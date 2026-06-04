// Small client for the duo-sync FastAPI backend.

import { env } from "./env";

const SESSION_KEY = "duo-sync.session_token";
const USER_KEY = "duo-sync.user";

export interface BackendUser {
  id: string;
  spotify_id: string;
  display_name: string | null;
  email: string | null;
  avatar_url: string | null;
  created_at: string;
}

export interface BackendSession {
  session_token: string;
  user: BackendUser;
}

// ---------- Session storage -------------------------------------------------

export function getSession(): { token: string; user: BackendUser } | null {
  if (typeof window === "undefined") return null;
  const token = localStorage.getItem(SESSION_KEY);
  const userJSON = localStorage.getItem(USER_KEY);
  if (!token || !userJSON) return null;
  return { token, user: JSON.parse(userJSON) };
}

export function storeSession(s: BackendSession) {
  localStorage.setItem(SESSION_KEY, s.session_token);
  localStorage.setItem(USER_KEY, JSON.stringify(s.user));
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
  localStorage.removeItem(USER_KEY);
}

// ---------- API calls -------------------------------------------------------

async function call<T>(path: string, init: RequestInit & { auth?: boolean } = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.auth) {
    const session = getSession();
    if (!session) throw new Error("Not signed in");
    headers.set("Authorization", `Bearer ${session.token}`);
  }
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const res = await fetch(`${env.backendURL}${path}`, { ...init, headers });
  if (res.status === 204) return undefined as T;
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Backend ${res.status}: ${text}`);
  }
  return (await res.json()) as T;
}

export async function signInWithSpotify(payload: {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  scope: string | null;
}): Promise<BackendSession> {
  const session = await call<BackendSession>("/auth/spotify", {
    method: "POST",
    body: JSON.stringify(payload),
  });
  storeSession(session);
  return session;
}

export async function fetchMe(): Promise<BackendUser> {
  return call<BackendUser>("/me", { auth: true });
}

export async function registerWebPushSubscription(sub: PushSubscription, userAgent?: string) {
  const json = sub.toJSON();
  if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) {
    throw new Error("Invalid PushSubscription");
  }
  await call("/me/web-push-subscription", {
    method: "POST",
    auth: true,
    body: JSON.stringify({
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth: json.keys.auth,
      user_agent: userAgent ?? navigator.userAgent,
    }),
  });
}

export async function unregisterWebPushSubscription(endpoint: string) {
  await call(`/me/web-push-subscription?endpoint=${encodeURIComponent(endpoint)}`, {
    method: "DELETE",
    auth: true,
  });
}
