// Centralized access to NEXT_PUBLIC_* env vars so missing values fail loudly.

function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export const env = {
  backendURL: required("NEXT_PUBLIC_BACKEND_URL", process.env.NEXT_PUBLIC_BACKEND_URL),
  supabaseURL: required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL),
  supabaseAnonKey: required("NEXT_PUBLIC_SUPABASE_ANON_KEY", process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
  spotifyClientID: required("NEXT_PUBLIC_SPOTIFY_CLIENT_ID", process.env.NEXT_PUBLIC_SPOTIFY_CLIENT_ID),
  spotifyRedirectURI: required(
    "NEXT_PUBLIC_SPOTIFY_REDIRECT_URI",
    process.env.NEXT_PUBLIC_SPOTIFY_REDIRECT_URI
  ),
  vapidPublicKey: required("NEXT_PUBLIC_VAPID_PUBLIC_KEY", process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY),
};
