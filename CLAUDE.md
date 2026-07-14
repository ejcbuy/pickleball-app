# CLAUDE.md

Dit bestand wordt automatisch geladen door Claude Code bij elke sessie in dit project.
Het beschrijft wat er al bestaat, wat het doel is, en de regels waaraan je je moet houden.

## Project

Ledenpanel voor pickleballverenigingen (eerste klant: Pickleball Den Haag), met als
uiteindelijk doel: dezelfde app ook verkopen aan locaties die banen verhuren.

Huidige staat: `ledenpanel.html` is één HTML/CSS/JS-bestand, live op
`https://ejcbuy.github.io/pickleball-app/ledenpanel.html` (GitHub Pages, repo
`github.com/ejcbuy/pickleball-app`) en gekoppeld aan een echt Supabase-project.

**Fase 1 (Database & Authenticatie) — af.** Registreren/inloggen/wachtwoord-
vergeten werken echt (Supabase Auth). "Mijn account" leest/schrijft de eigen
`leden`-rij. RLS staat aan op alle tabellen, incl. een kolombeveiligings-trigger
die voorkomt dat een gewoon lid zijn eigen rol/rating/organisatie kan wijzigen.

**Fase 2 (Ledenbeheer, Sessies, Baanreservering, Wedstrijden) — af.** Leden,
Sessies (incl. wachtlijst), Banen en Wedstrijden praten nu echt met Supabase:
- Ledenbeheer: bestuur/penningmeester bewerken/verwijderen leden; nieuwe leden
  ontstaan alleen via registratie (Fase 1), niet meer handmatig aan te maken.
- Sessies: inschrijven/wachtlijst zoals voorheen; wachtlijst-promotie bij
  uitschrijven gebeurt nu via een database-trigger (`promoveer_wachtlijst()`,
  zie `supabase/fase2.sql`), niet meer client-side.
- Banen: gebruikt nu `baan_nummer` + `start_tijd`/`eind_tijd` i.p.v. een vrije
  tekst-tijdslot; dubbele boekingen worden op databaseniveau geweigerd.
- Wedstrijden: ELO-berekening staat nu in de database-functie
  `registreer_wedstrijd()` (security definer) omdat een gewoon lid anders door
  de kolombeveiliging geblokkeerd zou worden bij het bijwerken van andermans
  rating/wins/matches.

**Nog op de demo-databron (localStorage), ongewijzigd:** Marktplaats, Nieuws,
Contributie/bundels + betaalmethode-keuze (nu nog nep — toont alleen een toast),
Financieel beheer. Deze volgen in latere fases. De demo-gebruikerswisselaar in de
zijbalk stuurt alleen deze onderdelen aan, niet meer Leden/Sessies/Banen/Wedstrijden
(die volgen de echte ingelogde Supabase-gebruiker).

## Doel van dit traject

De bestaande UI/logica **hergebruiken**, alleen de dataopslag vervangen door een
echte database + auth + betalingen, in vier losstaand te testen fases. Zie
`bouwplan.md` in deze map voor het volledige databaseschema, de RLS-regels, de
Mollie-betaalflow en de per-fase testchecklist.

## Kernregels — houd je hier altijd aan

1. **Bouw en test alleen de fase die expliciet gevraagd wordt.** Loop niet vooruit
   op een volgende fase, ook niet "om tijd te besparen". Elke fase moet apart
   werkend en getest zijn voordat de volgende begint.
2. **Hergebruik bestaande logica** (ELO-berekening, wachtlijst-regels, bundel-
   prijzen) — herschrijf deze niet zonder reden, verplaats alleen de dataopslag.
3. **Baanreservering is een optionele module**, geen kernfunctie. Pickleball Den
   Haag gebruikt alleen het vaste rooster per DUPR/niveau-klasse (geen boeking
   nodig). Klanten met baanverhuur zetten `organisaties.baanreservering_actief`
   aan. Bouw dit als één codebase met een aan/uit-schakelaar, nooit als aparte
   versie van de app.
4. **Betalingen via Mollie**, nooit een API-key in frontend-code. Betaalstatus
   wordt alleen server-side (Edge Function/webhook) bijgewerkt, nooit vanuit de
   client.
5. **Row Level Security is verplicht, niet optioneel**: leden zien alleen data
   van hun eigen `organisatie_id`, en alleen bestuur/penningmeester zien
   financiële data van andere leden.
6. **Bij twijfel over rolrechten of kortingslogica (bijv. Ooievaarspas): vraag
   het na** in plaats van een aanname te doen.
7. **Lever geen "klaar" op zonder de testchecklist van die fase te hebben
   doorlopen** (zie `bouwplan.md`).

## Stack

- **Backend/database**: Supabase (Postgres + Auth + Row Level Security)
- **Betalingen**: Mollie (iDEAL/Tikkie-achtige flows)
- **Frontend**: bestaande HTML/CSS/JS, later evolueren naar een installeerbare
  PWA (geen native app-store-traject voor v1)

## Volgorde van fases (kort overzicht, details in bouwplan.md)

1. Database + Authenticatie
2. Ledenbeheer + Sessies/Speelschema + Baanreservering (module)
3. Echte Mollie-betalingen
4. Marktplaats/Nieuws/DUPR-koppeling (laagste prioriteit)

## Hoe te starten

Zeg tegen Claude Code bijvoorbeeld: *"Bouw fase 1 uit bouwplan.md"* — niet meer
dan dat in één keer. Wacht op een werkende, geteste oplevering voordat je naar de
volgende fase vraagt.
