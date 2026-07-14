// Edge Function: mollie-webhook
//
// Wordt normaliter door Mollie zelf aangeroepen (server-to-server) zodra de
// status van een betaling verandert. Haalt de actuele status bij Mollie op
// (nooit de status uit de aanroep zelf vertrouwen — dat kan vervalst worden),
// werkt `betalingen.status` bij, en kent bij succes de bundel toe aan het
// lid. Stuurt daarna best-effort een bevestigingsmail via Resend (een
// mislukte mail mag de betaalverwerking nooit blokkeren).
//
// CORS staat aan omdat deze functie in dry-run-modus ook rechtstreeks vanuit
// de browser (fake-mollie-checkout.html) wordt aangeroepen — de echte Mollie-
// server stoort zich niet aan CORS-headers, dus dit is voor beide paden veilig.
//
// Benodigde secrets: MOLLIE_API_KEY, RESEND_API_KEY, RESEND_FROM (optioneel,
// valt terug op onboarding@resend.dev).
//
// DRY RUN: zolang MOLLIE_API_KEY niet gezet is, wordt voor betalingen met een
// 'dryrun_'-voorvoegsel de status uit het request zelf gehaald (gezet door
// fake-mollie-checkout.html) in plaats van bij Mollie opgevraagd. Zodra
// MOLLIE_API_KEY wél gezet is, wordt dit pad hier serverside geblokkeerd —
// een 'dryrun_'-id kan dan nooit meer een echte betaling voorwenden, ook niet
// als iemand deze endpoint direct met een verzonnen id aanroept.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const body = await req.text();
    const params = new URLSearchParams(body);
    const paymentId = params.get('id');
    if (!paymentId) return new Response('Geen payment id', { status: 400, headers: CORS_HEADERS });

    const mollieKey = Deno.env.get('MOLLIE_API_KEY');
    const isDryRunId = paymentId.startsWith('dryrun_');

    if (isDryRunId && mollieKey) {
      // Zodra er een echte Mollie-sleutel actief is, bestaat dry run niet
      // meer — een 'dryrun_'-id is dan altijd ongeldig, punt uit.
      return new Response('Dry run is uitgeschakeld (MOLLIE_API_KEY is actief)', { status: 400, headers: CORS_HEADERS });
    }
    if (!isDryRunId && !mollieKey) {
      return new Response('Geen MOLLIE_API_KEY ingesteld, kan echte betaling niet verifiëren', { status: 500, headers: CORS_HEADERS });
    }

    let molliestatus;
    if (isDryRunId) {
      // Simulatie: de teststatus komt van fake-mollie-checkout.html zelf.
      molliestatus = params.get('simuleer') === 'mislukt' ? 'failed' : 'paid';
    } else {
      const mollieRes = await fetch(`https://api.mollie.com/v2/payments/${paymentId}`, {
        headers: { 'Authorization': `Bearer ${mollieKey}` },
      });
      if (!mollieRes.ok) return new Response('Kon betaling niet ophalen bij Mollie', { status: 502, headers: CORS_HEADERS });
      const molliePayment = await mollieRes.json();
      molliestatus = molliePayment.status;
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: betaling } = await supabaseAdmin
      .from('betalingen').select('*').eq('mollie_payment_id', paymentId).maybeSingle();
    if (!betaling) return new Response('Betaling niet gevonden', { status: 404, headers: CORS_HEADERS });

    let nieuweStatus = 'open';
    if (molliestatus === 'paid') nieuweStatus = 'betaald';
    else if (['failed', 'expired', 'canceled'].includes(molliestatus)) nieuweStatus = 'mislukt';

    if (nieuweStatus === betaling.status) {
      // Mollie kan dezelfde webhook meerdere keren sturen — niets te doen.
      return new Response('OK (geen wijziging)', { status: 200, headers: CORS_HEADERS });
    }

    await supabaseAdmin.from('betalingen').update({ status: nieuweStatus }).eq('id', betaling.id);

    const { data: lid } = await supabaseAdmin
      .from('leden').select('naam,email').eq('id', betaling.lid_id).maybeSingle();
    const { data: bundel } = await supabaseAdmin
      .from('bundels').select('naam').eq('id', betaling.bundel_id).maybeSingle();

    if (nieuweStatus === 'betaald') {
      await supabaseAdmin.from('leden')
        .update({ bundel_id: betaling.bundel_id, gespeeld: 0 })
        .eq('id', betaling.lid_id);
    }

    if (lid && Deno.env.get('RESEND_API_KEY')) {
      try {
        const dryRunPrefix = isDryRunId ? '[TESTSIMULATIE] ' : '';
        const onderwerp = nieuweStatus === 'betaald'
          ? `${dryRunPrefix}Betaling gelukt — Pickleball Den Haag`
          : `${dryRunPrefix}Betaling niet gelukt — Pickleball Den Haag`;
        const inhoud = nieuweStatus === 'betaald'
          ? `<p>Hoi ${lid.naam},</p><p>Je betaling voor <b>${bundel?.naam ?? 'je bundel'}</b> is gelukt. Veel speelplezier!</p>`
          : `<p>Hoi ${lid.naam},</p><p>Je betaling voor <b>${bundel?.naam ?? 'je bundel'}</b> is niet gelukt of geannuleerd. Probeer het gerust opnieuw via de Contributie-pagina.</p>`;
        await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: Deno.env.get('RESEND_FROM') || 'onboarding@resend.dev',
            to: lid.email,
            subject: onderwerp,
            html: (isDryRunId ? '<p><b>Dit is een testsimulatie, er is geen echt geld verwerkt.</b></p>' : '') + inhoud,
          }),
        });
      } catch (_e) {
        // Mail-fout mag de betaalverwerking niet blokkeren.
      }
    }

    return new Response('OK', { status: 200, headers: CORS_HEADERS });
  } catch (e) {
    return new Response('Onverwachte fout: ' + (e as Error).message, { status: 500, headers: CORS_HEADERS });
  }
});
