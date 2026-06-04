// Browser-side Web Push subscription helpers.

import { env } from "./env";
import { registerWebPushSubscription, unregisterWebPushSubscription } from "./backend";

// Base64URL → Uint8Array (required by PushManager.subscribe).
function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4);
  const padded = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(padded);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

export function isWebPushSupported(): boolean {
  return typeof window !== "undefined" && "serviceWorker" in navigator && "PushManager" in window;
}

export async function ensureServiceWorker(): Promise<ServiceWorkerRegistration> {
  if (!isWebPushSupported()) throw new Error("Web Push not supported in this browser");
  return navigator.serviceWorker.register("/sw.js");
}

export async function currentSubscription(): Promise<PushSubscription | null> {
  if (!isWebPushSupported()) return null;
  const reg = await navigator.serviceWorker.getRegistration();
  if (!reg) return null;
  return await reg.pushManager.getSubscription();
}

/** Asks for permission, subscribes, and registers the subscription with the backend. */
export async function subscribeAndRegister(): Promise<PushSubscription> {
  const reg = await ensureServiceWorker();

  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    throw new Error(`Notification permission ${permission}`);
  }

  // If a subscription already exists for this browser, reuse it.
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(env.vapidPublicKey),
    });
  }
  await registerWebPushSubscription(sub);
  return sub;
}

export async function unsubscribe(): Promise<void> {
  const sub = await currentSubscription();
  if (!sub) return;
  await unregisterWebPushSubscription(sub.endpoint);
  await sub.unsubscribe();
}
