# CLAUDE.md

Dit bestand wordt automatisch geladen door Claude Code bij elke sessie in dit project.
Het beschrijft wat er al bestaat, wat het doel is, en de regels waaraan je je moet houden.

## Project

Ledenpanel voor pickleballverenigingen (eerste klant: Pickleball Den Haag), met als
uiteindelijk doel: dezelfde app ook verkopen aan locaties die banen verhuren.

Huidige staat: `ledenpanel.html` is een werkend, visueel afgerond prototype
(HTML/CSS/JS in één bestand) met alle UI/UX en business-logica al aanwezig:
- Ledenbeheer, interne ELO-rating berekening
- Sessies/Open Play/Clinics/Toernooien met wachtlijst-logica
- DUPR-koppeling (CSV-export, ID-koppeling per lid)
- Marktplaats, Nieuws
- Contributie/bundels + betaalmethode-keuze (nu nog nep — toont alleen een toast)
- Financieel beheer (alleen zichtbaar voor bestuur/penningmeester)

Alle data zit nu in `localStorage` — dus alleen zichtbaar in de eigen browser, niet
gedeeld tussen leden. Dat is het kernprobleem dat opgelost moet worden.

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
