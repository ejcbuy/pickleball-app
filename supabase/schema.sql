-- ============================================================
-- Pickleball Den Haag — Fase 1: Database & Authenticatie
--
-- Voer dit bestand EENMALIG volledig uit in de Supabase SQL
-- Editor van je project (Dashboard → SQL Editor → New query →
-- plak dit hele bestand → Run).
--
-- LET OP: dit script verwijdert eerst alle bestaande tabellen in
-- het public-schema (zowel een eerdere, andere leden/sessies-opzet
-- als niet-gerelateerde tabellen zoals marktplaats/nieuws/
-- sessie_templates/slots/inschrijvingen) en bouwt daarna alles
-- fris op. Bevestigd met de klant dat de bestaande data (1 rij in
-- 'leden') niet bewaard hoeft te blijven.
--
-- Dit schema is bouwplan.md plus een paar verbeteringen die zijn
-- overgenomen uit het eerder aangetroffen schema, zodat de app
-- ook aan een tweede klant (bijv. een sportcentrum met baanverhuur)
-- verkocht kan worden zonder dat data tussen klanten vermengt:
--   - bundels, markt_items, nieuwsberichten en wedstrijden hebben
--     nu ook organisatie_id (bouwplan.md had dit alleen op leden,
--     sessies en baanreserveringen).
--   - sessie_deelnemers heeft een 'positie'-kolom voor een
--     gegarandeerde wachtlijst-volgorde.
--   - baanreserveringen gebruikt baan_nummer + start_tijd/eind_tijd
--     in plaats van een vrije tekst-tijdslot.
--   - wedstrijden gebruikt een aparte koppeltabel
--     (wedstrijd_deelnemers) in plaats van uuid-arrays, met echte
--     foreign keys per speler; werkt zo ook voor enkelspel.
--
-- Na het draaien: alle tabellen bestaan met Row Level Security aan
-- en de organisatie + bundels als seed-data. De rest van de app
-- (leden, sessies, wedstrijden, ...) blijft in deze fase nog op
-- localStorage — dat wordt pas in Fase 2 omgezet.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Opruimen: alles wat nu in het public-schema staat weg, zodat
-- dit script herhaalbaar is en niet botst met eerdere pogingen.
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
-- Seed-data: organisatie + bundels (vast, geen per-lid data)
-- Bundel-inhoud komt overeen met de demo-data in ledenpanel.html.
-- ------------------------------------------------------------

insert into organisaties (id, naam, baanreservering_actief) values
  ('11111111-1111-1111-1111-111111111111', 'Pickleball Den Haag', false);

insert into bundels (organisatie_id, code, naam, prijs, omschrijving, speelbeurten, geldigheid) values
  ('11111111-1111-1111-1111-111111111111', 'starter', 'Starter', 15, 'Instapbundel voor nieuwe leden.', 4, '1 maand'),
  ('11111111-1111-1111-1111-111111111111', 'bundle10', '10-rittenkaart', 60, '10 speelbeurten, te gebruiken binnen 3 maanden.', 10, '3 maanden'),
  ('11111111-1111-1111-1111-111111111111', 'quarterly', 'Kwartaal onbeperkt', 90, 'Onbeperkt spelen gedurende een heel kwartaal.', 999, '3 maanden'),
  ('11111111-1111-1111-1111-111111111111', 'incidenteel', 'Losse sessie', 6, 'Eenmalig meespelen, per keer afrekenen.', 1, '1 sessie');

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

-- organisaties: alleen de eigen organisatie is zichtbaar
create policy "organisatie: alleen eigen organisatie lezen"
  on organisaties for select
  using (id = eigen_organisatie_id());

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

-- Bevestigd met de klant: bestuur/penningmeester mogen ook andere
-- leden van hun eigen organisatie bewerken (rol wijzigen,
-- actief/inactief zetten, gegevens corrigeren). De UI hiervoor
-- (Ledenbeheer-pagina) wordt pas in Fase 2 op deze tabel aangesloten.
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
-- wijzigen. Bevestigd via testen tegen de live database. Bestuur en
-- penningmeester mogen deze velden wel wijzigen (van zichzelf én van
-- andere leden), zoals afgesproken.
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

-- Wachtlijst-promotie (iemand anders van wachtlijst naar deelnemer
-- zetten wanneer je uitschrijft) raakt aan een andermans rij en
-- hoort daarom bij Fase 2 als een aparte, server-side functie —
-- nu alvast beperkt tot bestuur/penningmeester zodat een gewoon
-- lid nooit iemand anders' status/positie kan wijzigen.
create policy "sessie_deelnemers: bestuur/penningmeester werkt status/positie bij"
  on sessie_deelnemers for update
  using (
    eigen_rol() in ('bestuur','penningmeester')
    and exists (select 1 from sessies s where s.id = sessie_id and s.organisatie_id = eigen_organisatie_id())
  )
  with check (
    exists (select 1 from sessies s where s.id = sessie_id and s.organisatie_id = eigen_organisatie_id())
  );

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

-- Opzettelijk geen insert/update-policy op betalingen in Fase 1:
-- die komt in Fase 3 vast te zitten aan de Mollie-webhook
-- (server-side, met de service_role key — nooit vanuit de client).
