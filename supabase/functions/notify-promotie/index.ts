// Edge Function: notify-promotie
//
// Wordt aangeroepen door een Supabase Database Webhook op de tabel
// `sessie_deelnemers` (event: Update). Stuurt een e-mail zodra iemand
// automatisch van de wachtlijst naar deelnemer is doorgeschoven (de
// database-trigger promoveer_wachtlijst() uit fase2.sql doet die
// promotie zelf al — deze functie stuurt alleen de melding erover).
//
// Setup (eenmalig, in het Supabase-dashboard):
//   Database -> Webhooks -> Create a new webhook
//     Table: sessie_deelnemers, Events: Update
//     Type: Supabase Edge Functions, Function: notify-promotie
//
// Benodigde secrets: RESEND_API_KEY, RESEND_FROM (optioneel).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;
    const oldRecord = payload.old_record;

    // Alleen mailen bij de overgang wachtlijst -> deelnemer.
    if (!(oldRecord?.status === 'wachtlijst' && record?.status === 'deelnemer')) {
      return new Response('Geen relevante wijziging', { status: 200 });
    }
    if (!Deno.env.get('RESEND_API_KEY')) {
      return new Response('Geen RESEND_API_KEY ingesteld, melding overgeslagen', { status: 200 });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: lid } = await supabaseAdmin
      .from('leden').select('naam,email').eq('id', record.lid_id).maybeSingle();
    const { data: sessie } = await supabaseAdmin
      .from('sessies').select('titel,dag,start_tijd').eq('id', record.sessie_id).maybeSingle();
    if (!lid || !sessie) return new Response('Lid of sessie niet gevonden', { status: 200 });

    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: Deno.env.get('RESEND_FROM') || 'onboarding@resend.dev',
        to: lid.email,
        subject: `Je bent ingeschreven voor ${sessie.titel}`,
        html: `<p>Hoi ${lid.naam},</p><p>Er kwam een plek vrij en je bent automatisch doorgeschoven van de wachtlijst naar deelnemer voor <b>${sessie.titel}</b> (${sessie.dag} ${(sessie.start_tijd || '').slice(0,5)}).</p>`,
      }),
    });

    return new Response('OK', { status: 200 });
  } catch (e) {
    return new Response('Onverwachte fout: ' + (e as Error).message, { status: 500 });
  }
});
