# Pickleball Den Haag — Bouwplan (van prototype naar productie)

Dit document is het bouwplan voor Claude Code. Doel: de bestaande HTML/JS-prototype
(`ledenpanel.html`) omzetten naar een werkende multi-user app met echte database,
authenticatie en betalingen — gefaseerd, zodat elke fase apart getest kan worden
voordat de volgende begint.

**Belangrijk voor Claude Code: bouw en test alleen de fase die actief wordt gevraagd.
Ga niet vooruitlopen op latere fases, ook niet "om tijd te besparen".**

---

## Fase 0 — Uitgangspunten

- **Bestaande code**: `ledenpanel.html` bevat alle UI/UX en business-logica (ELO-rating
  berekening, sessie/wachtlijst-logica, bundel-prijzen). Deze logica is al goed doordacht
  en moet zoveel mogelijk **hergebruikt** worden, alleen de dataopslag verandert
  (van `localStorage` naar een echte database).
- **Stack-keuze**: Supabase (Postgres + Auth + Row Level Security + realtime).
  Reden: gratis tier ruim voldoende voor een club van ~150 leden, ingebouwde auth,
  en direct bruikbaar vanuit de bestaande JS zonder een aparte backend-server te bouwen.
- **Betalingen**: Mollie (ondersteunt iDEAL, en is de standaardkeuze voor Nederlandse
  verenigingen/kleine organisaties — makkelijker te integreren dan iDEAL direct).
- **Rollen**: `lid`, `bestuur`, `penningmeester` (staat al in de demo-data als `rol`-veld).
  Penningmeester + bestuur krijgen toegang tot Financieel Beheer, overige leden niet.
- **Baanreservering is een optionele module**: Pickleball Den Haag zelf heeft dit niet
  nodig (vast rooster per DUPR/niveau-klasse op 3 locaties), maar andere klanten die je
  wilt benaderen (sportcentra die banen verhuren) hebben dit wél nodig. Bouw dit dus
  als los, aan/uit-schakelbaar onderdeel per organisatie (bijv. `organisaties.baanreservering_actief`
  boolean), niet als vaste kernfunctie. Zo verkoop je dezelfde app aan twee type klanten
  zonder twee losse codebases.

---

## Fase 1 — Database & Authenticatie (bouw dit eerst, en NIET verder)

### Doel
Een werkende Supabase-database met tabellen, en login/registratie die echt werkt.
Na deze fase: iedereen kan inloggen, maar de rest van de app werkt nog met de oude
localStorage-data. Dat is prima — dit is een losstaand te testen stap.

### Database-tabellen

> **Bijgewerkt tijdens de bouw van Fase 1** (zie `supabase/schema.sql` voor de
> uitvoerbare, actuele versie — dit blok hieronder is daarmee gesynchroniseerd).
> Bij het opzetten bleek het Supabase-project al een ander, ongerelateerd schema
> te bevatten; in overleg met de klant is gekozen om niet zomaar het simpelste
> pad (bouwplan.md letterlijk) te volgen, maar de beste elementen te combineren
> zodat de app ook aan een tweede klant verkocht kan worden zonder dataverlies
> tussen klanten. Wijzigingen t.o.v. de oorspronkelijke opzet:
> - `bundels`, `markt_items`, `nieuwsberichten` en `wedstrijden` hebben nu ook
>   een `organisatie_id` (voorheen niet overal aanwezig — zonder deze kolom
>   zouden alle klanten dezelfde bundels/nieuws/marktplaats delen).
> - `bundels.id` is nu een `uuid` (was `text`), met een `code`-kolom
>   ('starter'/'bundle10'/...) die uniek is per organisatie, zodat elke klant
>   zijn eigen prijzen/bundels kan voeren.
> - `sessie_deelnemers` heeft een `positie`-kolom voor een gegarandeerde
>   wachtlijst-volgorde.
> - `baanreserveringen` gebruikt `baan_nummer` (int) + `start_tijd`/`eind_tijd`
>   (time) in plaats van een vrije tekst-`tijdslot`, en de unique constraint is
>   nu `(organisatie_id, locatie, baan_nummer, datum, start_tijd)`.
> - `wedstrijden` gebruikt een aparte koppeltabel `wedstrijd_deelnemers`
>   (`wedstrijd_id`, `lid_id`, `team` 'a'/'b') in plaats van `team_a`/`team_b`
>   uuid-arrays — geeft echte foreign keys per speler en werkt zo ook voor
>   enkelspel, niet alleen dubbel.
> - `markt_items` heeft een `status`-kolom (`te_koop` / `verkocht`).

```sql
-- organisaties (maakt de app bruikbaar voor meerdere klanten/clubs)
create table organisaties (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  baanreservering_actief boolean not null default false,  -- true voor klanten met baanverhuur
  created_at timestamptz not null default now()
);

-- bundels (contributie-opties, per organisatie eigen prijzen/inhoud)
create table bundels (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  code text not null,             -- 'starter' | 'bundle10' | 'quarterly' | 'incidenteel'
  naam text not null,
  prijs numeric not null,
  omschrijving text,
  speelbeurten int,               -- 999 = onbeperkt
  geldigheid text,
  actief boolean not null default true,
  unique (organisatie_id, code)
);

-- leden (koppelt aan Supabase auth.users via id)
create table leden (
  id uuid primary key references auth.users(id) on delete cascade,
  organisatie_id uuid not null references organisaties(id),
  naam text not null,
  email text not null,
  niveau text,                    -- bijv. "3.5"
  rating int not null default 1000,  -- interne ELO
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

-- sessies (Open Play / Clinics / Toernooien)
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
  positie int,                    -- volgorde binnen de wachtlijst; null als status = 'deelnemer'
  created_at timestamptz not null default now(),
  primary key (sessie_id, lid_id)
);

-- baanreserveringen (optionele module — alleen relevant als organisatie.baanreservering_actief = true)
create table baanreserveringen (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  locatie text not null,          -- sportcomplex/vestiging
  baan_nummer int not null,       -- specifieke baan binnen die locatie
  datum date not null,
  start_tijd time not null,
  eind_tijd time not null,
  lid_id uuid references leden(id),
  created_at timestamptz not null default now(),
  unique (organisatie_id, locatie, baan_nummer, datum, start_tijd)  -- voorkomt dubbele boekingen
);

-- wedstrijden (+ koppeltabel voor spelers, werkt voor dubbel én enkelspel)
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

-- marktplaats
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

-- nieuws
create table nieuwsberichten (
  id uuid primary key default gen_random_uuid(),
  organisatie_id uuid not null references organisaties(id),
  titel text not null,
  body text not null,
  categorie text,
  created_at timestamptz not null default now()
);

-- betalingen
create table betalingen (
  id uuid primary key default gen_random_uuid(),
  lid_id uuid references leden(id),
  bundel_id uuid references bundels(id),
  bedrag numeric not null,
  methode text,                    -- 'ideal' | 'tikkie' | 'card'
  mollie_payment_id text,          -- echte Mollie-referentie
  status text not null default 'open' check (status in ('open','betaald','mislukt')),
  aangemaakt_op timestamptz not null default now()
);
```

### Row Level Security (belangrijk, niet overslaan)
- Elk lid mag alleen zijn eigen rij in `leden` bewerken; bestuur/penningmeester
  mogen daarnaast ook andere leden van hun eigen organisatie bewerken/verwijderen
  (rol wijzigen, actief/inactief zetten) — bevestigd met de klant tijdens Fase 1.
- Alleen `bestuur`/`penningmeester` mogen `betalingen` van andere leden lezen.
- Alle leden van dezelfde organisatie mogen `sessies`, `markt_items`,
  `nieuwsberichten`, `bundels` en `wedstrijden` van die organisatie lezen; alleen
  ingelogde leden mogen toevoegen. (Niet publiek/anoniem leesbaar — dat zou
  clubdata tussen klanten laten lekken, wat ingaat tegen het multi-tenant doel.)
- Leden zien alleen data van hun eigen `organisatie_id` — dit is de scheiding tussen
  klanten (Pickleball Den Haag ziet nooit data van een andere club/sportcentrum).
  Dit geldt nu voor alle tabellen, ook `bundels`/`markt_items`/`nieuwsberichten`/
  `wedstrijden` (in de eerste opzet ontbrak `organisatie_id` daar nog).

### Auth-flow
- Supabase Auth met e-mail + wachtwoord (geen magic link nodig voor v1 — simpeler
  om te ondersteunen bij minder technische leden).
- Bij eerste registratie: rij in `leden` aanmaken gekoppeld aan de auth user.
- Wachtwoord-reset via Supabase's ingebouwde flow (geen zelfbouw nodig).

### Op te leveren / te testen na Fase 1
- [ ] Een nieuw lid kan zich registreren en inloggen
- [ ] Een lid kan zijn eigen profiel bewerken, niet dat van een ander
- [ ] Bestuur/penningmeester-rol geeft toegang tot extra secties, `lid`-rol niet
- [ ] Data staat aantoonbaar in Supabase, niet meer in localStorage

---

## Fase 2 — Ledenbeheer, Sessies/Speelschema & Baanreservering op de database

### Doel
De bestaande UI-functies (`renderLeden`, `renderSessies`, `renderBanen`, `addSessie`,
etc.) omzetten van localStorage-arrays naar Supabase-queries. Dit is grotendeels
1-op-1 werk: dezelfde render-functies, maar `players.find(...)` wordt een Supabase
`select`, en `save()` wordt een `insert`/`update`.

**Twee aparte gebruiksscenario's, in dezelfde codebase:**
- **Pickleball Den Haag**: vast rooster per DUPR/niveau-klasse op de 3 locaties.
  Dit gebruikt alleen de `sessies`-tabel (locatie + niveau + dag/tijd) — geen
  boeking nodig, iedereen in die klasse speelt op dat tijdstip.
- **Klanten met baanverhuur** (bijv. sportcentra): gebruiken daarnaast de
  `baanreserveringen`-tabel, waar een lid een specifiek tijdslot op een specifieke
  baan claimt. Dit is een module die je per organisatie aan/uit zet.

### Let op
- Baanreservering moet de `unique (organisatie_id, locatie, baan_nummer, datum, start_tijd)`
  constraint gebruiken om dubbele boekingen op databaseniveau te voorkomen — niet
  alleen in de UI checken. Let op: het huidige prototype gebruikt een vrije
  tekst-`tijdslot` (bijv. "08:00 - 09:00") in de Banen-dialoog; die UI moet in
  deze fase aangepast worden naar een baan-nummer + start/eind-tijd, aansluitend
  op het echte schema.
- Wedstrijden worden opgeslagen via de koppeltabel `wedstrijd_deelnemers`
  (per speler een rij met `team` 'a'/'b'), niet als `team_a`/`team_b`-arrays.
  De ELO-berekening zelf (client-side) blijft ongewijzigd; alleen hoe de
  deelnemers worden weggeschreven/uitgelezen verandert.
- Sessie-wachtlijst-logica (als `max_spelers` bereikt is) blijft hetzelfde, alleen
  de opslag verandert.
- Bouw de "Banen"-pagina zo dat hij simpelweg niet getoond wordt als
  `baanreservering_actief = false` voor die organisatie — geen losse versie van de app.

### Op te leveren / te testen na Fase 2
- [ ] Twee browsers/gebruikers zien dezelfde ledenlijst en hetzelfde sessie-rooster
      (bewijst dat het niet meer per-browser is)
- [ ] Dubbele baanboeking op hetzelfde tijdslot wordt geweigerd (bij een organisatie
      met de module aan)
- [ ] Bij een organisatie met de module uit, is de Banen-pagina niet zichtbaar/niet
      nodig
- [ ] Wedstrijduitslag invoeren werkt en ELO-rating wordt bijgewerkt voor alle
      gebruikers zichtbaar

---

## Fase 3 — Echte betalingen (Mollie)

### Doel
`doPayment()` vervangen door een echte Mollie-betaling in plaats van alleen een toast.

### Flow
1. Lid kiest bundel + betaalmethode → app maakt een Mollie-payment aan via de
   Mollie API (dit moet server-side, bijvoorbeeld via een Supabase Edge Function —
   nooit de Mollie API-key in de frontend-code).
2. Lid wordt doorgestuurd naar Mollie's betaalpagina (iDEAL-keuze zit daar al in).
3. Mollie stuurt een webhook naar een Edge Function zodra de betaling slaagt/mislukt.
4. Edge Function zet de rij in `betalingen` op `status = 'betaald'` en werkt
   `leden.bundel_id` bij.

### Op te leveren / te testen na Fase 3
- [ ] Een testbetaling (Mollie test-mode) doorloopt de hele flow en de status
      in de database klopt
- [ ] Mislukte/geannuleerde betaling wordt correct afgehandeld (geen bundel
      toegekend)
- [ ] Betaalgeschiedenis toont echte Mollie-transacties, geen demo-data meer

---

## Fase 4 — Marktplaats, Nieuws, DUPR-koppeling (laagste prioriteit)

Deze features zijn functioneel al compleet in de UI en hebben geen kritieke
data-integriteit-eisen (geen dubbele boekingen, geen geld). Gewoon dezelfde
localStorage → Supabase omzetting als Fase 2.

DUPR-koppeling: voor v1 volstaat het bewaren van `dupr_id`/`dupr_rating` en de
CSV-export (staat al in de code). Een live DUPR API-koppeling is een fase 5-
uitbreiding, pas de moeite waard zodra een club er expliciet om vraagt.

---

## Volgorde-samenvatting

| Fase | Wat | Waarom deze volgorde |
|---|---|---|
| 1 | Database + Auth | Fundament — alles hierna bouwt hierop |
| 2 | Leden + Sessies/Speelschema + Baanreservering (module) | Kernfunctionaliteit; module aan/uit per klanttype |
| 3 | Mollie-betalingen | Bevat echt geld — apart en grondig testen |
| 4 | Marktplaats/Nieuws/DUPR | Nice-to-have, laagste risico bij fouten |

**Instructie voor Claude Code bij elke fase**: lever werkende, geteste code op
voordat je verder gaat naar de volgende fase. Vraag bij twijfel over rolrechten
(bestuur vs. lid) of Ooievaarspas-kortingslogica om verduidelijking in plaats van
aannames te doen.
