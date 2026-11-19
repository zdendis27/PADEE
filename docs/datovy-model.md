# PADEE – datový model (Supabase)

Databáze v Supabase (PostgreSQL). Tabulky vznikají SQL migracemi ve složce [`supabase/migrations/`](../supabase/migrations/), bezpečnostní pravidla (RLS) jsou v druhé migraci. Model vychází z [uživatelských cest](uzivatelske-cesty.md).

## ER diagram

```mermaid
erDiagram
  AUTH_USERS ||--|| PROFILES : "má profil"
  CLUBS |o--o{ PROFILES : "domovský klub"
  PROFILES ||--o{ MATCHES : "zapisuje"
  CLUBS |o--o{ MATCHES : "hraje se v"
  MATCHES ||--|{ MATCH_PLAYERS : "hráči (2 týmy po 2)"
  PROFILES |o--o{ MATCH_PLAYERS : "hraje"
  MATCHES ||--o{ SETS : "má sety"
  MATCHES ||--o{ POINTS : "má body"

  PROFILES {
    uuid id PK "= auth.users.id"
    text padee_id UK "5 znaků, např. K7Q2M"
    bool padee_id_changed
    text display_name
    text avatar_url
    enum level "beginner / intermediate / advanced"
    uuid home_club_id FK
  }
  CLUBS {
    uuid id PK
    text name
    text city
    uuid created_by FK
  }
  MATCHES {
    uuid id PK
    uuid recorded_by FK "zapisovatel = vlastník"
    uuid club_id FK
    enum visibility "private / public"
    enum status "in_progress / finished / abandoned"
    smallint planned_sets
    bool golden_point
    bool tiebreak
    smallint first_server_team
    timestamptz started_at
    timestamptz ended_at
    smallint winner_team "1 / 2"
    smallint avg_heart_rate
    int active_calories
  }
  MATCH_PLAYERS {
    uuid id PK
    uuid match_id FK
    smallint team "1 / 2"
    uuid profile_id FK "hráč s účtem"
    text guest_name "nebo host bez účtu"
    timestamptz confirmed_at "potvrzení výsledku (T13)"
  }
  SETS {
    uuid id PK
    uuid match_id FK
    smallint set_number
    smallint team1_games
    smallint team2_games
    smallint team1_tiebreak
    smallint team2_tiebreak
  }
  POINTS {
    uuid match_id PK, FK
    int seq PK "pořadí bodu v zápase"
    smallint set_number
    smallint game_number
    smallint winner_team
    smallint server_team
    bool is_golden_point
    bool is_tiebreak
    timestamptz scored_at
  }
```

## Proč je to takhle

| Rozhodnutí | Důvod |
| --- | --- |
| Profil vzniká sám po registraci | Trigger `on_auth_user_created` založí profil a přidělí náhodné PADEE ID, aplikace nemusí nic řešit. |
| Tabulka `match_players` navíc | Zápas jsou 2 týmy po 2 a zapisovatel po zápase přidá spoluhráče, soupeře nebo hosta jen se jménem. Přes ni hráči vidí zápas, do kterého je někdo přidal. |
| Týmy jsou čísla 1 a 2 | Na hodinkách se klepe jen „My / Oni“. Tým 1 je vždy tým zapisovatele. |
| `points` má klíč (zápas, pořadí) | Hodinky posílají konečný seznam bodů; body vrácené přes undo se do databáze vůbec nedostanou. Stejný bod nejde uložit dvakrát. |
| `visibility` private / public | Výchozí je soukromý zápas. Viditelnost „jen přátelé“ přidáme v T13 spolu s tabulkou přátel. |

## Kdo co smí (RLS)

| Tabulka | Číst | Zapisovat / měnit / mazat |
| --- | --- | --- |
| `profiles` | každý přihlášený (hledání podle PADEE ID) | jen svůj profil |
| `clubs` | každý přihlášený | kdo klub přidal |
| `matches` | zapisovatel, hráči přidaní do zápasu, u veřejného zápasu všichni přihlášení | jen zapisovatel |
| `match_players`, `sets`, `points` | kdo smí číst zápas | jen zapisovatel zápasu |

Nepřihlášený klient (`anon`) nesmí nic. Že to platí, ověřuje test [`supabase/tests/rls_zapasy_test.sql`](../supabase/tests/rls_zapasy_test.sql).

## Co přijde později

- **T10** sync z hodinek: zápis zápasu, setů a bodů najednou (Edge Function nebo RPC).
- **T13** přátelé (`friendships`), potvrzování výsledku (`confirmed_at` přes funkci), viditelnost „jen přátelé“, Head-to-Head.
- **T14** klubové žebříčky (Elo).
