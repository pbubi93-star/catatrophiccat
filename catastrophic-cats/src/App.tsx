import { useState } from 'react'
import HomePage from './components/HomePage'
import './index.css'

function App() {
  const [currentView, setCurrentView] = useState<'home' | 'lobby' | 'game'>('home');
  const [currentRoom, setCurrentRoom] = useState<string | null>(null);
  const [nickname, setNickname] = useState<string>('');

  const handleJoinRoom = (roomId: string, userNickname: string) => {
    setCurrentRoom(roomId);
    setNickname(userNickname);
    setCurrentView('lobby');
  };

  return (
    <div className="min-h-screen bg-slate-900">
      {currentView === 'home' && (
        <HomePage onJoinRoom={handleJoinRoom} />
      )}
      {currentView === 'lobby' && (
        <div className="min-h-screen flex items-center justify-center text-white">
          <div className="text-center">
            <h2 className="text-3xl font-display font-bold mb-4">Lobby - {currentRoom}</h2>
            <p className="text-xl mb-6">Üdvözöllek, {nickname}!</p>
            <p className="text-slate-400">A játék indítása hamarosan...</p>
          </div>
        </div>
      )}
      {currentView === 'game' && (
        <div className="min-h-screen flex items-center justify-center text-white">
          <div className="text-center">
            <h2 className="text-3xl font-display font-bold">Játék folyamatban</h2>
          </div>
        </div>
      )}
    </div>
  )
}

export default App
