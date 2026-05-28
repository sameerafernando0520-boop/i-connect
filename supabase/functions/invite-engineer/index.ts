// ============================================================
// FILE: supabase/functions/invite-engineer/index.ts
// DEPLOY: supabase functions deploy invite-engineer
//
// v20 CHANGE: switched from inviteUserByEmail (magic-link only)
//   to createUser with a generated temp password.
//   The temp password is returned to the admin so they can share
//   it with the engineer via WhatsApp / phone.
//   Engineer logs in → Settings → Change Password on first use.
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Temp password generator ──────────────────────────────────
// Format: "iF@" + 6 alphanumeric + 1 symbol + 2 digits  (12 chars)
// Meets uppercase / lowercase / digit / special requirements.
function generateTempPassword(): string {
  const upper = "ABCDEFGHJKMNPQRSTUVWXYZ";
  const lower = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$";

  const pick = (s: string) => s[Math.floor(Math.random() * s.length)];
  const alphanum = upper + lower + digits;

  let mid = "";
  for (let i = 0; i < 4; i++) mid += pick(alphanum);

  // Guaranteed to include at least one of each required class
  return (
    "iF@" +
    pick(upper) +
    mid +
    pick(lower) +
    pick(symbols) +
    pick(digits) +
    pick(digits)
  );
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Read auth header from the incoming request ────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 2. Admin client (service role — never expose in app) ─
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // ── 3. Regular client — verify caller identity ───────────
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: { headers: { Authorization: authHeader } },
        auth: { autoRefreshToken: false, persistSession: false },
      }
    );

    // ── 4. Get the calling user ───────────────────────────────
    const {
      data: { user: caller },
      error: callerError,
    } = await supabaseClient.auth.getUser();

    if (callerError || !caller) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 5. Confirm caller is admin ────────────────────────────
    const { data: callerProfile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("role")
      .eq("id", caller.id)
      .single();

    if (
      profileError ||
      !["admin", "super_admin"].includes(callerProfile?.role)
    ) {
      return new Response(
        JSON.stringify({ error: "Only admins can invite engineers" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 6. Parse request body ─────────────────────────────────
    const {
      email,
      full_name,
      phone_number,
      specializations = [],
      engineer_bio = null,
    } = await req.json();

    if (!email || !full_name) {
      return new Response(
        JSON.stringify({ error: "email and full_name are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 7. Check if email already exists ─────────────────────
    const { data: existing } = await supabaseAdmin
      .from("users")
      .select("id, email")
      .eq("email", email.toLowerCase().trim())
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({ error: "An account with this email already exists" }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 8. Generate a temporary password ─────────────────────
    const tempPassword = generateTempPassword();

    // ── 9. Create auth account with temp password ─────────────
    //  email_confirm: true  → account is immediately active,
    //  no magic-link step needed.
    const { data: createData, error: createError } =
      await supabaseAdmin.auth.admin.createUser({
        email: email.toLowerCase().trim(),
        password: tempPassword,
        email_confirm: true,
        user_metadata: {
          full_name: full_name.trim(),
          phone_number: phone_number?.trim() ?? "",
        },
      });

    if (createError) {
      console.error("createUser error:", createError);
      throw new Error(createError.message);
    }

    const newUserId = createData.user.id;

    // ── 10. Insert engineer profile row ───────────────────────
    const { error: insertError } = await supabaseAdmin.from("users").upsert(
      {
        id: newUserId,
        email: email.toLowerCase().trim(),
        full_name: full_name.trim(),
        phone_number: phone_number?.trim() ?? null,
        role: "engineer",
        specializations: specializations,
        engineer_bio: engineer_bio,
        availability_status: "offline",
        avg_rating: 0.0,
        total_resolved: 0,
        created_at: new Date().toISOString(),
      },
      { onConflict: "id" }
    );

    if (insertError) {
      // Roll back: delete the auth user if profile insert failed
      await supabaseAdmin.auth.admin.deleteUser(newUserId);
      console.error("Insert error:", insertError);
      throw new Error(insertError.message);
    }

    // ── 11. Return success + temp password ────────────────────
    //  The admin shows this to the engineer (via WhatsApp / phone).
    //  The engineer must change it on first login.
    return new Response(
      JSON.stringify({
        success: true,
        user_id: newUserId,
        temp_password: tempPassword,
        message: `Engineer account created for ${email}`,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
