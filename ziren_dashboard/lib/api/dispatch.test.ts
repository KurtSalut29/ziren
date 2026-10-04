import { afterEach, describe, expect, it, vi } from 'vitest';
import { assignResponder, fetchResponderPosition, saveNarrativeReport } from './dispatch';

// Evaluator finding #25: the incident-management calls the console depends on,
// checked against what they actually send.
function mockFetch(body: unknown = {}, status = 200) {
  const fn = vi.fn(async () => new Response(JSON.stringify(body), { status }));
  vi.stubGlobal('fetch', fn);
  return fn;
}

afterEach(() => vi.unstubAllGlobals());

describe('dispatch calls', () => {
  it('a dispatch carries the dispatcher’s severity confirmation (finding #4)', async () => {
    const fetchFn = mockFetch({ status: 'dispatched' });
    await assignResponder('inc-1', {
      responder_id: 'r-1', chosen_severity: 'high', suggested_severity: 'high',
      override_reason: null, notes: null, severity_confirmed: true,
    }, 'tok');
    const [url, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/dispatch\/queue\/inc-1\/assign$/);
    expect(init.method).toBe('POST');
    expect(JSON.parse(String(init.body))).toMatchObject({ severity_confirmed: true, chosen_severity: 'high' });
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer tok');
  });

  it('a refused dispatch surfaces the server’s reason, not "HTTP 422"', async () => {
    mockFetch({ detail: 'Confirm that you have checked the severity and the reason for it before dispatching.' }, 422);
    await expect(assignResponder('inc-1', {
      responder_id: 'r-1', chosen_severity: 'high', severity_confirmed: false,
    }, 'tok')).rejects.toThrow(/Confirm that you have checked the severity/);
  });

  it('reads the assigned responder’s position for the live map (finding #2)', async () => {
    const fetchFn = mockFetch({ responder_id: 'r-1', full_name: 'Juan', lat: 11.5, lng: 124.4, updated_at: null });
    const pos = await fetchResponderPosition('inc-1', 'tok');
    expect(String((fetchFn.mock.calls[0] as unknown as [string])[0])).toMatch(/\/dispatch\/queue\/inc-1\/responder-position$/);
    expect(pos?.lat).toBe(11.5);
  });

  it('changing a finalized narrative report sends the reason (finding #8)', async () => {
    const fetchFn = mockFetch({ id: 'r1', status: 'finalized', details_saved: true, details_supported: true });
    await saveNarrativeReport('inc-1', { narrative: 'x', amendment_reason: 'Corrected the time' }, 'tok');
    const [, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(String(init.body)).amendment_reason).toBe('Corrected the time');
  });
});
