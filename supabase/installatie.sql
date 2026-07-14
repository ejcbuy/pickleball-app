-- ============================================================
-- Ledenpanel — installatiescript voor een NIEUWE klant
--
-- Dit is het enige SQL-bestand dat je nodig hebt om een verse
-- Supabase-project klaar te maken voor de app. Het vervangt de
-- oude volgorde van schema.sql → fase2.sql → fase3.sql: alle
-- fixes en uitbreidingen uit die drie bestanden zijn hierin al
-- samengevoegd tot hun eindversie.
--
-- GEBRUIK
--   1. Maak een nieuw, leeg Supabase-project aan.
--   2. Pas hieronder bij "AAN TE PASSEN" de clubnaam aan.
--   3. Dashboard → SQL Editor → New query → plak dit hele
--      bestand → Run.
--   4. Het script eindigt met een select die het nieuwe
--      organisatie-id toont. Kopieer dat id samen met de
--      clubnaam naar supabase-config.js (ORGANISATIE_ID,
--      ORGANISATIE_NAAM, ORGANISATIE_LOGO_TEKST).
--
-- Dit script is herhaalbaar: het begint met het opruimen van
-- alles wat een eerdere (mislukte) poging heeft achtergelaten,
-- zodat je het gerust opnieuw kunt draaien in hetzelfde project.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Opruimen (idempotent — mag altijd opnieuw gedraaid worden)
-- ------------------------------------------------------------

drop table if exists inschrijvingen cascade;
drop table if exists slots cascade;
drop table if exists sessie_templates cascade;
drop table if exists marktplaats cascade;
drop table if exists nieuws cascade;
drop table if exists wedstrijd_deelnemers cascade;
drop table if exists wedstrijden cascade;
drop table if exists betalingen cascade;
drop table if exists baanreserveringen cascade;
drop table if exists sessie_deelnemers cascade;
drop table if exists sessies cascade;
drop table if exists markt_items cascade;
drop table if exists nieuwsberichten cascade;
drop table if exists leden cascade;
drop table if exists bundels cascade;
drop table if exists organisaties cascade;
drop function if exists eigen_organisatie_id();
drop function if exists eigen_rol();
drop function if exists bescherm_leden_kolommen();
drop function if exists promoveer_wachtlijst();
drop function if exists registreer_wedstrijd(uuid[], uuid[], int, int);
drop function if exists valideer_baanreservering_venster();

-- ------------------------------------------------------------
-- Tabellen
-- ------------------------------------------------------------

create table organisaties (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  baanreservering_actief boolean not null default false,
  created_at timestamptz not null default now()
);

create table bundels (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  code text not null,              -- leesbare sleutel binnen de organisatie: 'starter' | 'bundle10' | 'quarterly' | 'incidenteel'
  naam text not null,
  prijs numeric not null,
  omschrijving text,
  speelbeurten int,                -- 999 = onbeperkt
  geldigheid text,
  actief boolean not null default true,
  unique (organisatie_id, code)
);

create table leden (
  id uuid primary key references auth.users(id) on delete cascade,
  organisatie_id uuid not null references organisaties(id),
  naam text not null,
  email text not null,
  niveau text,
  rating int not null default 1000,
  wins int not null default 0,
  matches int not null default 0,
  bundel_id uuid references bundels(id),
  gespeeld int not null default 0,
  actief boolean not null default true,
  rol text not null default 'lid' check (rol in ('lid','bestuur','penningmeester')),
  dupr_id text,
  dupr_rating numeric,
  created_at timestamptz not null default now()
);

create table sessies (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  titel text not null,
  type text not null check (type in ('session','clinic','tournament')),
  dag text,
  start_tijd time,
  eind_tijd time,
  locatie text,
  niveau text,
  max_spelers int,
  created_at timestamptz not null default now()
);

create table sessie_deelnemers (
  sessie_id uuid not null references sessies(id) on delete cascade,
  lid_id uuid not null references leden(id) on delete cascade,
  status text not null default 'deelnemer' check (status in ('deelnemer','wachtlijst')),
  positie int,                     -- volgorde binnen de wachtlijst; null als status = 'deelnemer'
  created_at timestamptz not null default now(),
  primary key (sessie_id, lid_id)
);

create table baanreserveringen (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  locatie text not null,           -- sportcomplex/vestiging
  baan_nummer int not null,        -- specifieke baan binnen die locatie
  datum date not null,
  start_tijd time not null,
  eind_tijd time not null,
  lid_id uuid references leden(id),
  created_at timestamptz not null default now(),
  unique (organisatie_id, locatie, baan_nummer, datum, start_tijd)
);

create table wedstrijden (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  score_a int not null,
  score_b int not null,
  gespeeld_op date not null default current_date,
  created_at timestamptz not null default now()
);

create table wedstrijd_deelnemers (
  wedstrijd_id uuid not null references wedstrijden(id) on delete cascade,
  lid_id uuid not null references leden(id),
  team text not null check (team in ('a','b')),
  primary key (wedstrijd_id, lid_id)
);

create table markt_items (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  titel text not null,
  prijs numeric not null,
  categorie text check (categorie in ('paddle','ball','other')),
  omschrijving text,
  status text not null default 'te_koop' check (status in ('te_koop','verkocht')),
  verkoper_id uuid references leden(id),
  created_at timestamptz not null default now()
);

create table nieuwsberichten (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  titel text not null,
  body text not null,
  categorie text,
  created_at timestamptz not null default now()
);

create table betalingen (
  id uuid primary key default gen_random_uuid(),
  lid_id uuid references leden(id),
  bundel_id uuid references bundels(id),
  bedrag numeric not null,
  methode text,
  mollie_payment_id text,
  status text not null default 'open' check (status in ('open','betaald','mislukt')),
  aangemaakt_op timestamptz not null default now()
);

create index on bundels (organisatie_id);
create index on leden (organisatie_id);
create index on sessies (organisatie_id);
create index on sessie_deelnemers (lid_id);
create index on baanreserveringen (organisatie_id);
create index on wedstrijden (organisatie_id);
create index on wedstrijd_deelnemers (lid_id);
create index on markt_items (organisatie_id);
create index on nieuwsberichten (organisatie_id);
create index on betalingen (lid_id);

-- ------------------------------------------------------------
-- Seed-data: organisatie + standaard bundels
--
-- AAN TE PASSEN: zet hieronder de echte clubnaam neer. Het
-- organisatie-id wordt automatisch gegenereerd (niet hardcoded,
-- zodat elke klant een eigen, uniek id krijgt) — dat id staat
-- aan het eind van dit script in de resultaten, kopieer het naar
-- supabase-config.js.
-- ------------------------------------------------------------

with nieuwe_organisatie as (
  insert into organisaties (naam, baanreservering_actief)
  values ('NAAM VAN DE CLUB HIER', false)
  returning id
)
insert into bundels (organisatie_id, code, naam, prijs, omschrijving, speelbeurten, geldigheid)
select id, 'starter', 'Starter', 15, 'Instapbundel voor nieuwe leden.', 4, '1 maand' from nieuwe_organisatie
union all
select id, 'bundle10', '10-rittenkaart', 60, '10 speelbeurten, te gebruiken binnen 3 maanden.', 10, '3 maanden' from nieuwe_organisatie
union all
select id, 'quarterly', 'Kwartaal onbeperkt', 90, 'Onbeperkt spelen gedurende een heel kwartaal.', 999, '3 maanden' from nieuwe_organisatie
union all
select id, 'incidenteel', 'Losse sessie', 6, 'Eenmalig meespelen, per keer afrekenen.', 1, '1 sessie' from nieuwe_organisatie;

-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------

alter table organisaties enable row level security;
alter table bundels enable row level security;
alter table leden enable row level security;
alter table sessies enable row level security;
alter table sessie_deelnemers enable row level security;
alter table baanreserveringen enable row level security;
alter table wedstrijden enable row level security;
alter table wedstrijd_deelnemers enable row level security;
alter table markt_items enable row level security;
alter table nieuwsberichten enable row level security;
alter table betalingen enable row level security;

-- Helperfuncties: security definer zodat ze de leden-tabel mogen
-- lezen zonder de RLS-policies die ze zelf voeden opnieuw te
-- triggeren (het standaard Supabase-patroon om recursie in
-- rol-gebaseerde policies te voorkomen).
create or replace function eigen_organisatie_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select organisatie_id from leden where id = auth.uid();
$$;

create or replace function eigen_rol()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select rol from leden where id = auth.uid();
$$;

-- organisaties
create policy "organisatie: alleen eigen organisatie lezen"
  on organisaties for select
  using (id = eigen_organisatie_id());

create policy "organisatie: bestuur/penningmeester werkt eigen organisatie bij"
  on organisaties for update
  using (id = eigen_organisatie_id() and eigen_rol() in ('bestuur','penningmeester'))
  with check (id = eigen_organisatie_id());

-- bundels
create policy "bundels: lezen binnen eigen organisatie"
  on bundels for select
  using (organisatie_id = eigen_organisatie_id());

create policy "bundels: bestuur/penningmeester voegt bundel toe"
  on bundels for insert
  with check (eigen_rol() in ('bestuur','penningmeester') and organisatie_id = eigen_organisatie_id());

create policy "bundels: bestuur/penningmeester bewerkt bundel"
  on bundels for update
  using (eigen_rol() in ('bestuur','penningmeester') and organisatie_id = eigen_organisatie_id())
  with check (organisatie_id = eigen_organisatie_id());

create policy "bundels: bestuur/penningmeester verwijdert bundel"
  on bundels for delete
  using (eigen_rol() in ('bestuur','penningmeester') and organisatie_id = eigen_organisatie_id());

-- leden
create policy "leden: zien leden van eigen organisatie"
  on leden for select
  using (organisatie_id = eigen_organisatie_id());

create policy "leden: eigen rij aanmaken bij registratie"
  on leden for insert
  with check (id = auth.uid());

create policy "leden: zichzelf bewerken"
  on leden for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "leden: bestuur/penningmeester bewerken leden van organisatie"
  on leden for update
  using (eigen_rol() in ('bestuur','penningmeester') and organisatie_id = eigen_organisatie_id())
  with check (organisatie_id = eigen_organisatie_id());

create policy "leden: bestuur/penningmeester verwijderen leden van organisatie"
  on leden for delete
  using (eigen_rol() in ('bestuur','penningmeester') and organisatie_id = eigen_organisatie_id());

-- RLS werkt op rij-niveau, niet op kolom-niveau: zonder onderstaande
-- trigger zou de "zichzelf bewerken"-policy hierboven een gewoon lid
-- toestaan om via een directe API-call (buiten de UI om) zijn eigen
-- rol, organisatie, actief-status, rating/wins/matches of bundel_id te
-- wijzigen. Bestuur/penningmeester mogen deze velden wel wijzigen (van
-- zichzelf én van andere leden). Twee vertrouwde uitzonderingen erbovenop:
--   - app.systeem_update: lokaal aan de transactie gezet door
--     registreer_wedstrijd() hieronder, zodat die functie de rating/
--     wins/matches van alle 4 spelers mag bijwerken.
--   - auth.role() = 'service_role': requests van de Edge Functions
--     (bijv. de Mollie-webhook die bundel_id bijwerkt na betaling).
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
  new.email := old.email;  -- e-mail wijzig je via Supabase Auth, niet hier
  return new;
end;
$$;

create trigger leden_bescherm_kolommen
  before update on leden
  for each row
  execute function bescherm_leden_kolommen();

-- sessies
create policy "sessies: lezen binnen eigen organisatie"
  on sessies for select
  using (organisatie_id = eigen_organisatie_id());

create policy "sessies: ingelogde leden voegen toe binnen eigen organisatie"
  on sessies for insert
  with check (organisatie_id = eigen_organisatie_id());

-- sessie_deelnemers
create policy "sessie_deelnemers: lezen binnen eigen organisatie"
  on sessie_deelnemers for select
  using (exists (select 1 from sessies s where s.id = sessie_id and s.organisatie_id = eigen_organisatie_id()));

create policy "sessie_deelnemers: eigen inschrijving aanmaken"
  on sessie_deelnemers for insert
  with check (lid_id = auth.uid());

create policy "sessie_deelnemers: eigen inschrijving verwijderen"
  on sessie_deelnemers for delete
  using (lid_id = auth.uid());

create policy "sessie_deelnemers: bestuur/penningmeester werkt status/positie bij"
  on sessie_deelnemers for update
  using (
    eigen_rol() in ('bestuur','penningmeester')
    and exists (select 1 from sessies s where s.id = sessie_id and s.organisatie_id = eigen_organisatie_id())
  )
  with check (
    exists (select 1 from sessies s where s.id = sessie_id and s.organisatie_id = eigen_organisatie_id())
  );

-- Wachtlijst-promotie: als iemand zich uitschrijft (status 'deelnemer'
-- wordt verwijderd), wordt de eerstvolgende op de wachtlijst automatisch
-- deelnemer. Draait als trigger (niet client-side) zodat dit ook werkt
-- als de uitschrijver niet dezelfde is als degene die gepromoveerd wordt.
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

create trigger sessie_deelnemers_promoveer_wachtlijst
  after delete on sessie_deelnemers
  for each row
  execute function promoveer_wachtlijst();

-- baanreserveringen (optionele module)
create policy "baanreserveringen: lezen binnen eigen organisatie"
  on baanreserveringen for select
  using (organisatie_id = eigen_organisatie_id());

create policy "baanreserveringen: eigen reservering aanmaken"
  on baanreserveringen for insert
  with check (organisatie_id = eigen_organisatie_id() and lid_id = auth.uid());

create policy "baanreserveringen: eigen reservering verwijderen"
  on baanreserveringen for delete
  using (lid_id = auth.uid());

-- Boekingsvenster van 2 weken: een baan kan pas gereserveerd worden
-- vanaf 2 weken voor de datum (en niet meer voor een datum in het
-- verleden). Voorkomt dat leden maanden vooruit alle sloten claimen.
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

create trigger baanreserveringen_venster
  before insert on baanreserveringen
  for each row
  execute function valideer_baanreservering_venster();

-- wedstrijden
create policy "wedstrijden: lezen binnen eigen organisatie"
  on wedstrijden for select
  using (organisatie_id = eigen_organisatie_id());

create policy "wedstrijden: ingelogde leden voegen uitslag toe binnen organisatie"
  on wedstrijden for insert
  with check (organisatie_id = eigen_organisatie_id());

-- wedstrijd_deelnemers
create policy "wedstrijd_deelnemers: lezen binnen eigen organisatie"
  on wedstrijd_deelnemers for select
  using (exists (select 1 from wedstrijden w where w.id = wedstrijd_id and w.organisatie_id = eigen_organisatie_id()));

create policy "wedstrijd_deelnemers: ingelogde leden voegen deelnemers toe binnen organisatie"
  on wedstrijd_deelnemers for insert
  with check (exists (select 1 from wedstrijden w where w.id = wedstrijd_id and w.organisatie_id = eigen_organisatie_id()));

-- Wedstrijduitslag + ELO-rating (K=24): elke speler mag een uitslag
-- invoeren, maar dat werkt de rating/wins/matches van alle 4 spelers
-- bij — niet alleen die van de invoerder. De kolombeveiliging hierboven
-- blokkeert dit terecht voor gewone client-updates, dus dit gaat via
-- een beveiligde functie met een expliciete "systeem-update"-markering
-- die de trigger herkent (app.systeem_update).
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

-- markt_items
create policy "markt_items: lezen binnen eigen organisatie"
  on markt_items for select
  using (organisatie_id = eigen_organisatie_id());

create policy "markt_items: ingelogde leden plaatsen eigen item binnen organisatie"
  on markt_items for insert
  with check (verkoper_id = auth.uid() and organisatie_id = eigen_organisatie_id());

create policy "markt_items: eigenaar bewerkt eigen item (bijv. status)"
  on markt_items for update
  using (verkoper_id = auth.uid())
  with check (verkoper_id = auth.uid());

create policy "markt_items: eigenaar verwijdert eigen item"
  on markt_items for delete
  using (verkoper_id = auth.uid());

-- nieuwsberichten
create policy "nieuwsberichten: lezen binnen eigen organisatie"
  on nieuwsberichten for select
  using (organisatie_id = eigen_organisatie_id());

create policy "nieuwsberichten: ingelogde leden plaatsen bericht binnen organisatie"
  on nieuwsberichten for insert
  with check (organisatie_id = eigen_organisatie_id());

-- betalingen
create policy "betalingen: eigen betalingen lezen"
  on betalingen for select
  using (lid_id = auth.uid());

create policy "betalingen: bestuur/penningmeester lezen betalingen van organisatie"
  on betalingen for select
  using (
    eigen_rol() in ('bestuur','penningmeester')
    and exists (select 1 from leden l where l.id = betalingen.lid_id and l.organisatie_id = eigen_organisatie_id())
  );

-- Bewuste keuze: geen insert/update-policy op 'betalingen' voor de
-- 'authenticated' rol. Alle schrijfacties op betalingen lopen via de
-- Edge Functions (create-mollie-payment, mollie-webhook) met de
-- service_role key — nooit vanuit de client.

-- ------------------------------------------------------------
-- Klaar. Kopieer het onderstaande organisatie-id + naam naar
-- supabase-config.js (ORGANISATIE_ID / ORGANISATIE_NAAM).
-- ------------------------------------------------------------

select id, naam from organisaties order by created_at desc limit 1;
