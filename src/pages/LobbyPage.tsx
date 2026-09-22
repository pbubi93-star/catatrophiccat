import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { supabase, startGame, getRoom, getPlayers, subscribeToRoom } from '../lib/supabase';
import type { GameRoom, GamePlayer } from '../types/game';

export default function LobbyPage() {
  const { roomId } = useParams<{ roomId: string }>();
  const navigate = useNavigate();
  const [room, setRoom] = useState<GameRoom | null>(null);
  const [players, setPlayers] = useState<GamePlayer[]>([]);
  const [isHost, setIsHost] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!roomId) return;

    const loadData = async () => {
      try {
        const [roomData, playersData] = await Promise.all([
          getRoom(roomId),
          getPlayers(roomId)
        ]);
        setRoom(roomData);
        setPlayers(playersData);
        
        // Check if current user is host
        const { data: { user } } = await supabase.auth.getUser();
        setIsHost(roomData.host_id === user?.id);
      } catch (err: any) {
        setError(err.message || 'Hiba történt a betöltéskor');
      }
    };

    loadData();

    // Subscribe to realtime updates
    const unsubscribe = subscribeToRoom(roomId, {
      onRoomChange: (updatedRoom) => {
        setRoom(updatedRoom);
        // If game started, redirect to game page
        if (updatedRoom.status === 'in_progress') {
          navigate(`/game/${roomId}`);
        }
      },
      onPlayersChange: async () => {
        const updatedPlayers = await getPlayers(roomId);
        setPlayers(updatedPlayers);
      }
    });

    return () => {
      unsubscribe();
    };
  }, [roomId, navigate]);

  const handleStartGame = async () => {
    if (!roomId || !isHost) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      await startGame(roomId);
      // Navigation happens via realtime subscription
    } catch (err: any) {
      setError(err.message || 'Hiba történt a játék indításakor');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopyCode = () => {
    if (room?.room_code) {
      navigator.clipboard.writeText(room.room_code);
    }
  };

  const playerCount = players.length;
  const canStart = isHost && playerCount >= 2 && playerCount <= 5 && room?.status === 'lobby';

  return (
    <div className="lobby-page">
      <div className="lobby-header">
        <button 
          className="btn-back"
          onClick={() => navigate('/')}
        >
          ← Kilépés
        </button>
        
        <div className="room-code-display">
          <span className="code-label">Szoba:</span>
          <span className="code-value">{room?.room_code || '...'}</span>
          <button className="btn-copy" onClick={handleCopyCode} title="Másolás">
            📋
          </button>
        </div>
      </div>

      <div className="lobby-content">
        {/* QR Code placeholder */}
        <div className="qr-section">
          <div className="qr-placeholder">
            <div className="qr-icon">📱</div>
            <p>Oszd meg a kóddal!</p>
          </div>
        </div>

        {/* Players list */}
        <div className="players-section">
          <h2>Játékosok ({playerCount}/5)</h2>
          <div className="players-list">
            {players.map((player, index) => (
              <div key={player.id} className="player-card">
                <span className="player-avatar">🐱</span>
                <span className="player-name">
                  {player.profile?.nickname || 'Játékos'}
                  {player.player_id === players.find(p => p.seat_order === 0)?.player_id && (
                    <span className="host-badge">👑 (host)</span>
                  )}
                </span>
              </div>
            ))}
            
            {/* Empty slots */}
            {Array.from({ length: 5 - playerCount }).map((_, index) => (
              <div key={`empty-${index}`} className="player-card empty">
                <span className="player-avatar">...</span>
                <span className="player-name">Vár további játékosra...</span>
              </div>
            ))}
          </div>
        </div>

        {/* Start button */}
        <div className="start-section">
          {isHost ? (
            <>
              <button
                className="btn btn-primary btn-large"
                onClick={handleStartGame}
                disabled={!canStart || isLoading}
              >
                {isLoading ? 'Indítás...' : 'JÁTÉK INDÍTÁSA'}
              </button>
              {!canStart && playerCount < 2 && (
                <p className="hint">Legalább 2 játékos szükséges</p>
              )}
            </>
          ) : (
            <p className="waiting-message">Várakozás a hostra...</p>
          )}
          
          {error && (
            <div className="error-message">
              {error}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
