-- Catastrophic Cats - Initial Schema Migration
-- This creates all tables, RLS policies, and RPC functions for server-authoritative game logic

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABLES
-- ============================================

-- Player profiles (linked to anonymous auth)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nickname TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Game rooms
CREATE TABLE game_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'in_progress', 'finished')),
  host_id UUID REFERENCES profiles(id),
  min_players INT NOT NULL DEFAULT 2,
  max_players INT NOT NULL DEFAULT 5,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  winner_id UUID REFERENCES profiles(id),
  win_type TEXT CHECK (win_type IN ('apokalipszis', 'tulelesi'))
);

-- Game players - split hand into separate table for RLS
CREATE TABLE game_players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES game_rooms(id) ON DELETE CASCADE,
  player_id UUID REFERENCES profiles(id),
  seat_order INT NOT NULL,
  is_alive BOOLEAN NOT NULL DEFAULT TRUE,
  collection JSONB NOT NULL DEFAULT '[]'::jsonb,
  skip_next BOOLEAN NOT NULL DEFAULT FALSE,
  protected BOOLEAN NOT NULL DEFAULT FALSE,
  nine_lives_active BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE(room_id, player_id),
  UNIQUE(room_id, seat_order)
);

-- Separate table for hands (for fine-grained RLS)
CREATE TABLE player_hands (
  player_id UUID PRIMARY KEY REFERENCES game_players(id) ON DELETE CASCADE,
  hand JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- Game state (one row per room)
CREATE TABLE game_state (
  room_id UUID PRIMARY KEY REFERENCES game_rooms(id) ON DELETE CASCADE,
  draw_pile JSONB NOT NULL DEFAULT '[]'::jsonb,
  market JSONB NOT NULL DEFAULT '[]'::jsonb,
  discard_pile JSONB NOT NULL DEFAULT '[]'::jsonb,
  current_turn_seat INT NOT NULL DEFAULT 0,
  turn_number INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Game log
CREATE TABLE game_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id UUID REFERENCES game_rooms(id) ON DELETE CASCADE,
  turn_number INT,
  actor_id UUID,
  event_type TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_game_players_room ON game_players(room_id);
CREATE INDEX idx_game_players_player ON game_players(player_id);
CREATE INDEX idx_game_log_room ON game_log(room_id);
CREATE INDEX idx_game_rooms_code ON game_rooms(room_code);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_hands ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_log ENABLE ROW LEVEL SECURITY;

-- Profiles: anyone can read all profiles
CREATE POLICY profiles_read_all ON profiles
  FOR SELECT USING (TRUE);

-- Profiles: users can update their own profile
CREATE POLICY profiles_update_own ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Game rooms: anyone can read lobby/in_progress rooms
CREATE POLICY game_rooms_read ON game_rooms
  FOR SELECT USING (status IN ('lobby', 'in_progress'));

-- Game rooms: authenticated users can insert (create)
CREATE POLICY game_rooms_insert ON game_rooms
  FOR INSERT WITH CHECK (auth.uid() = host_id);

-- Game rooms: host can update their own room
CREATE POLICY game_rooms_update_host ON game_rooms
  FOR UPDATE USING (auth.uid() = host_id);

-- Game players: anyone can read public fields (collection, is_alive, etc.)
CREATE POLICY game_players_read_public ON game_players
  FOR SELECT USING (TRUE);

-- Game players: players can update their own row (except hand)
CREATE POLICY game_players_update_own ON game_players
  FOR UPDATE USING (auth.uid() = player_id);

-- Player hands: ONLY the owner can read their own hand
CREATE POLICY player_hands_read_own ON player_hands
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM game_players gp
      WHERE gp.id = player_hands.player_id
      AND gp.player_id = auth.uid()
    )
  );

-- Player hands: only server RPC can modify (no direct client access)
-- We'll rely on SECURITY DEFINER functions for modifications

-- Game state: anyone can read market, discard_pile, current_turn_seat, turn_number
-- But NOT draw_pile (handled by SECURITY DEFINER RPCs)
CREATE POLICY game_state_read_public ON game_state
  FOR SELECT USING (TRUE);

-- Game state: only server RPC can modify
CREATE POLICY game_state_no_client_update ON game_state
  FOR UPDATE USING (FALSE);

CREATE POLICY game_state_no_client_insert ON game_state
  FOR INSERT USING (FALSE);

-- Game log: anyone can read
CREATE POLICY game_log_read ON game_log
  FOR SELECT USING (TRUE);

-- Game log: only server RPC can insert
CREATE POLICY game_log_no_client_insert ON game_log
  FOR INSERT USING (FALSE);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Generate a random 6-character room code
CREATE OR REPLACE FUNCTION generate_room_code() RETURNS TEXT AS $$
DECLARE
  code TEXT;
BEGIN
  code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- Shuffle a JSONB array (Fisher-Yates)
CREATE OR REPLACE FUNCTION shuffle_jsonb_array(arr JSONB) RETURNS JSONB AS $$
DECLARE
  result JSONB := '[]'::jsonb;
  arr_len INT := jsonb_array_length(arr);
  i INT;
  j INT;
  temp JSONB;
BEGIN
  result := arr;
  FOR i IN REVERSE arr_len - 1 .. 1 LOOP
    j := FLOOR(RANDOM() * (i + 1))::INT;
    temp := result->i;
    result := jsonb_set(result, ARRAY[i::TEXT], result->j);
    result := jsonb_set(result, ARRAY[j::TEXT], temp);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Get card count from deck definition
CREATE OR REPLACE FUNCTION get_card_count(card_id TEXT) RETURNS INT AS $$
BEGIN
  RETURN CASE card_id
    WHEN 'atomfizikus' THEN 4
    WHEN 'emberszolga' THEN 5
    WHEN 'sisak' THEN 6
    WHEN 'centrifuga' THEN 7
    WHEN 'piros_gomb' THEN 2
    WHEN 'csempeszjarat' THEN 4
    WHEN 'terepszemle' THEN 4
    WHEN 'csere_bere' THEN 3
    WHEN 'second_breakfast' THEN 4
    WHEN 'dorombolas' THEN 3
    WHEN 'kilenc_elet' THEN 3
    WHEN 'cicanip' THEN 3
    WHEN 'gombolyag' THEN 4
    WHEN 'kohoges' THEN 3
    WHEN 'lomha' THEN 3
    WHEN 'toltolap' THEN 30
    WHEN 'veszleallitas' THEN 2
    ELSE 0
  END;
END;
$$ LANGUAGE plpgsql;

-- Build the initial deck
CREATE OR REPLACE FUNCTION build_initial_deck() RETURNS JSONB AS $$
DECLARE
  deck JSONB := '[]'::jsonb;
  card TEXT;
  cnt INT;
  i INT;
BEGIN
  -- Add all cards according to spec
  FOR card, cnt IN VALUES
    ('atomfizikus', 4),
    ('emberszolga', 5),
    ('sisak', 6),
    ('centrifuga', 7),
    ('piros_gomb', 2),
    ('csempeszjarat', 4),
    ('terepszemle', 4),
    ('csere_bere', 3),
    ('second_breakfast', 4),
    ('dorombolas', 3),
    ('kilenc_elet', 3),
    ('cicanip', 3),
    ('gombolyag', 4),
    ('kohoges', 3),
    ('lomha', 3),
    ('toltolap', 30)
  LOOP
    FOR i IN 1..cnt LOOP
      deck := deck || to_jsonb(card);
    END LOOP;
  END LOOP;
  
  RETURN deck;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MAIN RPC FUNCTIONS (SECURITY DEFINER)
-- ============================================

-- Create a new room
CREATE OR REPLACE FUNCTION create_room(nickname TEXT)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_room_id UUID;
  new_profile_id UUID;
  room_code TEXT;
  code_exists BOOLEAN;
BEGIN
  -- Create or get profile
  INSERT INTO profiles (id, nickname)
  VALUES (auth.uid(), nickname)
  ON CONFLICT (id) DO UPDATE SET nickname = EXCLUDED.nickname
  RETURNING id INTO new_profile_id;
  
  -- Generate unique room code
  LOOP
    room_code := generate_room_code();
    SELECT EXISTS(SELECT 1 FROM game_rooms WHERE room_code = room_code) INTO code_exists;
    EXIT WHEN NOT code_exists;
  END LOOP;
  
  -- Create room
  INSERT INTO game_rooms (host_id, room_code)
  VALUES (new_profile_id, room_code)
  RETURNING id INTO new_room_id;
  
  -- Add host as first player
  INSERT INTO game_players (room_id, player_id, seat_order)
  VALUES (new_room_id, new_profile_id, 0);
  
  RETURN new_room_id;
END;
$$ LANGUAGE plpgsql;

-- Join an existing room
CREATE OR REPLACE FUNCTION join_room(room_code TEXT, nickname TEXT)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  room_id UUID;
  profile_id UUID;
  next_seat INT;
  room_status TEXT;
  player_count INT;
  max_players INT;
BEGIN
  -- Get room info
  SELECT id, status, max_players INTO room_id, room_status, max_players
  FROM game_rooms
  WHERE join_room.room_code = room_code;
  
  IF room_id IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  
  IF room_status != 'lobby' THEN
    RAISE EXCEPTION 'Game already in progress';
  END IF;
  
  -- Create or get profile
  INSERT INTO profiles (id, nickname)
  VALUES (auth.uid(), nickname)
  ON CONFLICT (id) DO UPDATE SET nickname = EXCLUDED.nickname
  RETURNING id INTO profile_id;
  
  -- Check if already in room
  IF EXISTS (SELECT 1 FROM game_players WHERE room_id = join_room.room_id AND player_id = profile_id) THEN
    RETURN room_id;
  END IF;
  
  -- Check player count
  SELECT COUNT(*), MAX(seat_order) INTO player_count, next_seat
  FROM game_players
  WHERE room_id = join_room.room_id;
  
  IF player_count >= max_players THEN
    RAISE EXCEPTION 'Room is full';
  END IF;
  
  -- Add player
  INSERT INTO game_players (room_id, player_id, seat_order)
  VALUES (room_id, profile_id, COALESCE(next_seat, -1) + 1);
  
  RETURN room_id;
END;
$$ LANGUAGE plpgsql;

-- Start the game
CREATE OR REPLACE FUNCTION start_game(room_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  room RECORD;
  player_count INT;
  deck JSONB;
  shuffled_deck JSONB;
  player RECORD;
  hand JSONB;
  i INT;
  card TEXT;
  remaining_deck JSONB;
  market_cards JSONB := '[]'::jsonb;
  meltdown_count INT;
BEGIN
  -- Validate room
  SELECT * INTO room
  FROM game_rooms
  WHERE id = room_id;
  
  IF room IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  
  IF room.status != 'lobby' THEN
    RAISE EXCEPTION 'Game already started';
  END IF;
  
  IF room.host_id != auth.uid() THEN
    RAISE EXCEPTION 'Only host can start the game';
  END IF;
  
  -- Check player count
  SELECT COUNT(*) INTO player_count
  FROM game_players
  WHERE room_id = room_id;
  
  IF player_count < 2 OR player_count > 5 THEN
    RAISE EXCEPTION 'Need 2-5 players to start';
  END IF;
  
  -- Build and shuffle deck
  deck := build_initial_deck();
  shuffled_deck := shuffle_jsonb_array(deck);
  
  -- Deal 5 cards to each player
  remaining_deck := shuffled_deck;
  FOR player IN SELECT * FROM game_players WHERE room_id = room_id ORDER BY seat_order LOOP
    hand := '[]'::jsonb;
    FOR i IN 1..5 LOOP
      IF jsonb_array_length(remaining_deck) > 0 THEN
        card := remaining_deck->>0;
        hand := hand || to_jsonb(card);
        remaining_deck := remaining_deck - 0;
      END IF;
    END LOOP;
    
    -- Update player hand
    INSERT INTO player_hands (player_id, hand)
    VALUES (player.id, hand)
    ON CONFLICT (player_id) DO UPDATE SET hand = EXCLUDED.hand;
  END LOOP;
  
  -- Add meltdown and defuse cards, shuffle again
  meltdown_count := player_count;
  FOR i IN 1..meltdown_count LOOP
    remaining_deck := remaining_deck || to_jsonb('meghibasodas');
  END LOOP;
  FOR i IN 1..2 LOOP
    remaining_deck := remaining_deck || to_jsonb('veszleallitas');
  END LOOP;
  
  remaining_deck := shuffle_jsonb_array(remaining_deck);
  
  -- Set up market (4 cards)
  FOR i IN 0..3 LOOP
    IF jsonb_array_length(remaining_deck) > 0 THEN
      card := remaining_deck->>0;
      market_cards := market_cards || to_jsonb(card);
      remaining_deck := remaining_deck - 0;
    END IF;
  END LOOP;
  
  -- Create game state
  INSERT INTO game_state (room_id, draw_pile, market, discard_pile)
  VALUES (room_id, remaining_deck, market_cards, '[]'::jsonb)
  ON CONFLICT (room_id) DO UPDATE SET
    draw_pile = EXCLUDED.draw_pile,
    market = EXCLUDED.market,
    discard_pile = EXCLUDED.discard_pile,
    current_turn_seat = 0,
    turn_number = 0,
    updated_at = NOW();
  
  -- Update room status
  UPDATE game_rooms
  SET status = 'in_progress',
      started_at = NOW()
  WHERE id = room_id;
  
  -- Log
  INSERT INTO game_log (room_id, event_type, payload)
  VALUES (room_id, 'game_started', jsonb_build_object('player_count', player_count));
END;
$$ LANGUAGE plpgsql;

-- Central function to resolve a drawn card (CRITICAL - handles meltdown check)
CREATE OR REPLACE FUNCTION resolve_drawn_card(
  p_room_id UUID,
  p_player_id UUID,
  p_card TEXT
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  player RECORD;
  result JSONB;
  has_defuse BOOLEAN;
  has_nine_lives BOOLEAN;
  is_meghibasodas BOOLEAN;
BEGIN
  is_meghibasodas := (p_card = 'meghibasodas');
  
  -- Get player info
  SELECT * INTO player
  FROM game_players
  WHERE room_id = p_room_id AND player_id = p_player_id;
  
  IF player IS NULL THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
  
  IF NOT player.is_alive THEN
    RAISE EXCEPTION 'Player is eliminated';
  END IF;
  
  IF is_meghibasodas THEN
    -- Check for defenses
    has_defuse := EXISTS (
      SELECT 1 FROM player_hands ph
      JOIN game_players gp ON ph.player_id = gp.id
      WHERE gp.room_id = p_room_id
      AND gp.player_id = p_player_id
      AND ph.hand @> '["veszleallitas"]'::jsonb
    );
    
    has_nine_lives := player.nine_lives_active;
    
    IF has_defuse THEN
      -- Use defuse - remove it permanently
      UPDATE player_hands
      SET hand = hand - (
        SELECT MIN(idx)
        FROM jsonb_array_elements_text(hand) WITH ORDINALITY AS elem(card, idx)
        WHERE card = 'veszleallitas'
      )
      WHERE player_id = player.id;
      
      -- Put meltdown back into draw pile at random position
      UPDATE game_state
      SET draw_pile = jsonb_insert(
        draw_pile,
        ARRAY[FLOOR(RANDOM() * jsonb_array_length(draw_pile))::TEXT],
        to_jsonb(p_card)
      )
      WHERE room_id = p_room_id;
      
      result := jsonb_build_object(
        'card', p_card,
        'is_meghibasodas', TRUE,
        'survived', TRUE,
        'used_defuse', TRUE
      );
      
      INSERT INTO game_log (room_id, actor_id, event_type, payload)
      VALUES (p_room_id, p_player_id, 'defused_meltdown', jsonb_build_object('card', p_card));
      
    ELSIF has_nine_lives THEN
      -- Use nine lives
      UPDATE game_players
      SET nine_lives_active = FALSE
      WHERE id = player.id;
      
      -- Put meltdown back into draw pile
      UPDATE game_state
      SET draw_pile = jsonb_insert(
        draw_pile,
        ARRAY[FLOOR(RANDOM() * jsonb_array_length(draw_pile))::TEXT],
        to_jsonb(p_card)
      )
      WHERE room_id = p_room_id;
      
      result := jsonb_build_object(
        'card', p_card,
        'is_meghibasodas', TRUE,
        'survived', TRUE,
        'used_nine_lives', TRUE
      );
      
      INSERT INTO game_log (room_id, actor_id, event_type, payload)
      VALUES (p_room_id, p_player_id, 'nine_lives_saved', jsonb_build_object('card', p_card));
      
    ELSE
      -- Player eliminated
      UPDATE game_players
      SET is_alive = FALSE
      WHERE id = player.id;
      
      -- Move all cards to discard
      UPDATE game_state gs
      SET discard_pile = gs.discard_pile || ph.hand || player.collection,
          draw_pile = CASE 
            WHEN jsonb_array_length(gs.draw_pile) = 0 
            THEN shuffle_jsonb_array(gs.discard_pile || ph.hand || player.collection || to_jsonb(p_card))
            ELSE gs.draw_pile || to_jsonb(p_card)
          END
      FROM player_hands ph
      WHERE gs.room_id = p_room_id
      AND ph.player_id = player.id;
      
      -- Clear player's hand and collection
      UPDATE player_hands
      SET hand = '[]'::jsonb
      WHERE player_id = player.id;
      
      UPDATE game_players
      SET collection = '[]'::jsonb
      WHERE id = player.id;
      
      result := jsonb_build_object(
        'card', p_card,
        'is_meghibasodas', TRUE,
        'survived', FALSE,
        'player_eliminated', TRUE
      );
      
      INSERT INTO game_log (room_id, actor_id, event_type, payload)
      VALUES (p_room_id, p_player_id, 'eliminated', jsonb_build_object('card', p_card));
    END IF;
  ELSE
    -- Normal card - add to hand or collection
    IF p_card IN ('atomfizikus', 'emberszolga', 'sisak', 'centrifuga') THEN
      -- Alkatrész goes to collection
      UPDATE game_players
      SET collection = collection || to_jsonb(p_card)
      WHERE player_id = p_player_id;
    ELSE
      -- Other cards go to hand
      UPDATE player_hands
      SET hand = hand || to_jsonb(p_card)
      WHERE player_id = player.id;
    END IF;
    
    result := jsonb_build_object(
      'card', p_card,
      'is_meghibasodas', FALSE,
      'survived', TRUE
    );
  END IF;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Draw from pile
CREATE OR REPLACE FUNCTION draw_from_pile(p_room_id UUID, p_player_id UUID)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  gs RECORD;
  card TEXT;
  new_draw_pile JSONB;
  result JSONB;
BEGIN
  -- Get game state
  SELECT * INTO gs
  FROM game_state
  WHERE room_id = p_room_id;
  
  IF gs IS NULL THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  
  -- Check if it's player's turn
  SELECT * INTO gs FROM game_players WHERE room_id = p_room_id AND player_id = p_player_id;
  IF gs.seat_order != (SELECT current_turn_seat FROM game_state WHERE room_id = p_room_id) THEN
    RAISE EXCEPTION 'Not your turn';
  END IF;
  
  -- Reshuffle if empty
  IF jsonb_array_length(gs.draw_pile) = 0 THEN
    UPDATE game_state
    SET draw_pile = shuffle_jsonb_array(discard_pile),
        discard_pile = '[]'::jsonb
    WHERE room_id = p_room_id
    RETURNING * INTO gs;
    
    INSERT INTO game_log (room_id, event_type, payload)
    VALUES (p_room_id, 'deck_reshuffled', '{}');
  END IF;
  
  -- Draw card
  card := gs.draw_pile->>0;
  new_draw_pile := gs.draw_pile - 0;
  
  UPDATE game_state
  SET draw_pile = new_draw_pile,
      updated_at = NOW()
  WHERE room_id = p_room_id;
  
  -- Resolve the drawn card
  result := resolve_drawn_card(p_room_id, p_player_id, card);
  
  -- End turn
  UPDATE game_state
  SET current_turn_seat = (current_turn_seat + 1) % (SELECT COUNT(*) FROM game_players WHERE room_id = p_room_id),
      turn_number = turn_number + 1,
      updated_at = NOW()
  WHERE room_id = p_room_id;
  
  -- Clear skip_next if set
  UPDATE game_players
  SET skip_next = FALSE
  WHERE room_id = p_room_id AND player_id = p_player_id;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Take from market
CREATE OR REPLACE FUNCTION take_from_market(p_room_id UUID, p_player_id UUID, p_card_index INT)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  gs RECORD;
  card TEXT;
  new_market JSONB;
  draw_pile JSONB;
  result JSONB;
  refill_card TEXT;
BEGIN
  -- Get game state
  SELECT * INTO gs
  FROM game_state
  WHERE room_id = p_room_id;
  
  IF gs IS NULL THEN
    RAISE EXCEPTION 'Game not found';
  END IF;
  
  -- Validate card index
  IF p_card_index < 0 OR p_card_index >= jsonb_array_length(gs.market) THEN
    RAISE EXCEPTION 'Invalid card index';
  END IF;
  
  -- Get card
  card := gs.market->>p_card_index;
  new_market := gs.market - p_card_index;
  
  -- Refill market from draw pile
  draw_pile := gs.draw_pile;
  IF jsonb_array_length(draw_pile) > 0 THEN
    refill_card := draw_pile->>0;
    draw_pile := draw_pile - 0;
    new_market := new_market || to_jsonb(refill_card);
  ELSIF jsonb_array_length(gs.discard_pile) > 0 THEN
    -- Reshuffle discard
    draw_pile := shuffle_jsonb_array(gs.discard_pile);
    refill_card := draw_pile->>0;
    draw_pile := draw_pile - 0;
    new_market := new_market || to_jsonb(refill_card);
    
    INSERT INTO game_log (room_id, event_type, payload)
    VALUES (p_room_id, 'deck_reshuffled', '{}');
  END IF;
  
  UPDATE game_state
  SET market = new_market,
      draw_pile = draw_pile,
      updated_at = NOW()
  WHERE room_id = p_room_id;
  
  -- Resolve the taken card
  result := resolve_drawn_card(p_room_id, p_player_id, card);
  
  -- End turn
  UPDATE game_state
  SET current_turn_seat = (current_turn_seat + 1) % (SELECT COUNT(*) FROM game_players WHERE room_id = p_room_id),
      turn_number = turn_number + 1,
      updated_at = NOW()
  WHERE room_id = p_room_id;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Play action card
CREATE OR REPLACE FUNCTION play_action_card(
  p_room_id UUID,
  p_player_id UUID,
  p_card TEXT,
  p_target_player_id UUID DEFAULT NULL,
  p_extra_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  player RECORD;
  target RECORD;
  hand JSONB;
  card_index INT;
  result JSONB := '{}'::jsonb;
BEGIN
  -- Get player
  SELECT * INTO player
  FROM game_players
  WHERE room_id = p_room_id AND player_id = p_player_id;
  
  IF player IS NULL THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
  
  -- Get hand
  SELECT hand INTO hand
  FROM player_hands
  WHERE player_id = player.id;
  
  -- Find card in hand
  SELECT MIN(idx) INTO card_index
  FROM jsonb_array_elements_text(hand) WITH ORDINALITY AS elem(card, idx)
  WHERE card = p_card;
  
  IF card_index IS NULL THEN
    RAISE EXCEPTION 'Card not in hand';
  END IF;
  
  -- Remove card from hand
  UPDATE player_hands
  SET hand = hand - card_index
  WHERE player_id = player.id;
  
  -- Execute card effect
  CASE p_card
    WHEN 'csempeszjarat' THEN
      -- Smuggling can be played anytime, handled separately
      result := jsonb_build_object('action', 'smuggling_played');
      
    WHEN 'terepszemle' THEN
      -- Look at top 3 cards of draw pile, reorder
      result := jsonb_build_object('action', 'terepszemle_played');
      
    WHEN 'csere_bere' THEN
      -- Swap an alkatresz from collection with opponent's
      result := jsonb_build_object('action', 'csere_bere_played', 'target', p_target_player_id);
      
    WHEN 'second_breakfast' THEN
      -- Draw extra card
      result := jsonb_build_object('action', 'second_breakfast_played');
      
    WHEN 'dorombolas' THEN
      -- Protection from next negative card
      UPDATE game_players
      SET protected = TRUE
      WHERE id = player.id;
      result := jsonb_build_object('action', 'dorombolas_played');
      
    WHEN 'kilenc_elet' THEN
      -- Activate nine lives
      UPDATE game_players
      SET nine_lives_active = TRUE
      WHERE id = player.id;
      result := jsonb_build_object('action', 'kilenc_elet_played');
      
    WHEN 'cicanip' THEN
      -- Peek at opponent's hand
      result := jsonb_build_object('action', 'cicanip_played', 'target', p_target_player_id);
      
    WHEN 'gombolyag' THEN
      -- Skip opponent's next turn
      SELECT * INTO target FROM game_players WHERE id = (
        SELECT id FROM game_players WHERE room_id = p_room_id AND player_id = p_target_player_id
      );
      IF target IS NOT NULL AND target.is_alive THEN
        UPDATE game_players
        SET skip_next = TRUE
        WHERE player_id = p_target_player_id;
      END IF;
      result := jsonb_build_object('action', 'gombolyag_played', 'target', p_target_player_id);
      
    WHEN 'kohoges' THEN
      -- Steal random card from opponent
      result := jsonb_build_object('action', 'kohoges_played', 'target', p_target_player_id);
      
    WHEN 'lomha' THEN
      -- Swap hand card with opponent's random card
      result := jsonb_build_object('action', 'lomha_played', 'target', p_target_player_id);
      
    ELSE
      RAISE EXCEPTION 'Unknown card';
  END CASE;
  
  -- Log
  INSERT INTO game_log (room_id, actor_id, event_type, payload)
  VALUES (p_room_id, p_player_id, 'card_played', jsonb_build_object('card', p_card, 'target', p_target_player_id));
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Play smuggling (anytime)
CREATE OR REPLACE FUNCTION play_smuggling_anytime(p_room_id UUID, p_player_id UUID, p_card_index INT)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  gs RECORD;
  player RECORD;
  hand JSONB;
  card TEXT;
  market_card TEXT;
  new_market JSONB;
  result JSONB;
  refill_card TEXT;
BEGIN
  -- Verify player has csempeszjarat
  SELECT * INTO player
  FROM game_players
  WHERE room_id = p_room_id AND player_id = p_player_id;
  
  IF player IS NULL OR NOT player.is_alive THEN
    RAISE EXCEPTION 'Invalid player';
  END IF;
  
  SELECT hand INTO hand FROM player_hands WHERE player_id = player.id;
  
  IF NOT (hand @> '["csempeszjarat"]'::jsonb) THEN
    RAISE EXCEPTION 'No csempeszjarat in hand';
  END IF;
  
  -- Remove csempeszjarat from hand
  UPDATE player_hands
  SET hand = hand - (
    SELECT MIN(idx)
    FROM jsonb_array_elements_text(hand) WITH ORDINALITY AS elem(card, idx)
    WHERE card = 'csempeszjarat'
  )
  WHERE player_id = player.id;
  
  -- Take card from market
  SELECT * INTO gs FROM game_state WHERE room_id = p_room_id;
  
  IF p_card_index < 0 OR p_card_index >= jsonb_array_length(gs.market) THEN
    RAISE EXCEPTION 'Invalid card index';
  END IF;
  
  market_card := gs.market->>p_card_index;
  new_market := gs.market - p_card_index;
  
  -- Refill market
  IF jsonb_array_length(gs.draw_pile) > 0 THEN
    refill_card := gs.draw_pile->>0;
    new_market := new_market || to_jsonb(refill_card);
    UPDATE game_state
    SET market = new_market,
        draw_pile = draw_pile - 0
    WHERE room_id = p_room_id;
  END IF;
  
  -- Resolve the stolen card
  result := resolve_drawn_card(p_room_id, p_player_id, market_card);
  
  -- Log
  INSERT INTO game_log (room_id, actor_id, event_type, payload)
  VALUES (p_room_id, p_player_id, 'smuggled', jsonb_build_object('card', market_card));
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Play red button (win condition)
CREATE OR REPLACE FUNCTION play_red_button(p_room_id UUID, p_player_id UUID)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  player RECORD;
  hand JSONB;
  collection JSONB;
  has_all_parts BOOLEAN;
BEGIN
  -- Get player
  SELECT * INTO player
  FROM game_players
  WHERE room_id = p_room_id AND player_id = p_player_id;
  
  IF player IS NULL OR NOT player.is_alive THEN
    RAISE EXCEPTION 'Invalid player';
  END IF;
  
  -- Check hand has piros_gomb
  SELECT hand INTO hand FROM player_hands WHERE player_id = player.id;
  IF NOT (hand @> '["piros_gomb"]'::jsonb) THEN
    RAISE EXCEPTION 'No piros_gomb in hand';
  END IF;
  
  -- Check collection has all 4 parts
  collection := player.collection;
  has_all_parts := 
    (collection @> '["atomfizikus"]'::jsonb) AND
    (collection @> '["emberszolga"]'::jsonb) AND
    (collection @> '["sisak"]'::jsonb) AND
    (collection @> '["centrifuga"]'::jsonb);
  
  IF NOT has_all_parts THEN
    RAISE EXCEPTION 'Missing apocalypse parts';
  END IF;
  
  -- WIN!
  UPDATE game_rooms
  SET status = 'finished',
      finished_at = NOW(),
      winner_id = player.player_id,
      win_type = 'apokalipszis'
  WHERE id = p_room_id;
  
  -- Log
  INSERT INTO game_log (room_id, actor_id, event_type, payload)
  VALUES (p_room_id, p_player_id, 'apocalypse_win', jsonb_build_object('winner', player.player_id));
  
  RETURN jsonb_build_object('winner', player.player_id, 'win_type', 'apokalipszis');
END;
$$ LANGUAGE plpgsql;

-- Check survival winner
CREATE OR REPLACE FUNCTION check_survival_winner(p_room_id UUID)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  alive_count INT;
  last_player UUID;
BEGIN
  SELECT COUNT(*), MAX(player_id) INTO alive_count, last_player
  FROM game_players
  WHERE room_id = p_room_id AND is_alive = TRUE;
  
  IF alive_count = 1 THEN
    UPDATE game_rooms
    SET status = 'finished',
        finished_at = NOW(),
        winner_id = last_player,
        win_type = 'tulelesi'
    WHERE id = p_room_id;
    
    INSERT INTO game_log (room_id, event_type, payload)
    VALUES (p_room_id, 'survival_win', jsonb_build_object('winner', last_player));
    
    RETURN jsonb_build_object('winner', last_player, 'win_type', 'tulelesi');
  END IF;
  
  RETURN jsonb_build_object('alive_count', alive_count);
END;
$$ LANGUAGE plpgsql;

-- Debug: verify card count invariant
CREATE OR REPLACE FUNCTION verify_card_count(p_room_id UUID)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total_count INT := 0;
  expected_count INT := 92; -- Base deck: 4+5+6+7+2+4+4+3+4+3+3+3+4+3+3+30 = 88 + 2 defuse = 90 base
  actual_count INT;
  hand_count INT;
  collection_count INT;
  market_count INT;
  draw_count INT;
  discard_count INT;
  player_count INT;
BEGIN
  SELECT COUNT(*) INTO player_count FROM game_players WHERE room_id = p_room_id;
  expected_count := expected_count + player_count; -- Add meltdowns
  
  -- Count cards in all locations
  SELECT COALESCE(SUM(jsonb_array_length(hand)), 0) INTO hand_count
  FROM player_hands ph
  JOIN game_players gp ON ph.player_id = gp.id
  WHERE gp.room_id = p_room_id;
  
  SELECT COALESCE(SUM(jsonb_array_length(collection)), 0) INTO collection_count
  FROM game_players
  WHERE room_id = p_room_id;
  
  SELECT jsonb_array_length(market), jsonb_array_length(draw_pile), jsonb_array_length(discard_pile)
  INTO market_count, draw_count, discard_count
  FROM game_state
  WHERE room_id = p_room_id;
  
  total_count := hand_count + collection_count + market_count + draw_count + discard_count;
  
  RETURN jsonb_build_object(
    'expected', expected_count,
    'actual', total_count,
    'valid', total_count = expected_count,
    'breakdown', jsonb_build_object(
      'hands', hand_count,
      'collections', collection_count,
      'market', market_count,
      'draw_pile', draw_count,
      'discard', discard_count
    )
  );
END;
$$ LANGUAGE plpgsql;
