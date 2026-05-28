// This runs on Deno (TypeScript runtime) on Supabase's servers
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
  try {
    // These environment variables are automatically available
    // in every Supabase Edge Function — you don't set them
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Service role key bypasses RLS — needed because this runs
    // without a logged-in user
    const supabase = createClient(supabaseUrl, serviceKey);

    // Call the SQL function we created in the migration
    const { data, error } = await supabase.rpc("check_installment_reminders");

    if (error) throw error;

    // Return the result (e.g., { reminders_sent: 5, checked_at: "..." })
    return new Response(JSON.stringify({ success: true, ...data }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { headers: { "Content-Type": "application/json" }, status: 500 }
    );
  }
});