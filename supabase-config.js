/* ============================================================
   Supabase-configuratie — per klant/installatie in te vullen.
   De anon/public key hieronder is bedoeld om in frontend-code te
   staan (Supabase's RLS-beleid beschermt de data, niet geheimhouding
   van deze key). Zet hier NOOIT de service_role key in.

   Dit bestand is het ENIGE bestand dat per klant hoeft te wijzigen —
   de rest van de app (ledenpanel.html) leest de clubnaam/branding
   hieruit en past zich automatisch aan. Zie
   installatiehandleiding-nieuwe-klant.pdf voor de volledige opzet.
   ============================================================ */

const SUPABASE_URL = 'https://hwbugosdktnojmptdcei.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh3YnVnb3Nka3Rub2ptcHRkY2VpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNTc3MjIsImV4cCI6MjA5MTkzMzcyMn0.YQihb9ECWXy6Z6J-OEfNtFyEGb2oK7NjjZ4q5g2wj8o';

// Moet exact overeenkomen met het organisatie-id dat het installatiescript
// (installatie.sql) heeft aangemaakt voor deze klant.
const ORGANISATIE_ID = '11111111-1111-1111-1111-111111111111';

// Branding: wordt getoond vóórdat iemand is ingelogd (dan kan de app de
// databasenaam nog niet opvragen). Ná inloggen wordt de naam automatisch
// overschreven met de echte waarde uit de organisaties-tabel, dus deze
// twee waarden hoeven niet per se helemaal actueel te blijven — maar zet
// ze wel logisch voor de eerste indruk.
const ORGANISATIE_NAAM = 'Pickleball Den Haag';
const ORGANISATIE_LOGO_TEKST = 'PDH';
