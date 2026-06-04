"use client";

import { useState } from "react";
import { beginLogin } from "@/lib/spotifyAuth";

export default function LoginPage() {
  const [busy, setBusy] = useState(false);

  async function go() {
    setBusy(true);
    const url = await beginLogin();
    window.location.assign(url);
  }

  return (
    <main className="min-h-dvh flex flex-col items-center justify-between p-8">
      <div />
      <div className="flex flex-col items-center gap-10">
        <h1 className="text-5xl font-bold tracking-tight">duo-sync</h1>
        <div className="w-44 h-44 rounded-full border-4 border-white flex items-center justify-center">
          <span className="text-7xl">♫</span>
        </div>
      </div>
      <button
        onClick={go}
        disabled={busy}
        className="w-full max-w-xs rounded-full bg-spotify text-white py-4 font-semibold text-lg disabled:opacity-50"
      >
        {busy ? "Connecting…" : "Log in with Spotify"}
      </button>
    </main>
  );
}
