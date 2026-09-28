import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cloud deploy (Docker): bundles the server into .next/standalone with only
  // the node_modules it actually uses, so the runtime image doesn't need the
  // full node_modules tree. Has no effect on `next dev`/`next start` outside
  // Docker, so local workflows are unchanged.
  output: 'standalone',
  // A production build can be made and started in its own folder
  // (NEXT_DIST_DIR=.next-prod) without touching the .next that `next dev` is
  // serving from. Building over a running dev server's .next is what makes it
  // start returning 500 on every route - see the ziren-dev skill.
  distDir: process.env.NEXT_DIST_DIR || '.next',
  // /api/* is proxied to the backend by app/api/[...path]/route.ts, not by
  // a rewrites() rule — see that file for why: Next's rewrite catch-all
  // segment silently drops a trailing slash, which broke every incident
  // submission (POST /incidents/) through this proxy. A route handler
  // preserves the path exactly as the client sent it.
  //
  // skipTrailingSlashRedirect still has to be set even with a route handler
  // instead of rewrites: Next's own router 308-redirects any trailing-slash
  // URL to the no-slash version at the routing layer, before dispatching to
  // ANY handler — this flag is what's needed to stop that, independent of
  // rewrites being involved at all.
  skipTrailingSlashRedirect: true,
};

export default nextConfig;
