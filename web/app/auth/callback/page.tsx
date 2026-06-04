"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { exchangeCode } from "@/lib/spotifyAuth";
import { signInWithSpotify } from "@/lib/backend";

export default function CallbackPage() {
  const router = useRouter();
  const params = useSearchParams();
  const [status, setStatus] = useState("Finishing sign-in…");

  useEffect(() => {
    const code = params.get("code");
    const state = params.get("state");
    const errParam = params.get("error");
    if (errParam) {
      setStatus(`Spotify error: ${errParam}`);
      return;
    }
    if (!code || !state) {
      setStatus("Missing code or state in callback URL.");
      return;
    }
    (async () => {
      try {
        const tokens = await exchangeCode(code, state);
        await signInWithSpotify({
          access_token: tokens.access_token,
          refresh_token: tokens.refresh_token,
          expires_in: tokens.expires_in,
          scope: tokens.scope ?? null,
        });
        router.replace("/");
      } catch (e: unknown) {
        setStatus(e instanceof Error ? e.message : String(e));
      }
    })();
  }, [params, router]);

  return (
    <main className="min-h-dvh flex items-center justify-center p-8">
      <p className="text-white/80">{status}</p>
    </main>
  );
}
