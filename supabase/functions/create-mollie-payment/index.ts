// Edge Function: create-mollie-payment
//
// Wordt aangeroepen door de ingelogde gebruiker (via supabaseClient.functions.invoke)
// wanneer die een bundel wil afrekenen. Maakt een echte Mollie-betaling aan en
// slaat een 'open' rij in `betalingen` op. Geeft de Mollie-checkout-URL terug
// waar de browser naartoe moet redirecten.
//
// Benodigde secrets (Supabase Dashboard -> Edge Functions -> Secrets):
//   MOLLIE_API_KEY  — je Mollie test- of live-sleutel (nooit in code/frontend)
//   APP_URL         — bijv. https://ejcbuy.github.io/pickleball-app
// SUPABASE_URL, SUPABASE_ANON_KEY en SUPABASE_SERVICE_ROLE_KEY staan al
// automatisch klaar in elke Edge Function, die hoef je niet zelf te zetten.

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
    const { bundelId } = await req.json();
    if (!bundelId) {
      return new Response(JSON.stringify({ error: 'bundelId ontbreekt' }), {
        status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Niet ingelogd' }), {
        status: 401, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // Client met de JWT van de aanroepende gebruiker, om te bepalen wie dit is.
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Niet ingelogd' }), {
        status: 401, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // Service-role client voor het lezen van de bundel en wegschrijven van de betaling.
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: bundel, error: bundelError } = await supabaseAdmin
      .from('bundels').select('*').eq('id', bundelId).maybeSingle();
    if (bundelError || !bundel) {
      return new Response(JSON.stringify({ error: 'Bundel niet gevonden' }), {
        status: 404, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const appUrl = Deno.env.get('APP_URL') || '';
    const mollieRes = await fetch('https://api.mollie.com/v2/payments', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('MOLLIE_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: { currency: 'EUR', value: Number(bundel.prijs).toFixed(2) },
        description: `${bundel.naam} — Pickleball Den Haag`,
        redirectUrl: `${appUrl}/ledenpanel.html?betaling=voltooid`,
        webhookUrl: `${Deno.env.get('SUPABASE_URL')}/functions/v1/mollie-webhook`,
        metadata: { lidId: user.id, bundelId: bundel.id },
      }),
    });

    if (!mollieRes.ok) {
      const errBody = await mollieRes.text();
      return new Response(JSON.stringify({ error: 'Mollie-fout: ' + errBody }), {
        status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }
    const molliePayment = await mollieRes.json();

    const { error: insertError } = await supabaseAdmin.from('betalingen').insert({
      lid_id: user.id,
      bundel_id: bundel.id,
      bedrag: bundel.prijs,
      methode: 'ideal',
      mollie_payment_id: molliePayment.id,
      status: 'open',
    });
    if (insertError) {
      return new Response(JSON.stringify({ error: 'Databasefout: ' + insertError.message }), {
        status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ checkoutUrl: molliePayment._links.checkout.href }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: 'Onverwachte fout: ' + (e as Error).message }), {
      status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
