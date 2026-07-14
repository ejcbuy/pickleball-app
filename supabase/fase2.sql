-- ============================================================
-- Pickleball Den Haag — Fase 2: server-side functies
--
-- Voer dit bestand uit in de Supabase SQL Editor, ná schema.sql
-- en de kolombeveiligings-fix uit Fase 1. Dit voegt alleen functies/
-- triggers/policies toe, verandert geen bestaande tabellen of data.
--
-- Twee acties in Fase 2 raken de rij van een ándere speler dan wie
-- de actie uitvoert, en kunnen daarom niet als gewone client-side
-- update via RLS:
--   1. Wachtlijst-promotie: als iemand zich uitschrijft, moet de
--      eerstvolgende op de wachtlijst automatisch deelnemer worden.
--   2. Wedstrijduitslag: elke speler mag een uitslag invoeren, maar
--      dat werkt de rating/wins/matches van alle 4 spelers bij —
--      niet alleen die van de invoerder. De kolombeveiliging uit
--      Fase 1 blokkeert dit terecht voor gewone client-updates, dus
--      dit gaat via een beveiligde functie met een expliciete
--      "systeem-update" markering die de trigger herkent.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Wachtlijst-promotie
-- ------------------------------------------------------------

create or replace function promoveer_wachtlijst()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  volgende record;
begin
  if old.status = 'deelnemer' then
    select sd.sessie_id, sd.lid_id into volgende
    from sessie_deelnemers sd
    where sd.sessie_id = old.sessie_id and sd.status = 'wachtlijst'
    order by sd.positie asc nulls last, sd.created_at asc
    limit 1;

    if found then
      update sessie_deelnemers
      set status = 'deelnemer', positie = null
      where sessie_id = volgende.sessie_id and lid_id = volgende.lid_id;
    end if;
  end if;
  return old;
end;
$$;

drop trigger if exists sessie_deelnemers_promoveer_wachtlijst on sessie_deelnemers;
create trigger sessie_deelnemers_promoveer_wachtlijst
  after delete on sessie_deelnemers
  for each row
  execute function promoveer_wachtlijst();

-- ------------------------------------------------------------
-- 2) Wedstrijduitslag + ELO-rating
-- ------------------------------------------------------------

-- Kolombeveiliging uit Fase 1 herzien: naast bestuur/penningmeester
-- mag ook een "systeem-update" (via app.systeem_update, lokaal aan
-- de transactie gezet door registreer_wedstrijd hieronder) de
-- beschermde velden wijzigen. Een gewoon lid kan deze vlag zelf niet
-- zetten — die staat alleen aan binnen de functie hieronder.
create or replace function bescherm_leden_kolommen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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

create or replace function registreer_wedstrijd(
  p_team_a uuid[],
  p_team_b uuid[],
  p_score_a int,
  p_score_b int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organisatie_id uuid;
  v_wedstrijd_id uuid;
  v_rating_a numeric;
  v_rating_b numeric;
  v_verwacht_a numeric;
  v_verwacht_b numeric;
  v_werkelijk_a int;
  v_werkelijk_b int;
  v_delta_a int;
  v_delta_b int;
  v_k int := 24;
  v_lid_id uuid;
  v_alle_spelers uuid[];
begin
  if auth.uid() is null then
    raise exception 'Niet ingelogd';
  end if;
  if array_length(p_team_a, 1) <> 2 or array_length(p_team_b, 1) <> 2 then
    raise exception 'Elk team moet uit 2 spelers bestaan';
  end if;
  if p_score_a = p_score_b then
    raise exception 'Een wedstrijd kan niet gelijk eindigen';
  end if;

  v_alle_spelers := p_team_a || p_team_b;
  if (select count(distinct s) from unnest(v_alle_spelers) s) <> 4 then
    raise exception 'Elke speler mag maar één keer voorkomen';
  end if;

  v_organisatie_id := eigen_organisatie_id();
  if v_organisatie_id is null then
    raise exception 'Geen organisatie gevonden voor huidige gebruiker';
  end if;

  if exists (
    select 1 from leden where id = any(v_alle_spelers) and organisatie_id <> v_organisatie_id
  ) then
    raise exception 'Alle spelers moeten tot dezelfde organisatie behoren';
  end if;

  select avg(rating) into v_rating_a from leden where id = any(p_team_a);
  select avg(rating) into v_rating_b from leden where id = any(p_team_b);

  v_verwacht_a := 1.0 / (1 + power(10, (v_rating_b - v_rating_a) / 400.0));
  v_verwacht_b := 1 - v_verwacht_a;
  v_werkelijk_a := case when p_score_a > p_score_b then 1 else 0 end;
  v_werkelijk_b := 1 - v_werkelijk_a;
  v_delta_a := round(v_k * (v_werkelijk_a - v_verwacht_a));
  v_delta_b := round(v_k * (v_werkelijk_b - v_verwacht_b));

  insert into wedstrijden (organisatie_id, score_a, score_b)
  values (v_organisatie_id, p_score_a, p_score_b)
  returning id into v_wedstrijd_id;

  perform set_config('app.systeem_update', 'true', true);

  foreach v_lid_id in array p_team_a loop
    insert into wedstrijd_deelnemers (wedstrijd_id, lid_id, team) values (v_wedstrijd_id, v_lid_id, 'a');
    update leden set rating = rating + v_delta_a, matches = matches + 1,
      wins = wins + case when v_werkelijk_a = 1 then 1 else 0 end
      where id = v_lid_id;
  end loop;

  foreach v_lid_id in array p_team_b loop
    insert into wedstrijd_deelnemers (wedstrijd_id, lid_id, team) values (v_wedstrijd_id, v_lid_id, 'b');
    update leden set rating = rating + v_delta_b, matches = matches + 1,
      wins = wins + case when v_werkelijk_b = 1 then 1 else 0 end
      where id = v_lid_id;
  end loop;

  return v_wedstrijd_id;
end;
$$;

grant execute on function registreer_wedstrijd(uuid[], uuid[], int, int) to authenticated;

-- ------------------------------------------------------------
-- 3) Organisatie-instellingen (baanreservering-module aan/uit)
--    ontbrak nog: Fase 1 had alleen een SELECT-policy.
-- ------------------------------------------------------------

drop policy if exists "organisatie: bestuur/penningmeester werkt eigen organisatie bij" on organisaties;
create policy "organisatie: bestuur/penningmeester werkt eigen organisatie bij"
  on organisaties for update
  using (id = eigen_organisatie_id() and eigen_rol() in ('bestuur','penningmeester'))
  with check (id = eigen_organisatie_id());

-- ------------------------------------------------------------
-- 4) Baanreservering: boekingsvenster van 2 weken
--    Een baan kan pas gereserveerd worden vanaf 2 weken voor de
--    datum (en niet meer voor een datum in het verleden). Dit
--    voorkomt dat leden maanden vooruit alle sloten claimen, en
--    is de gangbare regel bij sportcentra die banen verhuren.
-- ------------------------------------------------------------

create or replace function valideer_baanreservering_venster()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.datum < current_date then
    raise exception 'Je kunt geen baan reserveren in het verleden.';
  end if;
  if new.datum > current_date + 14 then
    raise exception 'Deze baan kan pas vanaf 2 weken voor de datum gereserveerd worden.';
  end if;
  return new;
end;
$$;

drop trigger if exists baanreserveringen_venster on baanreserveringen;
create trigger baanreserveringen_venster
  before insert on baanreserveringen
  for each row
  execute function valideer_baanreservering_venster();
