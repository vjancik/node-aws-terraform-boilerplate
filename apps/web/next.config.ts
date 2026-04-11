import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactCompiler: true,
  output: "standalone",
  // Uncomment to add long-lived cache headers for static assets in public/
  // headers: async () => [
  //   {
  //     source: "/:all*(svg|jpg|png|ico|webp)",
  //     headers: [
  //       { key: "Cache-Control", value: "public, max-age=86400, stale-while-revalidate" },
  //     ],
  //   },
  // ],
};

export default nextConfig;
