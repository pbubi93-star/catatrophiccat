import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Supabase credentials not found. Make sure VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are set.');
}

export const supabase = createClient(
  supabaseUrl || 'https://placeholder.supabase.co',
  supabaseAnonKey || 'placeholder-key'
);

// Auth helpers
export async function signInAnonymously() {
  const result = await supabase.auth.signInAnonymously();
  if (result.error) throw result.error;
  return result.data;
}

export async function signOut() {
  const result = await supabase.auth.signOut();
  if (result.error) throw result.error;
}

export function getCurrentUser() {
  return supabase.auth.getUser();
}

// Room RPC calls
export async function createRoom(nickname: string) {
  const { data, error } = await supabase.rpc('create_room', { nickname });
  if (error) throw error;
  return data;
}

export async function joinRoom(roomCode: string, nickname: string) {
  const { data, error } = await supabase.rpc('join_room', { room_code: roomCode, nickname });
  if (error) throw error;
  return data;
}

export async function startGame(roomId: string) {
  const { data, error } = await supabase.rpc('start_game', { room_id: roomId });
  if (error) throw error;
  return data;
}

// Game action RPCs
export async function drawFromPile(roomId: string, playerId: string) {
  const { data, error } = await supabase.rpc('draw_from_pile', { 
    room_id: roomId, 
    player_id: playerId 
  });
  if (error) throw error;
  return data as { card: string; is_meghibasodas: boolean; survived: boolean; player_eliminated?: boolean };
}

export async function takeFromMarket(roomId: string, playerId: string, cardIndex: number) {
  const { data, error } = await supabase.rpc('take_from_market', { 
    room_id: roomId, 
    player_id: playerId,
    card_index: cardIndex
  });
  if (error) throw error;
  return data as { card: string; is_meghibasodas: boolean; survived: boolean; player_eliminated?: boolean };
}

export async function playActionCard(
  roomId: string, 
  playerId: string, 
  card: string, 
  targetPlayerId?: string,
  extraPayload?: Record<string, unknown>
) {
  const { data, error } = await supabase.rpc('play_action_card', { 
    room_id: roomId, 
    player_id: playerId,
    card,
    target_player_id: targetPlayerId,
    extra_payload: extraPayload
  });
  if (error) throw error;
  return data;
}

export async function playSmugglingAnytime(roomId: string, playerId: string, cardIndex: number) {
  const { data, error } = await supabase.rpc('play_smuggling_anytime', { 
    room_id: roomId, 
    player_id: playerId,
    card_index: cardIndex
  });
  if (error) throw error;
  return data as { card: string; is_meghibasodas: boolean; survived: boolean; player_eliminated?: boolean };
}

export async function playRedButton(roomId: string, playerId: string) {
  const { data, error } = await supabase.rpc('play_red_button', { 
    room_id: roomId, 
    player_id: playerId
  });
  if (error) throw error;
  return data;
}

export async function checkSurvivalWinner(roomId: string) {
  const { data, error } = await supabase.rpc('check_survival_winner', { 
    room_id: roomId
  });
  if (error) throw error;
  return data;
}

// Data fetching
export async function getRoom(roomId: string) {
  const { data, error } = await supabase
    .from('game_rooms')
    .select('*')
    .eq('id', roomId)
    .single();
  if (error) throw error;
  return data;
}

export async function getPlayers(roomId: string) {
  const { data, error } = await supabase
    .from('game_players')
    .select(`
      *,
      profile:profiles(id, nickname)
    `)
    .eq('room_id', roomId)
    .order('seat_order');
  if (error) throw error;
  return data;
}

export async function getGameState(roomId: string) {
  const { data, error } = await supabase
    .from('game_state')
    .select('room_id, market, discard_pile, current_turn_seat, turn_number, updated_at')
    .eq('room_id', roomId)
    .single();
  if (error) throw error;
  return data;
}

export async function getMyHand(roomId: string, playerId: string) {
  // This uses RLS - only the owner can see their own hand
  const { data, error } = await supabase
    .from('game_players')
    .select('hand')
    .eq('room_id', roomId)
    .eq('player_id', playerId)
    .single();
  if (error) throw error;
  return data?.hand || [];
}

export async function getGameLog(roomId: string, limit = 20) {
  const { data, error } = await supabase
    .from('game_log')
    .select('*')
    .eq('room_id', roomId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}

// Realtime subscriptions
export function subscribeToRoom(roomId: string, callbacks: {
  onRoomChange?: (room: any) => void;
  onPlayersChange?: (players: any[]) => void;
  onGameStateChange?: (state: any) => void;
  onLogChange?: (log: any) => void;
}) {
  const channel = supabase.channel(`room:${roomId}`);
  
  if (callbacks.onRoomChange) {
    channel.on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'game_rooms', filter: `room_id=eq.${roomId}` },
      (payload) => callbacks.onRoomChange?.(payload.new)
    );
  }
  
  if (callbacks.onPlayersChange) {
    channel.on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'game_players', filter: `room_id=eq.${roomId}` },
      (payload) => callbacks.onPlayersChange?.([payload.new])
    );
  }
  
  if (callbacks.onGameStateChange) {
    channel.on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'game_state', filter: `room_id=eq.${roomId}` },
      (payload) => callbacks.onGameStateChange?.(payload.new)
    );
  }
  
  if (callbacks.onLogChange) {
    channel.on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'game_log', filter: `room_id=eq.${roomId}` },
      (payload) => callbacks.onLogChange?.(payload.new)
    );
  }
  
  channel.subscribe();
  
  return () => {
    supabase.removeChannel(channel);
  };
}
