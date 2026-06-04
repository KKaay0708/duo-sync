// Spotify PKCE OAuth helpers — mirrors what the iOS app does, but in the browser.
// We use the Authorization Code with PKCE flow (no client secret needed).

import { env } from "./env";

const SCOPES = [
  "user-read-private",
  "user-read-email",
  "user-read-currently-playing",
  "user-read-playback-state",
  "user-read-recently-played",
  "user-top-read",
  "playlist-read-private",
  "playlist-modify-private",
  "playlist-modify-public",
];

const VERIFIER_KEY = "duo-sync.pkce.verifier";
const STATE_KEY = "duo-sync.pkce.state";

// ---------- PKCE helpers ----------------------------------------------------

function base64UrlEncode(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function generateCodeVerifier(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(64));
  return base64UrlEncode(bytes.buffer);
}

async function codeChallengeFromVerifier(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return base64UrlEncode(hash);
}

// ---------- Public API ------------------------------------------------------

/** Builds the /authorize URL and stashes the verifier in sessionStorage. */
export async function beginLogin(): Promise<string> {
  const verifier = generateCodeVerifier();
  const challenge = await codeChallengeFromVerifier(verifier);
  const state = crypto.randomUUID();

  sessionStorage.setItem(VERIFIER_KEY, verifier);
  sessionStorage.setItem(STATE_KEY, state);

  const params = new URLSearchParams({
    response_type: "code",
    client_id: env.spotifyClientID,
    scope: SCOPES.join(" "),
    redirect_uri: env.spotifyRedirectURI,
    code_challenge_method: "S256",
    code_challenge: challenge,
    state,
  });
  return `https://accounts.spotify.com/authorize?${params.toString()}`;
}

export interface SpotifyTokens {
  access_token: string;
  refresh_token: string;
  scope: string;
  expires_in: number;
  token_type: string;
}

/** Exchanges the code at /api/token. Called from the callback page. */
export async function exchangeCode(code: string, returnedState: string): Promise<SpotifyTokens> {
  const verifier = sessionStorage.getItem(VERIFIER_KEY);
  const stateSent = sessionStorage.getItem(STATE_KEY);
  sessionStorage.removeItem(VERIFIER_KEY);
  sessionStorage.removeItem(STATE_KEY);

  if (!verifier) throw new Error("Missing PKCE verifier");
  if (!stateSent || stateSent !== returnedState) throw new Error("State mismatch");

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: env.spotifyRedirectURI,
    client_id: env.spotifyClientID,
    code_verifier: verifier,
  });

  const res = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Spotify token exchange failed: ${res.status} ${text}`);
  }
  return (await res.json()) as SpotifyTokens;
}
