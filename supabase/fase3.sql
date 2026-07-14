-- ============================================================
-- Pickleball Den Haag — Fase 3: echte Mollie-betalingen + meldingen
--
-- Voer dit bestand uit in de Supabase SQL Editor, ná schema.sql en
-- fase2.sql. Dit verandert alleen de kolombeveiligings-trigger op
-- 'leden' (voegt een uitzondering toe) — geen nieuwe tabellen, geen
-- dataverlies.
--
-- Waarom deze wijziging nodig is: de Mollie-webhook (Edge Function
-- 'mollie-webhook') werkt na een geslaagde betaling leden.bundel_id
-- bij, met de service_role key (bypassed RLS bewust, maar RLS en
-- triggers zijn twee verschillende dingen — de kolombeveiligings-
-- trigger uit Fase 1 zou deze update alsnog blokkeren omdat er geen
-- ingelogde gebruiker/rol aan de request hangt). Deze update herkent
-- nu expliciet requests die via de service_role key binnenkomen
-- (auth.role() = 'service_role') als vertrouwd systeemverkeer.
-- ============================================================

create or replace function bescherm_leden_kolommen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;
  if eigen_rol() in ('bestuur', 'penningmeester') then
    return new;
  end if;
  if coalesce(current_setting('app.systeem_update', true), 'false') = 'true' then
    return new;
  end if;
  new.rol := old.rol;
  new.organisatie_id := old.organisatie_id;
  new.actief := old.actief;
  new.rating := old.rating;
  new.wins := old.wins;
  new.matches := old.matches;
  new.bundel_id := old.bundel_id;
  new.gespeeld := old.gespeeld;
  new.email := old.email;
  return new;
end;
$$;

-- ------------------------------------------------------------
-- Betalingen lezen: leden lazen al hun eigen betalingen (Fase 1),
-- maar de Contributie-pagina heeft ook publieke bundelprijzen nodig
-- voor niet-ingelogde weergave-scenario's — die policy bestaat al
-- (bundels: lezen binnen eigen organisatie, Fase 2). Geen wijziging
-- nodig hier; deze sectie staat er ter documentatie.
-- ------------------------------------------------------------
-- Bewuste keuze (ongewijzigd sinds Fase 1): geen insert/update-policy
-- op 'betalingen' voor de 'authenticated' rol. Alle schrijfacties op
-- betalingen lopen via de Edge Functions met de service_role key.
