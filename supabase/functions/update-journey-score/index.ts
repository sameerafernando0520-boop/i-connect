// supabase/functions/update-journey-score/index.ts
// Admin calls this when they move the journey slider.
// - Updates journey_score + stage_note in machine_suggestions
// - Fires milestone notifications for any thresholds newly crossed
// - At 100%: inserts follow-up notifications for all admin accounts

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
      new_score,    // 0–100, set by admin slider
      stage_note,   // optional internal note — NOT shown to customer
      admin_id,
    } = await req.json()

    if (!suggestion_id || new_score === undefined) {
      return new Response(
        JSON.stringify({ error: 'suggestion_id and new_score required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Clamp to valid range
    const score = Math.max(0, Math.min(100, Math.round(new_score)))

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── 1. Fetch current suggestion state ─────────────────────
    const { data: suggestion, error: fetchErr } = await supabase
      .from('machine_suggestions')
      .select(`
        id,
        customer_id,
        journey_score,
        milestone_25_sent,
        milestone_50_sent,
        milestone_75_sent,
        milestone_100_sent,
        batch:suggestion_batches!batch_id(
          note,
          machine:machine_catalog!machine_id(
            machine_name
          )
        )
      `)
      .eq('id', suggestion_id)
      .single()

    if (fetchErr || !suggestion) {
      return new Response(
        JSON.stringify({ error: 'Suggestion not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const previousScore = (suggestion.journey_score as number) ?? 0

    // machine_name from the catalog (used in notification text)
    const batchData = suggestion.batch as Record<string, unknown> | null
    const machineData = batchData?.machine as Record<string, unknown> | null
    const machineName = (machineData?.machine_name as string | null) ?? 'your next machine'

    // ── 2. Update score + stage note ──────────────────────────
    await supabase
      .from('machine_suggestions')
      .update({
        journey_score:    score,
        stage_note:       stage_note ?? null,
        score_updated_by: admin_id ?? null,
        score_updated_at: new Date().toISOString(),
      })
      .eq('id', suggestion_id)

    // ── 3. Check which milestones are newly crossed ───────────
    // e.g. moving from 20% → 60% fires BOTH 25% and 50%
    const milestones = [
      {
        threshold: 25,
        sent:      suggestion.milestone_25_sent as boolean,
        field:     'milestone_25_sent',
        title:     '🌱 Your journey has begun',
        body:      `Your advisor has marked a new step in your journey toward the ${machineName}.`,
      },
      {
        threshold: 50,
        sent:      suggestion.milestone_50_sent as boolean,
        field:     'milestone_50_sent',
        title:     '🚀 You\'re halfway there',
        body:      `You\'re halfway to your next upgrade. The ${machineName} could be the right fit for your business.`,
      },
      {
        threshold: 75,
        sent:      suggestion.milestone_75_sent as boolean,
        field:     'milestone_75_sent',
        title:     '⚡ Almost ready',
        body:      `Your business is almost ready for the next step. The ${machineName} could be waiting for you.`,
      },
      {
        threshold: 100,
        sent:      suggestion.milestone_100_sent as boolean,
        field:     'milestone_100_sent',
        title:     '🎯 It\'s time',
        body:      `You\'ve reached your next journey milestone. Let\'s talk about making it happen.`,
      },
    ]

    const firedMilestones: number[] = []

    for (const m of milestones) {
      // Fire only if: new score crosses threshold AND previous didn't AND not already sent
      if (score >= m.threshold && previousScore < m.threshold && !m.sent) {
        // Mark as sent first (idempotent guard)
        await supabase
          .from('machine_suggestions')
          .update({ [m.field]: true })
          .eq('id', suggestion_id)

        // Send notification via dedicated function
        await supabase.functions.invoke('send-journey-notification', {
          body: {
            customer_id:   suggestion.customer_id,
            suggestion_id,
            milestone:     m.threshold,
            title:         m.title,
            body:          m.body,
          },
        })

        firedMilestones.push(m.threshold)
      }
    }

    // ── 4. At 100%: notify all admins to follow up personally ─
    if (score === 100 && previousScore < 100) {
      const { data: admins } = await supabase
        .from('users')
        .select('id')
        .in('role', ['admin', 'marketing_admin'])

      const { data: customer } = await supabase
        .from('users')
        .select('full_name')
        .eq('id', suggestion.customer_id)
        .single()

      const customerName = (customer?.full_name as string | null) ?? 'A customer'

      for (const admin of admins ?? []) {
        await supabase.from('notifications').insert({
          user_id: admin.id,
          type:    'system',
          title:   '🎯 Journey Complete — Follow Up Now',
          body:    `${customerName} is ready for their next machine. Follow up personally.`,
          data: {
            customer_id:   suggestion.customer_id,
            suggestion_id,
            action:        'follow_up',
          },
        })
      }
    }

    return new Response(
      JSON.stringify({ success: true, score, firedMilestones }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
