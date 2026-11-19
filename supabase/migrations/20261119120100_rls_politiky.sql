-- =============================================================================
-- PADEE · migrace 2/2 · RLS politiky (Row Level Security)
-- =============================================================================
-- Jak RLS funguje:
--   Aplikace se k databázi připojuje přímo (přes supabase-swift). Bez RLS by
--   každý přihlášený mohl číst i měnit cokoli. S RLS databáze ke každému dotazu
--   sama přidá podmínku z politiky, takže uživatel uvidí jen řádky, na které má
--   právo. auth.uid() vrací id přihlášeného uživatele (z jeho JWT tokenu).
--
-- Role:
--   anon           nepřihlášený klient; v PADEE nesmí nic (žádná politika pro něj)
--   authenticated  přihlášený uživatel; pravidla níže
--
-- Pravidla v kostce:
--   profiles       číst smí každý přihlášený (hledání kamaráda podle PADEE ID),
--                  měnit jen svůj profil
--   clubs          číst smí každý přihlášený, měnit jen ten, kdo klub přidal
--   matches        číst: zapisovatel, hráči přidaní do zápasu, nebo když je zápas veřejný
--                  měnit/mazat: jen zapisovatel
--   match_players,
--   sets, points   číst: kdo smí číst zápas; měnit: jen zapisovatel zápasu
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Pomocné funkce ve schématu "private"
-- -----------------------------------------------------------------------------
-- Schéma private není vystavené přes API, takže funkce nejde volat z aplikace.
-- Jsou "security definer", aby mohly nahlédnout do matches a match_players bez
-- RLS. Jinak by se politiky matches a match_players volaly navzájem dokola
-- (nekonečná rekurze).
create schema if not exists private;
grant usage on schema private to authenticated;

-- Je přihlášený uživatel zapisovatelem (vlastníkem) zápasu?
create function private.is_match_owner(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and m.recorded_by = (select auth.uid())
  );
$$;

-- Smí přihlášený uživatel zápas vidět?
create function private.can_read_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and (
        m.recorded_by = (select auth.uid())
        or m.visibility = 'public'
        or exists (
          select 1 from public.match_players mp
          where mp.match_id = m.id
            and mp.profile_id = (select auth.uid())
        )
      )
  );
$$;

revoke all on function private.is_match_owner(uuid) from public;
revoke all on function private.can_read_match(uuid) from public;
grant execute on function private.is_match_owner(uuid) to authenticated;
grant execute on function private.can_read_match(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
create policy "Přihlášení vidí profily"
  on public.profiles for select
  to authenticated
  using (true);

-- Profil vzniká triggerem po registraci; ruční insert jen pro sebe sama.
create policy "Uživatel založí jen svůj profil"
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy "Uživatel upravuje jen svůj profil"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
-- Mazání profilu: žádná politika = nejde. Profil zmizí se smazáním účtu.


-- -----------------------------------------------------------------------------
-- clubs
-- -----------------------------------------------------------------------------
create policy "Přihlášení vidí kluby"
  on public.clubs for select
  to authenticated
  using (true);

create policy "Přihlášený může přidat klub"
  on public.clubs for insert
  to authenticated
  with check (created_by = (select auth.uid()));

create policy "Klub upravuje jen ten, kdo ho přidal"
  on public.clubs for update
  to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

create policy "Klub maže jen ten, kdo ho přidal"
  on public.clubs for delete
  to authenticated
  using (created_by = (select auth.uid()));


-- -----------------------------------------------------------------------------
-- matches
-- -----------------------------------------------------------------------------
create policy "Zápas vidí zapisovatel a hráči, veřejný všichni"
  on public.matches for select
  to authenticated
  using (
    recorded_by = (select auth.uid())
    or visibility = 'public'
    or exists (
      select 1 from public.match_players mp
      where mp.match_id = matches.id
        and mp.profile_id = (select auth.uid())
    )
  );

create policy "Zápas zakládá přihlášený jen sám za sebe"
  on public.matches for insert
  to authenticated
  with check (recorded_by = (select auth.uid()));

create policy "Zápas upravuje jen zapisovatel"
  on public.matches for update
  to authenticated
  using (recorded_by = (select auth.uid()))
  with check (recorded_by = (select auth.uid()));

create policy "Zápas maže jen zapisovatel"
  on public.matches for delete
  to authenticated
  using (recorded_by = (select auth.uid()));


-- -----------------------------------------------------------------------------
-- match_players
-- -----------------------------------------------------------------------------
-- Pozn.: match_players se v politice matches čte přímo; obráceně tady voláme
-- private.can_read_match (security definer), takže k rekurzi nedojde.
create policy "Hráče zápasu vidí ten, kdo vidí zápas"
  on public.match_players for select
  to authenticated
  using (private.can_read_match(match_id));

create policy "Hráče do zápasu přidává zapisovatel"
  on public.match_players for insert
  to authenticated
  with check (private.is_match_owner(match_id));

create policy "Hráče zápasu upravuje zapisovatel"
  on public.match_players for update
  to authenticated
  using (private.is_match_owner(match_id))
  with check (private.is_match_owner(match_id));

create policy "Hráče ze zápasu odebírá zapisovatel"
  on public.match_players for delete
  to authenticated
  using (private.is_match_owner(match_id));
-- Potvrzení výsledku ostatními hráči (confirmed_at) doplníme v T13 jako
-- samostatnou funkci, aby hráč nemohl měnit nic jiného než své potvrzení.


-- -----------------------------------------------------------------------------
-- sets
-- -----------------------------------------------------------------------------
create policy "Sety vidí ten, kdo vidí zápas"
  on public.sets for select
  to authenticated
  using (private.can_read_match(match_id));

create policy "Sety zapisuje zapisovatel zápasu"
  on public.sets for insert
  to authenticated
  with check (private.is_match_owner(match_id));

create policy "Sety upravuje zapisovatel zápasu"
  on public.sets for update
  to authenticated
  using (private.is_match_owner(match_id))
  with check (private.is_match_owner(match_id));

create policy "Sety maže zapisovatel zápasu"
  on public.sets for delete
  to authenticated
  using (private.is_match_owner(match_id));


-- -----------------------------------------------------------------------------
-- points
-- -----------------------------------------------------------------------------
create policy "Body vidí ten, kdo vidí zápas"
  on public.points for select
  to authenticated
  using (private.can_read_match(match_id));

create policy "Body zapisuje zapisovatel zápasu"
  on public.points for insert
  to authenticated
  with check (private.is_match_owner(match_id));

create policy "Body upravuje zapisovatel zápasu"
  on public.points for update
  to authenticated
  using (private.is_match_owner(match_id))
  with check (private.is_match_owner(match_id));

create policy "Body maže zapisovatel zápasu"
  on public.points for delete
  to authenticated
  using (private.is_match_owner(match_id));
