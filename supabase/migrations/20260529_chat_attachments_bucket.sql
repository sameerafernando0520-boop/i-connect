-- Public storage bucket for chat attachments (images, documents, voice notes).
-- Replaces the previously-referenced (but non-existent) 'ticket-attachments'
-- bucket, fixing the broken image-attach upload in the customer ticket chat.

insert into storage.buckets (id, name, public)
values ('chat-attachments', 'chat-attachments', true)
on conflict (id) do nothing;

-- Authenticated users may upload.
drop policy if exists "chat_attachments_insert" on storage.objects;
create policy "chat_attachments_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-attachments');

-- Anyone may read (public bucket; explicit policy for API access).
drop policy if exists "chat_attachments_read" on storage.objects;
create policy "chat_attachments_read"
  on storage.objects for select to public
  using (bucket_id = 'chat-attachments');

-- Authenticated may update/delete (retry / cleanup).
drop policy if exists "chat_attachments_update" on storage.objects;
create policy "chat_attachments_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'chat-attachments')
  with check (bucket_id = 'chat-attachments');

drop policy if exists "chat_attachments_delete" on storage.objects;
create policy "chat_attachments_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-attachments');
