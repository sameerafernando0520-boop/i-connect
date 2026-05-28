// supabase/functions/send-journey-notification/index.ts
// Sends a milestone notification to a customer.
// Called internally by update-journey-score when a threshold is crossed.
// 1. Inserts a notification row for the customer
// 2. Fetches their FCM token
// 3. Invokes the existing send-push function

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      customer_id,
      suggestion_id,
      milestone,
      title,
      body,
    } = await req.json()

    if (!customer_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'customer_id, title, and body required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── 1. Insert notification row for customer ───────────────
    await supabase.from('notifications').insert({
      user_id: customer_id,
      type:    'system',
      title,
      body,
      data: {
        suggestion_id,
        milestone:     String(milestone),
        type:          'journey_milestone',
      },
    })

    // ── 2. Get most recent FCM token for this user ────────────
    const { data: tokenRow } = await supabase
      .from('fcm_tokens')
      .select('token')
      .eq('user_id', customer_id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    // ── 3. Send push via existing send-push function ──────────
    if (tokenRow?.token) {
      await supabase.functions.invoke('send-push', {
        body: {
          token: tokenRow.token,
          title,
          body,
          data: {
            suggestion_id,
            milestone:   String(milestone),
            type:        'journey_milestone',
          },
        },
      })
    }

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
