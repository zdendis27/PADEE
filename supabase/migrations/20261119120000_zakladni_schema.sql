-- =============================================================================
-- PADEE · migrace 1/2 · základní schéma databáze (týden T3)
-- =============================================================================
-- Tabulky:
--   profiles       hráč (1:1 k účtu v auth.users, vzniká automaticky po registraci)
--   clubs          padelový klub (domovský klub hráče, místo zápasu, později žebříček)
--   matches        jeden zápas; zapisuje ho vždy jen jeden hráč (recorded_by)
--   match_players  kdo v zápase hrál: 2 týmy po 2 hráčích, hráč s účtem nebo host
--   sets           výsledek jednotlivých setů
--   points         každý odehraný bod (podklad pro graf průběhu a AI rozbor)
--
-- Diagram vztahů je v docs/datovy-model.md.
-- Bezpečnostní pravidla (RLS) jsou v další migraci 20261119120100_rls_politiky.sql.
-- RLS ale zapínáme už tady, hned při vytvoření tabulky, aby žádná tabulka
-- nebyla ani na okamžik otevřená všem.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Výčtové typy (enum): sloupec pak může obsahovat jen jednu z vyjmenovaných hodnot.
-- -----------------------------------------------------------------------------

-- Úroveň hráče, kterou si zvolí při prvním spuštění (cesta A).
create type public.player_level as enum ('beginner', 'intermediate', 'advanced');

-- Kdo zápas uvidí.
--   private = jen zapisovatel a hráči přidaní do zápasu
--   public  = kdokoli přihlášený (např. pro klubový feed)
-- Viditelnost „jen přátelé“ přidáme v T13, až budou přátelé.
create type public.match_visibility as enum ('private', 'public');

-- Stav zápasu. Přerušený zápas jde uložit jako nedohraný (cesta B, krok 6).
create type public.match_status as enum ('in_progress', 'finished', 'abandoned');


-- -----------------------------------------------------------------------------
-- Pomocná funkce: při každé úpravě řádku nastaví updated_at na aktuální čas.
-- -----------------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- clubs
-- -----------------------------------------------------------------------------
create table public.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 100),
  city        text check (char_length(city) <= 100),
  -- Kdo klub do aplikace přidal. Jen on ho smí upravit nebo smazat.
  -- Odkaz na auth.users (ne na profiles), protože profiles odkazuje zpět na clubs.
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.clubs enable row level security;

create trigger clubs_set_updated_at
  before update on public.clubs
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
create table public.profiles (
  -- Stejné id jako účet v auth.users. Smazáním účtu zmizí i profil (cascade).
  id                uuid primary key references auth.users (id) on delete cascade,
  -- PADEE ID: 5 znaků, velká písmena a číslice bez 0/O, 1/I/L (viz docs/uzivatelske-cesty.md).
  padee_id          text not null unique
                    check (padee_id ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{5}$'),
  -- PADEE ID jde změnit jen jednou, tady si pamatujeme, jestli už se to stalo.
  padee_id_changed  boolean not null default false,
  display_name      text check (char_length(display_name) <= 60),
  avatar_url        text,
  level             public.player_level,
  home_club_id      uuid references public.clubs (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.profiles enable row level security;

create index profiles_home_club_id_idx on public.profiles (home_club_id);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- Vygeneruje náhodné, ještě nepoužité PADEE ID.
-- 31 povolených znaků na 5 pozicích = 31^5 ≈ 28,6 milionu kombinací.
create function public.generate_padee_id()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := '';
    for i in 1..5 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    -- Pokud ID už někdo má, zkusíme to znovu (při 28 milionech kombinací vzácné).
    exit when not exists (select 1 from public.profiles where padee_id = candidate);
  end loop;
  return candidate;
end;
$$;


-- Po registraci (nový řádek v auth.users) automaticky založí profil.
-- Jméno vezme z údajů, které poslal Apple (pokud je poslal).
-- security definer = funkce běží s právy svého vlastníka, ne přihlášeného
-- uživatele; jinak by do profiles nesměla zapisovat (RLS).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, padee_id, display_name)
  values (
    new.id,
    public.generate_padee_id(),
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- -----------------------------------------------------------------------------
-- matches
-- -----------------------------------------------------------------------------
create table public.matches (
  id               uuid primary key default gen_random_uuid(),
  -- Kdo zápas nahrál (vlastník). Výchozí hodnota = přihlášený uživatel.
  recorded_by      uuid not null references public.profiles (id) on delete cascade
                   default auth.uid(),
  club_id          uuid references public.clubs (id) on delete set null,
  visibility       public.match_visibility not null default 'private',
  status           public.match_status not null default 'in_progress',

  -- Pravidla zápasu, jak je hráč nastavil na hodinkách (cesta B, krok 2).
  planned_sets     smallint not null default 3 check (planned_sets between 1 and 5),
  golden_point     boolean not null default true,
  tiebreak         boolean not null default true,
  first_server_team smallint check (first_server_team in (1, 2)),

  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  -- Vítězný tým (1 nebo 2); null u nedohraného zápasu.
  winner_team      smallint check (winner_team in (1, 2)),

  -- Data z hodinek (HealthKit), vyplní se v T6.
  avg_heart_rate   smallint check (avg_heart_rate between 30 and 250),
  active_calories  integer check (active_calories >= 0),

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  check (ended_at is null or ended_at >= started_at)
);

alter table public.matches enable row level security;

create index matches_recorded_by_idx on public.matches (recorded_by, started_at desc);
create index matches_club_id_idx on public.matches (club_id);

create trigger matches_set_updated_at
  before update on public.matches
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- match_players
-- -----------------------------------------------------------------------------
-- Padel je čtyřhra: 2 týmy po 2 hráčích. Zapisovatel po zápase přidá spoluhráče
-- a soupeře (cesta C, krok 3). Hráč buď má účet (profile_id), nebo je to host
-- jen se jménem (guest_name, cesta E).
create table public.match_players (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.matches (id) on delete cascade,
  team          smallint not null check (team in (1, 2)),
  profile_id    uuid references public.profiles (id) on delete set null,
  guest_name    text check (char_length(guest_name) between 1 and 60),
  -- Kdy hráč výsledek potvrdil (null = ještě nepotvrdil). Využijeme v T13.
  confirmed_at  timestamptz,
  created_at    timestamptz not null default now(),

  -- Každý řádek je buď hráč s účtem, nebo host (aspoň jedno musí být vyplněné).
  check (profile_id is not null or guest_name is not null),
  -- Stejný hráč nemůže být v jednom zápase dvakrát.
  unique (match_id, profile_id)
);

alter table public.match_players enable row level security;

create index match_players_profile_id_idx on public.match_players (profile_id);


-- -----------------------------------------------------------------------------
-- sets
-- -----------------------------------------------------------------------------
create table public.sets (
  id                 uuid primary key default gen_random_uuid(),
  match_id           uuid not null references public.matches (id) on delete cascade,
  set_number         smallint not null check (set_number between 1 and 5),
  team1_games        smallint not null default 0 check (team1_games between 0 and 7),
  team2_games        smallint not null default 0 check (team2_games between 0 and 7),
  -- Body v tiebreaku (jen pokud se v setu hrál).
  team1_tiebreak     smallint check (team1_tiebreak >= 0),
  team2_tiebreak     smallint check (team2_tiebreak >= 0),
  created_at         timestamptz not null default now(),

  unique (match_id, set_number)
);

alter table public.sets enable row level security;


-- -----------------------------------------------------------------------------
-- points
-- -----------------------------------------------------------------------------
-- Každý bod, jak ho hráč klepl na hodinkách. Body vrácené přes undo se do
-- databáze vůbec neposílají, hodinky pošlou až konečný seznam.
create table public.points (
  match_id         uuid not null references public.matches (id) on delete cascade,
  -- Pořadí bodu v zápase (1, 2, 3, …).
  seq              integer not null check (seq >= 1),
  set_number       smallint not null check (set_number between 1 and 5),
  game_number      smallint not null check (game_number >= 1),
  winner_team      smallint not null check (winner_team in (1, 2)),
  server_team      smallint check (server_team in (1, 2)),
  is_golden_point  boolean not null default false,
  is_tiebreak      boolean not null default false,
  scored_at        timestamptz not null default now(),

  primary key (match_id, seq)
);

alter table public.points enable row level security;
