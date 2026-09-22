-- Catastrophic Cats - Initial Schema

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Profiles table (linked to auth.users)
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  created_at timestamptz default now()
);

-- Game rooms table
create table game_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text unique not null,
  status text not null default 'lobby',
  host_id uuid references profiles(id),
  min_players int not null default 2,
  max_players int not null default 5,
  created_at timestamptz default now(),
  started_at timestamptz,
  finished_at timestamptz,
  winner_id uuid references profiles(id),
  win_type text
);

-- Game players table
create table game_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references game_rooms(id) on delete cascade,
  player_id uuid references profiles(id),
  seat_order int not null,
  is_alive boolean not null default true,
  hand jsonb not null default '[]',
  collection jsonb not null default '[]',
  skip_next boolean not null default false,
  protected boolean not null default false,
  nine_lives_active boolean not null default false,
  unique(room_id, player_id),
  unique(room_id, seat_order)
);

-- Game state table (one row per room)
create table game_state (
  room_id uuid primary key references game_rooms(id) on delete cascade,
  draw_pile jsonb not null default '[]',
  market jsonb not null default '[]',
  discard_pile jsonb not null default '[]',
  current_turn_seat int not null default 0,
  turn_number int not null default 0,
  updated_at timestamptz default now()
);

-- Game log table
create table game_log (
  id bigint generated always as identity primary key,
  room_id uuid references game_rooms(id) on delete cascade,
  turn_number int,
  actor_id uuid,
  event_type text not null,
  payload jsonb,
  created_at timestamptz default now()
);

-- Enable RLS
alter table profiles enable row level security;
alter table game_rooms enable row level security;
alter table game_players enable row level security;
alter table game_state enable row level security;
alter table game_log enable row level security;

-- Profiles policies
create policy "Public profiles are viewable by everyone"
  on profiles for select
  using (true);

create policy "Users can insert their own profile"
  on profiles for insert
  with check (auth.uid() = id);

create policy "Users can update their own profile"
  on profiles for update
  using (auth.uid() = id);

-- Game rooms policies
create policy "Game rooms are viewable by everyone"
  on game_rooms for select
  using (true);

create policy "Authenticated users can create game rooms"
  on game_rooms for insert
  with check (auth.uid() = host_id);

-- Game players public view (excludes hand)
create or replace view game_players_public as
select 
  id,
  room_id,
  player_id,
  seat_order,
  is_alive,
  collection,
  skip_next,
  protected,
  nine_lives_active
from game_players;

create policy "Game players public data viewable by everyone"
  on game_players_public for select
  using (true);

create policy "Players can see their own hand"
  on game_players for select
  using (auth.uid() = player_id);

create policy "Players can update their own data"
  on game_players for update
  using (auth.uid() = player_id);

-- Game state public view (excludes draw_pile content)
create or replace view game_state_public as
select 
  room_id,
  jsonb_array_length(draw_pile) as draw_pile_count,
  market,
  discard_pile,
  current_turn_seat,
  turn_number,
  updated_at
from game_state;

create policy "Game state public data viewable by everyone"
  on game_state_public for select
  using (true);

-- Game log policies
create policy "Game log viewable by everyone"
  on game_log for select
  using (true);

-- Function to create a room
create or replace function create_room(nickname text)
returns uuid
language plpgsql
security definer
as $$
declare
  user_id uuid;
  room_id uuid;
  generated_code text;
begin
  -- Create or update profile
  user_id := auth.uid();
  
  insert into profiles (id, nickname)
  values (user_id, nickname)
  on conflict (id) do update set nickname = create_room.nickname;
  
  -- Generate unique 6-char code
  loop
    generated_code := upper(substring(md5(random()::text) from 1 for 6));
    exit when not exists (select 1 from game_rooms where room_code = generated_code);
  end loop;
  
  -- Create room
  insert into game_rooms (room_code, host_id, status)
  values (generated_code, user_id, 'lobby')
  returning id into room_id;
  
  -- Add host as first player
  insert into game_players (room_id, player_id, seat_order)
  values (room_id, user_id, 0);
  
  return room_id;
end;
$$;

-- Function to join a room
create or replace function join_room(room_code text, nickname text)
returns uuid
language plpgsql
security definer
as $$
declare
  user_id uuid;
  target_room_id uuid;
  next_seat int;
begin
  -- Create or update profile
  user_id := auth.uid();
  
  insert into profiles (id, nickname)
  values (user_id, nickname)
  on conflict (id) do update set nickname = join_room.nickname;
  
  -- Find room
  select id into target_room_id
  from game_rooms
  where game_rooms.room_code = join_room.room_code
    and status = 'lobby';
  
  if target_room_id is null then
    raise exception 'Szoba nem található vagy már indult a játék';
  end if;
  
  -- Check if already joined
  if exists (select 1 from game_players where room_id = target_room_id and player_id = user_id) then
    return target_room_id;
  end if;
  
  -- Get next seat order
  select coalesce(max(seat_order), -1) + 1 into next_seat
  from game_players
  where room_id = target_room_id;
  
  -- Check max players
  if next_seat >= (select max_players from game_rooms where id = target_room_id) then
    raise exception 'A szoba megtelt';
  end if;
  
  -- Add player
  insert into game_players (room_id, player_id, seat_order)
  values (target_room_id, user_id, next_seat);
  
  return target_room_id;
end;
$$;

-- Function to start game
create or replace function start_game(target_room_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  room_host uuid;
  player_count int;
  deck jsonb;
begin
  -- Verify host
  select host_id into room_host
  from game_rooms
  where id = target_room_id;
  
  if room_host != auth.uid() then
    raise exception 'Csak a host indíthatja a játékot';
  end if;
  
  -- Check player count
  select count(*) into player_count
  from game_players
  where room_id = target_room_id;
  
  if player_count < 2 or player_count > 5 then
    raise exception '2-5 játékos szükséges a játék indításához';
  end if;
  
  -- Build deck (simplified for now)
  deck := '["test_card"]'::jsonb;
  
  -- Update room status
  update game_rooms
  set status = 'in_progress',
      started_at = now()
  where id = target_room_id;
  
  -- Initialize game state
  insert into game_state (room_id, draw_pile, market)
  values (target_room_id, deck, '[]'::jsonb);
  
  -- Log event
  insert into game_log (room_id, event_type, payload)
  values (target_room_id, 'game_started', jsonb_build_object('player_count', player_count));
end;
$$;
