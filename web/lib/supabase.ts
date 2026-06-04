import { createClient } from "@supabase/supabase-js";
import { env } from "./env";

export const supabase = createClient(env.supabaseURL, env.supabaseAnonKey, {
  auth: { persistSession: false },
});

export interface NowPlayingRow {
  user_id: string;
  track_id: string | null;
  track_name: string | null;
  artist_name: string | null;
  album_name: string | null;
  album_art_url: string | null;
  is_playing: boolean;
  progress_ms: number | null;
  duration_ms: number | null;
  polled_at: string;
  change_seq: number;
}
