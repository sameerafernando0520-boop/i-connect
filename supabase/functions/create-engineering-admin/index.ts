// ============================================================
// FILE: supabase/functions/create-engineering-admin/index.ts
// DEPLOY: supabase functions deploy create-engineering-admin
//
// Creates an engineering_admin account from the admin panel.
// Username-based login: email is <username>@engineering.iconnect.lk
// Engineering admins have full portal access (no permission toggles).
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const EA_DOMAIN = "engineering.iconnect.lk";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Auth header ───────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 2. Service-role admin client ─────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // ── 3. Caller client — verify identity ───────────────────
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: { headers: { Authorization: authHeader } },
        auth: { autoRefreshToken: false, persistSession: false },
      }
    );

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

    // ── 4. Confirm caller is admin ────────────────────────────
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
        JSON.stringify({
          error: "Only admins can create engineering admin accounts",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 5. Parse body ─────────────────────────────────────────
    const { username, full_name, password } = await req.json();

    if (!username || !full_name || !password) {
      return new Response(
        JSON.stringify({
          error: "username, full_name, and password are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const cleanUsername = username.trim().toLowerCase();
    const syntheticEmail = `${cleanUsername}@${EA_DOMAIN}`;

    // Validate username format
    if (!/^[a-z0-9._]+$/.test(cleanUsername)) {
      return new Response(
        JSON.stringify({
          error:
            "Username may only contain lowercase letters, numbers, dots and underscores",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 6. Check username uniqueness ──────────────────────────
    const { data: existing } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("email", syntheticEmail)
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({
          error: `Username "${cleanUsername}" is already taken`,
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 7. Create auth user ───────────────────────────────────
    const { data: createData, error: createError } =
      await supabaseAdmin.auth.admin.createUser({
        email: syntheticEmail,
        password: password,
        email_confirm: true,
        user_metadata: {
          full_name: full_name.trim(),
        },
      });

    if (createError) {
      console.error("createUser error:", createError);
      throw new Error(createError.message);
    }

    const newUserId = createData.user.id;

    // ── 8. Upsert public.users row ────────────────────────────
    // The on_auth_user_created trigger may pre-insert a row,
    // so we use upsert (onConflict: id) to avoid duplicate-key errors.
    const { error: insertError } = await supabaseAdmin.from("users").upsert(
      {
        id: newUserId,
        email: syntheticEmail,
        full_name: full_name.trim(),
        role: "engineering_admin",
        created_at: new Date().toISOString(),
      },
      { onConflict: "id" }
    );

    if (insertError) {
      // Roll back auth user if profile insert failed
      await supabaseAdmin.auth.admin.deleteUser(newUserId);
      console.error("Insert error:", insertError);
      throw new Error(insertError.message);
    }

    return new Response(
      JSON.stringify({
        success: true,
        user_id: newUserId,
        username: cleanUsername,
        message: `Engineering admin "${full_name.trim()}" created successfully`,
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
