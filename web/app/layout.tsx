import "./globals.css";
import type { Metadata, Viewport } from "next";

export const metadata: Metadata = {
  title: "duo-sync",
  description: "See what your partner is listening to in real time.",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "duo-sync",
  },
};

export const viewport: Viewport = {
  themeColor: "#1DB954",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-dvh bg-black text-white font-sans">{children}</body>
    </html>
  );
}
