# Ziren dashboard — Next.js, built to the standalone output (next.config.ts)
# so the runtime image ships only the server bundle and the node_modules it
# actually uses, not the full dependency tree.
#
# NEXT_PUBLIC_* values are inlined into the JS bundle at BUILD time, not read
# from the container's environment at runtime — that's a Next.js constraint,
# not a choice made here. They must be passed as build args. Railway passes a
# service's configured Variables as build args automatically; on another
# platform, pass them explicitly: docker build
#   --build-arg NEXT_PUBLIC_API_BASE_URL=https://your-backend-url \
#   --build-arg NEXT_PUBLIC_SUPABASE_URL=... \
#   --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=...

FROM node:20-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:20-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_API_BASE_URL
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
ENV NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

FROM node:20-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000
ENV PORT=3000
# Docker sets HOSTNAME to the container ID for every container, and Next's
# generated standalone server reads that same env var for its bind address —
# so without this override it listens on <container-id>:8080, unreachable
# from outside the container, instead of 0.0.0.0.
ENV HOSTNAME=0.0.0.0
CMD ["node", "server.js"]
