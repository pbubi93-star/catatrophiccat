import { useState } from 'react';
import { supabase } from '../lib/supabaseClient';

interface HomePageProps {
  onJoinRoom: (roomId: string, nickname: string) => void;
}

export default function HomePage({ onJoinRoom }: HomePageProps) {
  const [nickname, setNickname] = useState('');
  const [roomCode, setRoomCode] = useState(['', '', '', '', '', '']);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleCreateRoom = async () => {
    if (!nickname.trim()) return;
    
    setLoading(true);
    setError(null);
    
    try {
      // Anonymous sign in
      const { data: authData, error: authError } = await supabase.auth.signInAnonymously();
      if (authError) throw authError;
      
      // Create profile
      const { error: profileError } = await supabase.rpc('create_room', {
        nickname: nickname.trim()
      });
      
      if (profileError) throw profileError;
      
      // In a real implementation, we'd get the room details back
      // For now, just notify parent
      onJoinRoom('new-room', nickname.trim());
    } catch (err: any) {
      setError(err.message || 'Hiba történt a szoba létrehozásakor');
    } finally {
      setLoading(false);
    }
  };

  const handleJoinRoom = async () => {
    const code = roomCode.join('').toUpperCase();
    if (!nickname.trim() || code.length !== 6) return;
    
    setLoading(true);
    setError(null);
    
    try {
      // Anonymous sign in
      const { data: authData, error: authError } = await supabase.auth.signInAnonymously();
      if (authError) throw authError;
      
      // Join room
      const { error: joinError } = await supabase.rpc('join_room', {
        room_code: code,
        nickname: nickname.trim()
      });
      
      if (joinError) throw joinError;
      
      onJoinRoom(code, nickname.trim());
    } catch (err: any) {
      setError(err.message || 'Hiba történt a csatlakozáskor');
    } finally {
      setLoading(false);
    }
  };

  const handleRoomCodeChange = (index: number, value: string) => {
    if (value.length > 1) value = value.charAt(0);
    value = value.toUpperCase();
    
    const newCode = [...roomCode];
    newCode[index] = value;
    setRoomCode(newCode);
    
    // Auto-focus next input
    if (value && index < 5) {
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
  const roomCodeString = roomCode.join('').toUpperCase();

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      <div className="max-w-md w-full">
        {/* Logo and Title */}
        <div className="text-center mb-8">
          <h1 className="text-5xl font-display font-bold text-white mb-2">
            🐱☢️
          </h1>
          <h2 className="text-3xl font-display font-bold text-radioactive-green mb-2">
            CATASTROPHIC CATS
          </h2>
          <p className="text-slate-400 text-lg">
            "Idézd elő a macska-apokalipszist!"
          </p>
        </div>

        {/* Nickname Input */}
        <div className="mb-6">
          <label htmlFor="nickname" className="block text-sm font-medium text-slate-300 mb-2">
            Beceneved:
          </label>
          <input
            type="text"
            id="nickname"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            placeholder="Pl. MacskaMester"
            className="w-full px-4 py-3 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-radioactive-green focus:border-transparent transition-all"
            disabled={loading}
          />
        </div>

        {/* Create Room Button */}
        <button
          onClick={handleCreateRoom}
          disabled={!isFormValid || loading}
          className={`w-full py-4 px-6 rounded-lg font-display font-bold text-lg mb-6 transition-all ${
            isFormValid && !loading
              ? 'bg-radioactive-green hover:bg-green-400 text-slate-900 shadow-lg hover:shadow-radioactive-green/30 transform hover:-translate-y-1'
              : 'bg-slate-700 text-slate-500 cursor-not-allowed'
          }`}
        >
          {loading ? 'Létrehozás...' : 'SZOBA LÉTREHOZÁSA'}
        </button>

        {/* Divider */}
        <div className="relative mb-6">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-slate-700"></div>
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="px-4 bg-slate-900 text-slate-400">vagy</span>
          </div>
        </div>

        {/* Room Code Input */}
        <div className="mb-6">
          <label className="block text-sm font-medium text-slate-300 mb-3">
            Szoba-kód megadása:
          </label>
          <div className="flex justify-center gap-2 mb-4">
            {roomCode.map((digit, index) => (
              <input
                key={index}
                id={`room-code-${index}`}
                type="text"
                maxLength={1}
                value={digit}
                onChange={(e) => handleRoomCodeChange(index, e.target.value)}
                onKeyDown={(e) => handleKeyDown(index, e)}
                className="w-12 h-14 text-center text-2xl font-bold bg-slate-800 border border-slate-700 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-radioactive-green focus:border-transparent transition-all"
                disabled={loading}
              />
            ))}
          </div>
        </div>

        {/* Join Room Button */}
        <button
          onClick={handleJoinRoom}
          disabled={!isFormValid || roomCodeString.length !== 6 || loading}
          className={`w-full py-4 px-6 rounded-lg font-display font-bold text-lg transition-all ${
            isFormValid && roomCodeString.length === 6 && !loading
              ? 'bg-warning-yellow hover:bg-yellow-300 text-slate-900 shadow-lg hover:shadow-warning-yellow/30 transform hover:-translate-y-1'
              : 'bg-slate-700 text-slate-500 cursor-not-allowed'
          }`}
        >
          {loading ? 'Csatlakozás...' : 'CSATLAKOZÁS'}
        </button>

        {/* Error Message */}
        {error && (
          <div className="mt-6 p-4 bg-red-900/30 border border-red-500 rounded-lg text-red-300 text-center">
            {error}
          </div>
        )}

        {/* Instructions */}
        <div className="mt-8 text-center text-slate-500 text-sm">
          <p>Hozz létre egy új szobát, vagy csatlakozz egy meglévőhöz 6 karakteres kóddal.</p>
        </div>
      </div>
    </div>
  );
}
