// ============================================================
// FILE: supabase/functions/create-engineer/index.ts
// DEPLOY: supabase functions deploy create-engineer
//
// Creates an engineer account using a username + password.
// No real email needed. Synthetic email: <username>@engineer.iconnect.lk
// Can be called by admin OR engineering_admin roles.
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ENGINEER_DOMAIN = "engineer.iconnect.lk";

serve(async (req) => {
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

    // ── 4. Confirm caller is admin or engineering_admin ──────
    const { data: callerProfile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("role")
      .eq("id", caller.id)
      .single();

    const allowedRoles = ["admin", "super_admin", "engineering_admin"];
    if (profileError || !allowedRoles.includes(callerProfile?.role)) {
      return new Response(
        JSON.stringify({
          error: "Only admins and engineering admins can create engineer accounts",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 5. Parse body ─────────────────────────────────────────
    const {
      username,
      full_name,
      password,
      phone_number = null,
      specializations = [],
      engineer_bio = null,
    } = await req.json();

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

    if (cleanUsername.length < 3) {
      return new Response(
        JSON.stringify({ error: "Username must be at least 3 characters" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (password.length < 8) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 8 characters" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const syntheticEmail = `${cleanUsername}@${ENGINEER_DOMAIN}`;

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
          phone_number: phone_number?.trim() ?? "",
        },
      });

    if (createError) {
      console.error("createUser error:", createError);
      throw new Error(createError.message);
    }

    const newUserId = createData.user.id;

    // ── 8. Upsert public.users row ────────────────────────────
    const { error: insertError } = await supabaseAdmin.from("users").upsert(
      {
        id: newUserId,
        email: syntheticEmail,
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
      await supabaseAdmin.auth.admin.deleteUser(newUserId);
      console.error("Insert error:", insertError);
      throw new Error(insertError.message);
    }

    return new Response(
      JSON.stringify({
        success: true,
        user_id: newUserId,
        username: cleanUsername,
        message: `Engineer "${full_name.trim()}" created successfully`,
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
