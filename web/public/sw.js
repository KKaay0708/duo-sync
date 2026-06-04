// duo-sync — Service Worker
//
// Receives Web Push events from the backend whenever a watched user's
// Spotify song changes. Shows a notification on the device's lock
// screen even when the PWA isn't open.
//
// On iOS this requires the user to have installed the PWA via
// Safari → Share → Add to Home Screen, on iOS 16.4 or later.

self.addEventListener("install", (event) => {
  // Activate as soon as possible so first push works.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  let data = {};
  try {
    if (event.data) {
      data = event.data.json();
    }
  } catch (e) {
    data = { title: "duo-sync", body: event.data ? event.data.text() : "" };
  }

  const title = data.title || "duo-sync";
  const body = data.body || "";
  const icon = data.icon || "/icon-192.png";
  const tag = data.data && data.data.user_id ? `now_playing:${data.data.user_id}` : "now_playing";
  const url = (data.data && data.data.url) || "/";

  const options = {
    body,
    icon,
    badge: "/icon-192.png",
    // Same tag for a given user collapses notifications — the latest
    // song replaces the previous notification rather than stacking.
    tag,
    renotify: true,
    data: { url, ...data.data },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if ("focus" in client) return client.focus();
        }
        if (self.clients.openWindow) return self.clients.openWindow(url);
      })
  );
});
