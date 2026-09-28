/**
 * Hand-rolled proxy to the backend, replacing next.config.ts's `rewrites()`.
 *
 * Why not rewrites(): Next's `/:path*` catch-all segment does not capture a
 * trailing slash, even with `skipTrailingSlashRedirect: true` set. So
 * `/api/incidents/` was being forwarded to the backend as `/incidents`
 * (slash dropped) — and the backend's route IS registered with a trailing
 * slash, so FastAPI/Starlette's own redirect_slashes then 307-redirected
 * back to `/incidents/`, as an ABSOLUTE `http://localhost:8000/...` URL
 * (the backend's own loopback address, meaningless to a phone or any
 * client outside this machine). That silently broke every incident
 * submission through the tunnel — confirmed 2026-09-14 during real device
 * testing, after the dashboard side of this exact class of bug (see the
 * .env.local NEXT_PUBLIC_API_BASE_URL history) had already been fixed once.
 *
 * A route handler sidesteps the whole problem: `params.path` is the exact
 * segment array Next parsed from the URL, and reconstructing the backend
 * URL from `request.nextUrl` (pathname + search) preserves the trailing
 * slash exactly as the client sent it, so the backend never has a reason
 * to redirect at all.
 */
import { NextRequest, NextResponse } from 'next/server';

const BACKEND_ORIGIN = 'http://localhost:8000';

async function proxy(request: NextRequest) {
  const backendPath = request.nextUrl.pathname.replace(/^\/api/, '');
  const url = `${BACKEND_ORIGIN}${backendPath}${request.nextUrl.search}`;

  const headers = new Headers(request.headers);
  headers.delete('host');

  const hasBody = !['GET', 'HEAD'].includes(request.method);

  const response = await fetch(url, {
    method: request.method,
    headers,
    body: hasBody ? await request.arrayBuffer() : undefined,
    redirect: 'manual',
  });

  const responseHeaders = new Headers(response.headers);
  responseHeaders.delete('content-encoding');
  responseHeaders.delete('content-length');

  return new NextResponse(response.body, {
    status: response.status,
    headers: responseHeaders,
  });
}

export {
  proxy as GET,
  proxy as POST,
  proxy as PUT,
  proxy as PATCH,
  proxy as DELETE,
};
