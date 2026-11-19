-- =============================================================================
-- Test RLS: cizí soukromé zápasy nejdou přečíst ani změnit
-- =============================================================================
-- Spuštění (potřebuje Docker a Supabase CLI):
--   supabase start        # nebo jen: supabase db start
--   supabase test db
--
-- Test používá pgTAP (testovací knihovna pro PostgreSQL, v Supabase je
-- předinstalovaná). Celý běží v transakci a na konci se vrátí (rollback),
-- takže v databázi nezůstanou žádná testovací data.
--
-- Postavy:
--   Alice  zapisovatelka; nahraje soukromý a veřejný zápas
--   Cyril  hraje s Alicí, Alice ho přidá do soukromého zápasu
--   Bob    s nimi nehrál; soukromý zápas nesmí vidět ani změnit
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);


-- -----------------------------------------------------------------------------
-- Příprava: tři uživatelé (jako by se přihlásili přes Apple)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'alice@example.com', '{"full_name": "Alice"}'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'bob@example.com',   '{"full_name": "Bob"}'),
  ('cccccccc-0000-0000-0000-000000000003', 'cyril@example.com', '{"full_name": "Cyril"}');

select is(
  (select count(*)::int from public.profiles),
  3,
  'Po registraci se každému uživateli automaticky založí profil'
);

select ok(
  (select bool_and(padee_id ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{5}$') from public.profiles),
  'Každý profil dostal platné 5znakové PADEE ID'
);

select is(
  (select display_name from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Alice',
  'Jméno z Apple ID se přeneslo do profilu'
);


-- -----------------------------------------------------------------------------
-- Alice nahraje zápasy
-- -----------------------------------------------------------------------------
-- Přepnutí na přihlášeného uživatele: role "authenticated" a v JWT tokenu
-- (request.jwt.claims) jeho id. Přesně takhle to dělá Supabase při dotazu z aplikace.
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$ insert into public.matches (id, visibility, status, winner_team)
     values ('11111111-0000-0000-0000-000000000001', 'private', 'finished', 1) $$,
  'Alice založí soukromý zápas'
);

select lives_ok(
  $$ insert into public.matches (id, visibility) values ('22222222-0000-0000-0000-000000000002', 'public') $$,
  'Alice založí veřejný zápas'
);

select lives_ok(
  $$ insert into public.sets (match_id, set_number, team1_games, team2_games)
       values ('11111111-0000-0000-0000-000000000001', 1, 6, 4);
     insert into public.points (match_id, seq, set_number, game_number, winner_team)
       values ('11111111-0000-0000-0000-000000000001', 1, 1, 1, 1);
     insert into public.match_players (match_id, team, profile_id)
       values ('11111111-0000-0000-0000-000000000001', 1, 'aaaaaaaa-0000-0000-0000-000000000001'),
              ('11111111-0000-0000-0000-000000000001', 1, 'cccccccc-0000-0000-0000-000000000003');
     insert into public.match_players (match_id, team, guest_name)
       values ('11111111-0000-0000-0000-000000000001', 2, 'Jana') $$,
  'Alice zapíše do svého zápasu set, bod a hráče (Cyrila a hosta Janu)'
);

select is(
  (select count(*)::int from public.matches),
  2,
  'Alice vidí oba své zápasy'
);


-- -----------------------------------------------------------------------------
-- Bob: cizí soukromý zápas nesmí vidět
-- -----------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "bbbbbbbb-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.matches where id = '11111111-0000-0000-0000-000000000001'),
  0,
  'Bob NEVIDÍ Alicin soukromý zápas'
);

select is(
  (select count(*)::int from public.sets where match_id = '11111111-0000-0000-0000-000000000001'),
  0,
  'Bob NEVIDÍ sety Alicina soukromého zápasu'
);

select is(
  (select count(*)::int from public.points where match_id = '11111111-0000-0000-0000-000000000001'),
  0,
  'Bob NEVIDÍ body Alicina soukromého zápasu'
);

select is(
  (select count(*)::int from public.match_players where match_id = '11111111-0000-0000-0000-000000000001'),
  0,
  'Bob NEVIDÍ hráče Alicina soukromého zápasu'
);

select is(
  (select count(*)::int from public.matches where id = '22222222-0000-0000-0000-000000000002'),
  1,
  'Bob vidí Alicin veřejný zápas'
);

-- Bob zkusí změnit výsledek. RLS řádek „neuvidí“, takže se nezmění nic (0 řádků).
update public.matches set winner_team = 2 where id = '11111111-0000-0000-0000-000000000001';
delete from public.matches where id = '22222222-0000-0000-0000-000000000002';

select throws_ok(
  $$ insert into public.points (match_id, seq, set_number, game_number, winner_team)
     values ('11111111-0000-0000-0000-000000000001', 2, 1, 1, 2) $$,
  '42501',
  null,
  'Bob NEMŮŽE přidat bod do cizího zápasu'
);

select throws_ok(
  $$ insert into public.matches (recorded_by) values ('aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'Bob NEMŮŽE založit zápas za Alici'
);

select throws_ok(
  $$ insert into public.match_players (match_id, team, profile_id)
     values ('11111111-0000-0000-0000-000000000001', 2, 'bbbbbbbb-0000-0000-0000-000000000002') $$,
  '42501',
  null,
  'Bob se NEMŮŽE sám přidat do cizího zápasu, aby ho uviděl'
);

-- Bob zkusí přepsat cizí profil (0 řádků) a upravit svůj (projde).
update public.profiles set display_name = 'Hacker' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
update public.profiles set display_name = 'Bob B.' where id = 'bbbbbbbb-0000-0000-0000-000000000002';


-- -----------------------------------------------------------------------------
-- Cyril: hrál s Alicí, takže soukromý zápas vidí
-- -----------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "cccccccc-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.matches where id = '11111111-0000-0000-0000-000000000001'),
  1,
  'Cyril (hráč zápasu) vidí soukromý zápas, do kterého ho Alice přidala'
);

select is(
  (select count(*)::int from public.points where match_id = '11111111-0000-0000-0000-000000000001'),
  1,
  'Cyril vidí i body toho zápasu'
);


-- -----------------------------------------------------------------------------
-- Nepřihlášený klient (anon) nevidí nic
-- -----------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select count(*)::int from public.matches),
  0,
  'Nepřihlášený klient nevidí žádný zápas, ani veřejný'
);


-- -----------------------------------------------------------------------------
-- Kontrola jako správce (bez RLS): Bobovy pokusy nic nezměnily
-- -----------------------------------------------------------------------------
reset role;

select is(
  (select winner_team::int from public.matches where id = '11111111-0000-0000-0000-000000000001')
    || ' / ' ||
  (select count(*)::int from public.matches where id = '22222222-0000-0000-0000-000000000002'),
  '1 / 1',
  'Bob nezměnil výsledek soukromého zápasu ani nesmazal veřejný'
);

select is(
  (select string_agg(display_name, ', ' order by display_name) from public.profiles),
  'Alice, Bob B., Cyril',
  'Bob změnil jen svůj profil, cizí ne'
);

select * from finish();
rollback;
