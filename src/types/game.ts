// Card types - union types for strict type safety
export type CardCategory = 'alkatresz' | 'zaro' | 'akcio' | 'elony' | 'hatraltato' | 'piaci_toltolap' | 'meghibasodas' | 'veszleallitas';

export type CardId = 
  // Alkatrész (Apocalypse parts)
  | 'atomfizikus'
  | 'emberszolga'
  | 'sisak'
  | 'centrifuga'
  // Záró kártya
  | 'piros_gomb'
  // Akció
  | 'csempeszjarat'
  | 'terepszemle'
  | 'csere_bere'
  // Előny
  | 'second_breakfast'
  | 'dorombolas'
  | 'kilenc_elet'
  | 'cicanip'
  // Hátráltató
  | 'gombolyag'
  | 'kohoges'
  | 'lomha'
  // Piaci töltőlap
  | 'toltolap'
  // Special cards (not in main deck)
  | 'meghibasodas'
  | 'veszleallitas';

export interface Card {
  id: CardId;
  category: CardCategory;
  name: string;
  count: number; // How many in the deck
}

// All card definitions with counts from the spec
export const CARD_DEFINITIONS: Record<CardId, Card> = {
  // Alkatrész - Apocalypse parts
  atomfizikus: { id: 'atomfizikus', category: 'alkatresz', name: 'Atomfizikus', count: 4 },
  emberszolga: { id: 'emberszolga', category: 'alkatresz', name: 'Emberszolga', count: 5 },
  sisak: { id: 'sisak', category: 'alkatresz', name: 'Sisak', count: 6 },
  centrifuga: { id: 'centrifuga', category: 'alkatresz', name: 'Centrifuga', count: 7 },
  
  // Záró kártya
  piros_gomb: { id: 'piros_gomb', category: 'zaro', name: 'Véletlenül a Piros Gombra Feküdtem', count: 2 },
  
  // Akció
  csempeszjarat: { id: 'csempeszjarat', category: 'akcio', name: 'Csempészjárat', count: 4 },
  terepszemle: { id: 'terepszemle', category: 'akcio', name: 'Terepszemle', count: 4 },
  csere_bere: { id: 'csere_bere', category: 'akcio', name: 'Csere-Bere', count: 3 },
  
  // Előny
  second_breakfast: { id: 'second_breakfast', category: 'elony', name: 'Second Breakfast', count: 4 },
  dorombolas: { id: 'dorombolas', category: 'elony', name: 'Dorombolás', count: 3 },
  kilenc_elet: { id: 'kilenc_elet', category: 'elony', name: 'Kilenc Élet', count: 3 },
  cicanip: { id: 'cicanip', category: 'elony', name: 'Cicanip', count: 3 },
  
  // Hátráltató
  gombolyag: { id: 'gombolyag', category: 'hatraltato', name: 'Gombolyag-csapda', count: 4 },
  kohoges: { id: 'kohoges', category: 'hatraltato', name: 'Macskaköhögés', count: 3 },
  lomha: { id: 'lomha', category: 'hatraltato', name: 'Lomha Macska', count: 3 },
  
  // Piaci töltőlap
  toltolap: { id: 'toltolap', category: 'piaci_toltolap', name: 'Piaci Töltőlap', count: 30 },
  
  // Special cards (added after initial deal)
  meghibasodas: { id: 'meghibasodas', category: 'meghibasodas', name: 'Nukleáris Meghibásodás', count: 0 }, // Count = player count
  veszleallitas: { id: 'veszleallitas', category: 'veszleallitas', name: 'Vészleállítás', count: 2 },
};

export const APOCALYPSE_PARTS: CardId[] = ['atomfizikus', 'emberszolga', 'sisak', 'centrifuga'];

export type GameStatus = 'lobby' | 'in_progress' | 'finished';
export type WinType = 'apokalipszis' | 'tulelesi';

export interface Profile {
  id: string;
  nickname: string;
  created_at: string;
}

export interface GameRoom {
  id: string;
  room_code: string;
  status: GameStatus;
  host_id: string;
  min_players: number;
  max_players: number;
  created_at: string;
  started_at?: string;
  finished_at?: string;
  winner_id?: string;
  win_type?: WinType;
}

export interface GamePlayer {
  id: string;
  room_id: string;
  player_id: string;
  seat_order: number;
  is_alive: boolean;
  hand: CardId[]; // Hidden - only visible to owner via RLS
  collection: CardId[]; // Public collection
  skip_next: boolean;
  protected: boolean; // dorombolás protection
  nine_lives_active: boolean;
  profile?: Profile;
}

export interface GameState {
  room_id: string;
  draw_pile: CardId[]; // Hidden - only server RPC can access
  market: CardId[]; // Public market (4 cards)
  discard_pile: CardId[]; // Public discard pile
  current_turn_seat: number;
  turn_number: number;
  updated_at: string;
}

export interface GameLog {
  id: number;
  room_id: string;
  turn_number: number;
  actor_id: string;
  event_type: string;
  payload: Record<string, unknown>;
  created_at: string;
}

// Action card types
export type ActionType = 'draw' | 'take_market' | 'play_card' | 'smuggle' | 'red_button';

export interface PlayCardPayload {
  card: CardId;
  target_player_id?: string;
  extra_payload?: Record<string, unknown>;
}

export interface DrawResult {
  card: CardId;
  is_meghibasodas: boolean;
  survived: boolean;
  player_eliminated?: boolean;
}
