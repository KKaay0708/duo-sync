"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  type BackendUser,
  clearSession,
  fetchMe,
  getSession,
} from "@/lib/backend";
import {
  currentSubscription,
  isWebPushSupported,
  subscribeAndRegister,
  unsubscribe,
} from "@/lib/webPush";
import { supabase, type NowPlayingRow } from "@/lib/supabase";

export default function HomePage() {
  const router = useRouter();
  const [user, setUser] = useState<BackendUser | null>(null);
  const [snap, setSnap] = useState<NowPlayingRow | null>(null);
  const [pushOn, setPushOn] = useState(false);
  const [pushBusy, setPushBusy] = useState(false);
  const [pushError, setPushError] = useState<string | null>(null);

  // Gate: redirect to /login if not signed in.
  useEffect(() => {
    const session = getSession();
    if (!session) {
      router.replace("/login");
      return;
    }
    setUser(session.user);
    fetchMe().catch(() => {
      clearSession();
      router.replace("/login");
    });
  }, [router]);

  // Initial load + Realtime subscription for the current user's now-playing.
  useEffect(() => {
    if (!user) return;

    (async () => {
      const { data } = await supabase
        .from("now_playing_state")
        .select("*")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();
      if (data) setSnap(data as NowPlayingRow);
    })();

    const ch = supabase
      .channel(`now_playing:${user.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "now_playing_state",
          filter: `user_id=eq.${user.id}`,
        },
        (payload) => {
          const row = (payload.new ?? payload.old) as NowPlayingRow | null;
          if (row) setSnap(row);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(ch);
    };
  }, [user]);

  // Check push subscription on mount.
  useEffect(() => {
    if (!isWebPushSupported()) return;
    currentSubscription().then((s) => setPushOn(!!s));
  }, []);

  async function togglePush() {
    setPushBusy(true);
    setPushError(null);
    try {
      if (pushOn) {
        await unsubscribe();
        setPushOn(false);
      } else {
        await subscribeAndRegister();
        setPushOn(true);
      }
    } catch (e: unknown) {
      setPushError(e instanceof Error ? e.message : String(e));
    } finally {
      setPushBusy(false);
    }
  }

  function logout() {
    clearSession();
    router.replace("/login");
  }

  if (!user) {
    return null;
  }

  const playing = snap?.is_playing ?? false;
  const trackName = snap?.track_name ?? "Nothing playing";
  const artist = snap?.artist_name ?? "—";

  return (
    <main className="min-h-dvh px-5 py-6 flex flex-col gap-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">duo-sync</h1>
        <div className="flex items-center gap-3">
          {user.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={user.avatar_url} alt="" className="w-8 h-8 rounded-full" />
          ) : (
            <div className="w-8 h-8 rounded-full bg-white/15" />
          )}
          <span className="text-sm">{user.display_name ?? user.spotify_id}</span>
          <button onClick={logout} className="text-sm text-white/60 underline">
            Log out
          </button>
        </div>
      </header>

      <section className="rounded-3xl bg-white/5 p-5 flex gap-4 items-center">
        {snap?.album_art_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={snap.album_art_url}
            alt=""
            className="w-24 h-24 rounded-xl object-cover"
          />
        ) : (
          <div className="w-24 h-24 rounded-xl bg-white/10 flex items-center justify-center text-3xl">
            ♫
          </div>
        )}
        <div className="flex flex-col min-w-0 gap-1">
          <span
            className={
              "text-xs font-bold tracking-wider " +
              (playing ? "text-spotify" : "text-white/50")
            }
          >
            {playing ? "NOW PLAYING" : "PAUSED"}
          </span>
          <span className="text-lg font-semibold truncate">{trackName}</span>
          <span className="text-sm text-white/70 truncate">{artist}</span>
        </div>
      </section>

      <section className="rounded-3xl bg-white/5 p-5 flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-semibold">Lock-screen notifications</p>
            <p className="text-xs text-white/60">
              {pushOn ? "On — you’ll get a buzz on every song change." : "Off"}
            </p>
          </div>
          <button
            onClick={togglePush}
            disabled={pushBusy || !isWebPushSupported()}
            className={
              "rounded-full px-4 py-2 text-sm font-semibold " +
              (pushOn ? "bg-white/15 text-white" : "bg-spotify text-white") +
              " disabled:opacity-50"
            }
          >
            {pushBusy ? "…" : pushOn ? "Disable" : "Enable"}
          </button>
        </div>
        {!isWebPushSupported() && (
          <p className="text-xs text-amber-400">
            This browser doesn’t support Web Push. On iPhone, open this site in Safari and
            tap Share → Add to Home Screen, then come back here.
          </p>
        )}
        {pushError && <p className="text-xs text-red-400">{pushError}</p>}
      </section>
    </main>
  );
}
