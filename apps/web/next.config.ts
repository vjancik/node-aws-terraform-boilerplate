import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@repo/db"],
  reactCompiler: true,
  output: "standalone",
  outputFileTracingRoot: path.join(import.meta.dirname, "../../"),
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
