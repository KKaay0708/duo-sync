/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Allow Spotify-hosted album art domains
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "i.scdn.co" },
      { protocol: "https", hostname: "mosaic.scdn.co" },
    ],
  },
};

module.exports = nextConfig;
