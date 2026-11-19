# Backend PADEE: návod krok za krokem (T3)

Tohle musíš udělat ty, protože kroky potřebují tvoje účty (Supabase, Apple Developer). Kód a SQL jsou už v repozitáři. Celé to zabere asi 30–45 minut.

Pořadí: **1** Supabase projekt → **2** tabulky → **3** Apple v Supabase → **4** Xcode (balíček, capability, klíče) → **5** vyzkoušet.

---

## 1. Založ projekt v Supabase (Free)

1. Otevři [supabase.com/dashboard](https://supabase.com/dashboard) a přihlas se (nejjednodušší je **Continue with GitHub**).
2. Pokud se ptá na organizaci, vytvoř ji: název např. `Zdenek`, plán **Free**.
3. **New project**:
   - **Name:** `PADEE`
   - **Database Password:** klikni na **Generate a password** a heslo si **ulož do Hesel (Klíčenky)**. Budeš ho potřebovat v kroku 2, v gitu ani v chatu být nesmí.
   - **Region:** `Central EU (Frankfurt)` (nejblíž Česku = nejrychlejší)
   - **Create new project** a počkej 1–2 minuty.
4. Poznamenej si **Project ref**: je to kód v adrese projektu, `supabase.com/dashboard/project/`**`abcdefghijklmnop`**.

> Free projekt se po 7 dnech bez jakékoli aktivity uspí. Probudíš ho v dashboardu tlačítkem **Restore**, data zůstanou.

## 2. Vytvoř tabulky (spusť migrace)

Doporučený způsob je přes **Supabase CLI**, protože si pamatuje, které migrace už v databázi jsou. V Terminálu ve složce `~/Documents/PADEE`:

```bash
brew install supabase/tap/supabase   # jednou: instalace CLI
supabase login                       # otevře prohlížeč, potvrď přístup
supabase init                        # jednou: vytvoří supabase/config.toml (na dotazy odpověz N)
supabase link --project-ref TVUJ_PROJECT_REF   # zeptá se na heslo databáze z kroku 1
supabase db push                     # nahraje obě migrace do databáze
```

`supabase db push` vypíše obě migrace a zeptá se `Do you want to push these migrations?`, odpověz `Y`.

Kontrola v dashboardu: **Table Editor** ukazuje tabulky `clubs`, `matches`, `match_players`, `points`, `profiles`, `sets` a u každé je zelený štítek RLS (ne červené „RLS disabled“).

<details>
<summary>Náhradní způsob bez CLI (SQL Editor)</summary>

V dashboardu **SQL Editor → New query**, vlož celý obsah `supabase/migrations/20261119120000_zakladni_schema.sql`, **Run**. Pak totéž s `20261119120100_rls_politiky.sql`. Nevýhoda: CLI pak o migracích neví a `supabase db push` by je zkoušel spustit znovu.
</details>

## 3. Zapni přihlášení přes Apple v Supabase

1. Dashboard → **Authentication → Sign In / Providers → Apple**.
2. Zapni **Enable Sign in with Apple**.
3. Do **Client IDs** napiš bundle ID iOS aplikace: `cz.vacek.PADEE`
4. **Secret Key** nech prázdný. Je potřeba jen pro přihlášení na webu; aplikace na iPhonu přihlašuje nativně.
5. **Save**.

## 4. Xcode

Otevři `App/PADEE/PADEE.xcodeproj`.

### 4a. Přidej balíček supabase-swift

1. **File → Add Package Dependencies…**
2. Vpravo nahoře do vyhledávání vlož `https://github.com/supabase/supabase-swift`
3. **Dependency Rule:** Up to Next Major Version (od 2.0.0) → **Add Package**.
4. V dalším okně vyber jen produkt **Supabase** a v **Add to Target** zvol **PADEE** (iOS aplikaci, ne Watch App) → **Add Package**.

### 4b. Přidej capability Sign in with Apple

1. V levém panelu klikni na modrou ikonu projektu **PADEE** → target **PADEE** → záložka **Signing & Capabilities**.
2. Zkontroluj, že **Team** je tvůj tým a **Automatically manage signing** je zaškrtnuté.
3. Klikni **+ Capability** a vyber **Sign in with Apple**.

Xcode tím sám vytvoří soubor `PADEE.entitlements` a zapne Sign in with Apple pro `cz.vacek.PADEE` i ve tvém Apple Developer účtu. Do portálu developer.apple.com nemusíš.

### 4c. Vlož klíče do Secrets.plist

1. Ve Finderu zkopíruj `App/PADEE/Secrets.example.plist` do složky `App/PADEE/PADEE/` a přejmenuj kopii na **`Secrets.plist`**.
2. V Supabase dashboardu otevři **Project Settings → API Keys** (URL projektu najdeš v **Project Settings → Data API**, případně tlačítkem **Connect** nahoře).
3. Do `Secrets.plist` doplň:
   - `SupabaseURL`: `https://TVUJ_PROJECT_REF.supabase.co`
   - `SupabasePublishableKey`: klíč **Publishable key** (`sb_publishable_…`). Pokud ho tam nemáš, funguje i starší **anon public** klíč.

> **Nikdy** do aplikace nedávej **Secret key** ani **service_role** klíč. Ty obcházejí RLS a patří jen na server. Publishable klíč do aplikace patří; data chrání RLS. `Secrets.plist` je v `.gitignore`, takže `git status` ho neukáže. Pokud ho ukáže, napiš mi.

## 5. Vyzkoušej

1. Nahoře vyber schéma **PADEE** a svůj **iPhone** (Sign in with Apple spolehlivě funguje na skutečném zařízení; v simulátoru musíš být přihlášený k Apple ID v Nastavení).
2. **⌘R**. Objeví se obrazovka s tlačítkem **Přihlásit se přes Apple**.
3. Po přihlášení uvidíš „Ahoj, …“ a své **PADEE ID**.
4. V dashboardu **Authentication → Users** je tvůj účet a v **Table Editor → profiles** řádek se stejným PADEE ID.

## Test RLS (cizí zápasy nejdou přečíst)

Test je v [`supabase/tests/rls_zapasy_test.sql`](../supabase/tests/rls_zapasy_test.sql). Simuluje tři hráče: Alice nahraje soukromý zápas, Cyril v něm hrál, Bob ne. Ověřuje 20 věcí, hlavně že Bob soukromý zápas, jeho sety, body ani hráče **nevidí** a nemůže je změnit, zatímco Cyril je vidí.

Spuštění lokálně (potřebuje nainstalovaný a spuštěný **Docker Desktop**):

```bash
supabase start      # první spuštění stahuje obrazy, trvá pár minut
supabase test db
```

Výsledek má končit `All tests successful.` Na konci `supabase stop`.

## Když něco nejde

| Chyba | Co s tím |
| --- | --- |
| Aplikace spadne hned po spuštění s hláškou o `Secrets.plist` | Soubor chybí nebo je ve špatné složce, viz 4c. Musí ležet vedle `PADEEApp.swift`. |
| `No such module 'Supabase'` | Balíček není přidaný k targetu PADEE, viz 4a. |
| Po klepnutí na Apple tlačítko chyba 1000 | Chybí capability Sign in with Apple (4b), nebo na zařízení/simulátoru nejsi přihlášený k Apple ID. |
| `Unacceptable audience in id_token` | V Supabase v Apple provideru chybí v Client IDs `cz.vacek.PADEE` (krok 3). |
| `Nepodařilo se načíst profil` | Neproběhly migrace (krok 2), takže chybí tabulka `profiles` nebo trigger. |
