// supabase/functions/send-nudge-message/index.ts
// Admin sends a personal nudge message to a customer at any score level.
// 1. Logs the nudge in journey_nudges table
// 2. Inserts a notification row for the customer
// 3. Sends FCM push via existing send-push function

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
      suggestion_id,
      customer_id,
      admin_id,
      message,
      current_score,
    } = await req.json()

    if (!suggestion_id || !customer_id || !message) {
      return new Response(
        JSON.stringify({ error: 'suggestion_id, customer_id, and message required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── 1. Record nudge in journey_nudges table ───────────────
    await supabase.from('journey_nudges').insert({
      suggestion_id,
      customer_id,
      sent_by:       admin_id ?? null,
      message,
      score_at_send: current_score ?? null,
    })

    // ── 2. Insert in-app notification for customer ────────────
    await supabase.from('notifications').insert({
      user_id: customer_id,
      type:    'system',
      title:   '💬 A message from your advisor',
      body:    message,
      data: {
        suggestion_id,
        type: 'journey_nudge',
      },
    })

    // ── 3. Fetch FCM token and send push ──────────────────────
    const { data: tokenRow } = await supabase
      .from('fcm_tokens')
      .select('token')
      .eq('user_id', customer_id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (tokenRow?.token) {
      await supabase.functions.invoke('send-push', {
        body: {
          token: tokenRow.token,
          title: '💬 A message from your advisor',
          body:  message,
          data: {
            suggestion_id,
            type: 'journey_nudge',
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
