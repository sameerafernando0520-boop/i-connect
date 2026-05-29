-- Live engineer position per ticket, powering the customer's
-- "track your engineer" map when a ticket is en-route.

create table if not exists public.ticket_engineer_locations (
  ticket_id   uuid primary key references public.service_tickets(id) on delete cascade,
  engineer_id uuid not null references public.users(id) on delete cascade,
  lat         double precision not null,
  lng         double precision not null,
  heading     double precision,
  updated_at  timestamptz not null default now()
);

alter table public.ticket_engineer_locations enable row level security;

-- Read: the ticket's customer, the assigned engineer, or admin / eng-admin.
drop policy if exists tel_select on public.ticket_engineer_locations;
create policy tel_select on public.ticket_engineer_locations
  for select to authenticated
  using (
    exists (select 1 from public.service_tickets t
            where t.id = ticket_id
              and (t.user_id = auth.uid() or t.assigned_to = auth.uid()))
    or exists (select 1 from public.users u
               where u.id = auth.uid() and u.role in ('admin','engineering_admin'))
  );

-- Write: only the engineer assigned to that ticket, for their own row.
drop policy if exists tel_insert on public.ticket_engineer_locations;
create policy tel_insert on public.ticket_engineer_locations
  for insert to authenticated
  with check (
    engineer_id = auth.uid()
    and exists (select 1 from public.service_tickets t
                where t.id = ticket_id and t.assigned_to = auth.uid())
  );

drop policy if exists tel_update on public.ticket_engineer_locations;
create policy tel_update on public.ticket_engineer_locations
  for update to authenticated
  using (engineer_id = auth.uid())
  with check (engineer_id = auth.uid());

-- Enable realtime (idempotent).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ticket_engineer_locations'
  ) then
    alter publication supabase_realtime add table public.ticket_engineer_locations;
  end if;
end $$;
