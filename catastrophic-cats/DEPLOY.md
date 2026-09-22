# Catastrophic Cats - Deployment Guide

## Prerequisites

1. Node.js 18+ installed
2. Supabase account and project created
3. Cloudflare account (optional, for Pages deployment)

## Local Development Setup

### 1. Install Dependencies

```bash
npm install
```

### 2. Set Up Environment Variables

Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Edit `.env` and add your Supabase credentials:
- `VITE_SUPABASE_URL`: Your Supabase project URL (found in Settings > API)
- `VITE_SUPABASE_ANON_KEY`: Your Supabase anon/public key (found in Settings > API)

### 3. Link to Supabase Project

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

### 4. Apply Database Migrations

```bash
npx supabase db push
```

This will create all tables, RLS policies, and RPC functions in your Supabase project.

### 5. Start Development Server

```bash
npm run dev
```

The app will be available at `http://localhost:5173`

## Production Deployment

### Option A: Cloudflare Pages

1. **Build the project:**
   ```bash
   npm run build
   ```

2. **Deploy to Cloudflare Pages:**
   ```bash
   npx wrangler pages deploy dist --project-name catastrophic-cats
   ```

3. **Set Environment Variables in Cloudflare Dashboard:**
   - Go to Workers & Pages > catastrophic-cats > Settings > Environment Variables
   - Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`

### Option B: Other Static Hosts

The `dist` folder contains the built static files that can be deployed to any static hosting service (Netlify, Vercel, GitHub Pages, etc.).

## Database Schema Overview

The migration creates the following structure:

- **profiles**: User profiles linked to Supabase Auth
- **game_rooms**: Game room metadata and status
- **game_players**: Player data (hand is protected by RLS)
- **game_state**: Current game state (draw pile is server-only)
- **game_log**: Event log for UI display

Key security features:
- Row Level Security (RLS) prevents players from seeing others' hands
- All game logic functions use `SECURITY DEFINER` to run with elevated privileges
- Public views expose only safe-to-share data

## Troubleshooting

### "Missing environment variables" error
Make sure your `.env` file exists and contains valid Supabase credentials.

### "Room not found" error
Verify that the room code is correct and the game hasn't already started.

### Database migration fails
Ensure you're logged in to Supabase CLI and linked to the correct project.

## Next Steps

After deployment:
1. Test creating a room with one browser
2. Join the room from another browser/device using the 6-character code
3. Verify real-time synchronization works
4. Test the full game flow
