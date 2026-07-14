// Edge Function: mollie-webhook
//
// Wordt door Mollie zelf aangeroepen (server-to-server, niet door de browser)
// zodra de status van een betaling verandert. Haalt de actuele status bij
// Mollie op (nooit de status uit de aanroep zelf vertrouwen — dat kan
// vervalst worden), werkt `betalingen.status` bij, en kent bij succes de
// bundel toe aan het lid. Stuurt daarna best-effort een bevestigingsmail
// via Resend (een mislukte mail mag de betaalverwerking nooit blokkeren).
//
// Benodigde secrets: MOLLIE_API_KEY, RESEND_API_KEY, RESEND_FROM (optioneel,
// valt terug op onboarding@resend.dev).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  try {
    const body = await req.text();
    const params = new URLSearchParams(body);
    const paymentId = params.get('id');
    if (!paymentId) return new Response('Geen payment id', { status: 400 });

    const mollieRes = await fetch(`https://api.mollie.com/v2/payments/${paymentId}`, {
      headers: { 'Authorization': `Bearer ${Deno.env.get('MOLLIE_API_KEY')}` },
    });
    if (!mollieRes.ok) return new Response('Kon betaling niet ophalen bij Mollie', { status: 502 });
    const molliePayment = await mollieRes.json();

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: betaling } = await supabaseAdmin
      .from('betalingen').select('*').eq('mollie_payment_id', paymentId).maybeSingle();
    if (!betaling) return new Response('Betaling niet gevonden', { status: 404 });

    let nieuweStatus = 'open';
    if (molliePayment.status === 'paid') nieuweStatus = 'betaald';
    else if (['failed', 'expired', 'canceled'].includes(molliePayment.status)) nieuweStatus = 'mislukt';

    if (nieuweStatus === betaling.status) {
      // Mollie kan dezelfde webhook meerdere keren sturen — niets te doen.
      return new Response('OK (geen wijziging)', { status: 200 });
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
        const onderwerp = nieuweStatus === 'betaald'
          ? 'Betaling gelukt — Pickleball Den Haag'
          : 'Betaling niet gelukt — Pickleball Den Haag';
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
            html: inhoud,
          }),
        });
      } catch (_e) {
        // Mail-fout mag de betaalverwerking niet blokkeren.
      }
    }

    return new Response('OK', { status: 200 });
  } catch (e) {
    return new Response('Onverwachte fout: ' + (e as Error).message, { status: 500 });
  }
});
