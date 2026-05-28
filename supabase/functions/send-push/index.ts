// supabase/functions/send-push/index.ts
// v10.1 — Added step-by-step error reporting for debugging

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

// ════════════════════════════════════════════════════════════
//  CRYPTO
// ════════════════════════════════════════════════════════════

function uint8ToBase64url(arr: Uint8Array): string {
  let bin = ""
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i])
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function strToBase64url(str: string): string {
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function importPkcs8(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\n/g, "")
    .replace(/\r/g, "")
    .replace(/\s/g, "")
  const raw = atob(b64)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)

  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  )
}

async function mintGoogleJwt(
  email: string,
  privateKey: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const hdr = strToBase64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))
  const pay = strToBase64url(
    JSON.stringify({
      iss: email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  )
  const input = new TextEncoder().encode(`${hdr}.${pay}`)
  const key = await importPkcs8(privateKey)
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, input)
  )
  return `${hdr}.${pay}.${uint8ToBase64url(sig)}`
}

async function getGoogleAccessToken(sa: {
  client_email: string
  private_key: string
}): Promise<string> {
  const jwt = await mintGoogleJwt(sa.client_email, sa.private_key)
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json()
  if (!data.access_token) {
    throw new Error(`OAuth2 response: ${JSON.stringify(data)}`)
  }
  return data.access_token
}

// ════════════════════════════════════════════════════════════
//  FCM v1
// ════════════════════════════════════════════════════════════

interface PushResult {
  ok: boolean
  token: string
  error?: string
}

async function fcmSend(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string
): Promise<PushResult> {
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            notification: { title, body },
            data: { type: "broadcast" },
            android: {
              priority: "high",
              notification: { channel_id: "high_importance_channel" },
            },
            apns: {
              payload: { aps: { sound: "default", badge: 1 } },
            },
          },
        }),
      }
    )
    if (res.ok) return { ok: true, token: deviceToken }
    const errText = await res.text()
    return { ok: false, token: deviceToken, error: errText }
  } catch (e) {
    return { ok: false, token: deviceToken, error: (e as Error).message }
  }
}

// ════════════════════════════════════════════════════════════
//  MAIN HANDLER
// ════════════════════════════════════════════════════════════

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const respond = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })

  // ── All errors return 200 with error field so Flutter can read them ──
  try {
    // ── STEP 1: Supabase client ──────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseUrl || !serviceRoleKey) {
      return respond({ error: "Missing SUPABASE_URL or SERVICE_ROLE_KEY", step: 1 })
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // ── STEP 2: Verify admin ─────────────────────────────
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return respond({ error: "No Authorization header", step: 2 })
    }

    const token = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !user) {
      return respond({ error: `Auth failed: ${authErr?.message || "no user"}`, step: 2 })
    }

    const { data: profile } = await supabase
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single()
    if (profile?.role !== "admin") {
      return respond({ error: `Not admin: role=${profile?.role}`, step: 2 })
    }

    // ── STEP 3: Parse body ───────────────────────────────
    let title: string, msgBody: string, audience: string, category: string | undefined
    try {
      const parsed = await req.json()
      title = parsed.title
      msgBody = parsed.body
      audience = parsed.audience || "all_customers"
      category = parsed.category
    } catch (parseErr) {
      return respond({ error: `Body parse failed: ${(parseErr as Error).message}`, step: 3 })
    }

    if (!title || !msgBody) {
      return respond({ error: "title and body required", step: 3 })
    }

    // ── STEP 4: Resolve users ────────────────────────────
    let userIds: string[] = []
    try {
      if (audience === "specific_machine" && category) {
        const { data: catMachines } = await supabase
          .from("machine_catalog")
          .select("id")
          .eq("category", category)
          .eq("is_active", true)
        if (catMachines && catMachines.length > 0) {
          const catIds = catMachines.map((m: any) => m.id)
          const { data: custMachines } = await supabase
            .from("customer_machines")
            .select("user_id")
            .in("catalog_machine_id", catIds)
          const ids = new Set<string>()
          for (const cm of custMachines || []) ids.add(cm.user_id)
          userIds = Array.from(ids)
        }
      } else {
        let query = supabase.from("users").select("id")
        if (audience === "all_customers") query = query.eq("role", "customer")
        else if (audience === "all_engineers") query = query.eq("role", "engineer")
        else if (audience === "all_users") query = query.neq("role", "admin")
        else query = query.eq("role", "customer")
        const { data: users } = await query
        userIds = (users || []).map((u: any) => u.id)
      }
    } catch (userErr) {
      return respond({ error: `User query failed: ${(userErr as Error).message}`, step: 4 })
    }

    if (userIds.length === 0) {
      return respond({ sent: 0, failed: 0, total_tokens: 0, stale_cleaned: 0 })
    }

    // ── STEP 5: Get FCM tokens ───────────────────────────
    let uniqueTokens: string[] = []
    try {
      let allTokens: string[] = []
      const CHUNK = 200
      for (let i = 0; i < userIds.length; i += CHUNK) {
        const chunk = userIds.slice(i, i + CHUNK)
        const { data: rows } = await supabase
          .from("fcm_tokens")
          .select("token")
          .in("user_id", chunk)
          .eq("is_active", true)
        if (rows) allTokens = allTokens.concat(rows.map((r: any) => r.token))
      }
      uniqueTokens = [...new Set(allTokens)]
    } catch (tokenErr) {
      return respond({ error: `Token query failed: ${(tokenErr as Error).message}`, step: 5 })
    }

    if (uniqueTokens.length === 0) {
      return respond({ sent: 0, failed: 0, total_tokens: 0, stale_cleaned: 0 })
    }

    // ── STEP 6: Load Firebase service account ────────────
    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")
    if (!saJson) {
      return respond({ error: "FIREBASE_SERVICE_ACCOUNT secret not set", step: 6 })
    }

    let sa: any
    try {
      sa = JSON.parse(saJson)
    } catch (jsonErr) {
      return respond({
        error: `Secret is not valid JSON: ${(jsonErr as Error).message}. First 50 chars: ${saJson.substring(0, 50)}`,
        step: 6,
      })
    }

    if (!sa.private_key) {
      return respond({
        error: `Secret missing private_key. Keys found: ${Object.keys(sa).join(", ")}`,
        step: 6,
      })
    }
    if (!sa.client_email) {
      return respond({ error: "Secret missing client_email", step: 6 })
    }
    if (!sa.project_id) {
      return respond({ error: "Secret missing project_id", step: 6 })
    }

    // ── STEP 7: Get Google OAuth2 access token ───────────
    let accessToken: string
    try {
      accessToken = await getGoogleAccessToken(sa)
    } catch (oauthErr) {
      return respond({
        error: `Google OAuth2 failed: ${(oauthErr as Error).message}`,
        step: 7,
        project_id: sa.project_id,
        client_email: sa.client_email,
      })
    }

    // ── STEP 8: Send FCM pushes ──────────────────────────
    const BATCH = 25
    const results: PushResult[] = []
    try {
      for (let i = 0; i < uniqueTokens.length; i += BATCH) {
        const batch = uniqueTokens.slice(i, i + BATCH)
        const settled = await Promise.allSettled(
          batch.map((tok) =>
            fcmSend(accessToken, sa.project_id, tok, title, msgBody)
          )
        )
        for (const s of settled) {
          results.push(
            s.status === "fulfilled"
              ? s.value
              : { ok: false, token: "", error: String(s.reason) }
          )
        }
      }
    } catch (sendErr) {
      return respond({ error: `FCM send failed: ${(sendErr as Error).message}`, step: 8 })
    }

    const sent = results.filter((r) => r.ok).length
    const failed = results.filter((r) => !r.ok).length

    // ── STEP 9: Clean stale tokens ───────────────────────
    const stale = results
      .filter(
        (r) =>
          !r.ok &&
          r.token &&
          r.error &&
          /UNREGISTERED|NOT_FOUND|INVALID_ARGUMENT/.test(r.error)
      )
      .map((r) => r.token)

    if (stale.length > 0) {
      try {
        await supabase
          .from("fcm_tokens")
          .update({ is_active: false, updated_at: new Date().toISOString() })
          .in("token", stale)
      } catch (_) {
        // Non-critical
      }
    }

    return respond({
      sent,
      failed,
      total_tokens: uniqueTokens.length,
      stale_cleaned: stale.length,
    })
  } catch (e) {
    console.error("send-push unhandled error:", e)
    return respond({ error: `Unhandled: ${(e as Error).message}`, step: "crash" })
  }
})