/* ============================================================
   Supabase-configuratie — Pickleball Den Haag
   De anon/public key hieronder is bedoeld om in frontend-code te
   staan (Supabase's RLS-beleid beschermt de data, niet geheimhouding
   van deze key). Zet hier NOOIT de service_role key in.
   ============================================================ */

const SUPABASE_URL = 'https://hwbugosdktnojmptdcei.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh3YnVnb3Nka3Rub2ptcHRkY2VpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNTc3MjIsImV4cCI6MjA5MTkzMzcyMn0.YQihb9ECWXy6Z6J-OEfNtFyEGb2oK7NjjZ4q5g2wj8o';

// Vast voor v1 — Pickleball Den Haag is de enige organisatie.
// Moet exact overeenkomen met het id uit supabase/schema.sql.
const ORGANISATIE_ID = '11111111-1111-1111-1111-111111111111';
