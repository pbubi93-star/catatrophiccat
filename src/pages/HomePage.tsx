import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { signInAnonymously, createRoom, joinRoom } from '../lib/supabase';

export default function HomePage() {
  const [nickname, setNickname] = useState('');
  const [roomCode, setRoomCode] = useState(['', '', '', '', '', '']);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    // Ensure user is authenticated
    const initAuth = async () => {
      try {
        await signInAnonymously();
      } catch (err) {
        console.error('Auth error:', err);
        setError('Nem sikerült csatlakozni. Kérlek frissítsd az oldalt.');
      }
    };
    initAuth();
  }, []);

  const handleCreateRoom = async () => {
    if (!nickname.trim()) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      const roomId = await createRoom(nickname.trim());
      navigate(`/lobby/${roomId}`);
    } catch (err: any) {
      setError(err.message || 'Hiba történt a szoba létrehozásakor');
    } finally {
      setIsLoading(false);
    }
  };

  const handleJoinRoom = async () => {
    const code = roomCode.join('').toUpperCase();
    if (!nickname.trim() || code.length !== 6) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      const roomId = await joinRoom(code, nickname.trim());
      navigate(`/lobby/${roomId}`);
    } catch (err: any) {
      setError(err.message || 'Hiba történt a csatlakozáskor');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRoomCodeChange = (index: number, value: string) => {
    const newValue = value.toUpperCase().slice(0, 1);
    const newCode = [...roomCode];
    newCode[index] = newValue;
    setRoomCode(newCode);
    
    // Auto-focus next input
    if (newValue && index < 5) {
      const nextInput = document.getElementById(`room-code-${index + 1}`);
      nextInput?.focus();
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !roomCode[index] && index > 0) {
      const prevInput = document.getElementById(`room-code-${index - 1}`);
      prevInput?.focus();
    }
  };

  const isFormValid = nickname.trim().length > 0;
  const isRoomCodeComplete = roomCode.every(c => c.length === 1);

  return (
    <div className="home-page">
      <div className="home-content">
        <div className="logo-section">
          <h1 className="game-title">🐱☢️ CATASTROPHIC CATS</h1>
          <p className="game-subtitle">"Idézd elő a macska-apokalipszist."</p>
        </div>

        <div className="form-section">
          <div className="input-group">
            <label htmlFor="nickname">Beceneved:</label>
            <input
              id="nickname"
              type="text"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              placeholder="Add meg a neved..."
              maxLength={20}
              disabled={isLoading}
            />
          </div>

          <button
            className="btn btn-primary btn-large"
            onClick={handleCreateRoom}
            disabled={!isFormValid || isLoading}
          >
            {isLoading ? 'Létrehozás...' : 'SZOBA LÉTREHOZÁSA'}
          </button>

          <div className="divider">
            <span>vagy</span>
          </div>

          <div className="input-group">
            <label>Szoba-kód:</label>
            <div className="room-code-inputs">
              {roomCode.map((char, index) => (
                <input
                  key={index}
                  id={`room-code-${index}`}
                  type="text"
                  value={char}
                  onChange={(e) => handleRoomCodeChange(index, e.target.value)}
                  onKeyDown={(e) => handleKeyDown(index, e)}
                  maxLength={1}
                  disabled={isLoading}
                  className="room-code-char"
                />
              ))}
            </div>
          </div>

          <button
            className="btn btn-secondary btn-large"
            onClick={handleJoinRoom}
            disabled={!isFormValid || !isRoomCodeComplete || isLoading}
          >
            {isLoading ? 'Csatlakozás...' : 'CSATLAKOZÁS'}
          </button>

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
