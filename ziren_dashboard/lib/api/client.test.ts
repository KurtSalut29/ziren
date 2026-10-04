import { afterEach, describe, expect, it, vi } from 'vitest';
import { httpErrorMessage, networkErrorMessage } from './client';

// Evaluator findings #10 / #31: offline, the dashboard showed the backend URL,
// CORS and "Failed to fetch". People now get a sentence they can act on.
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('networkErrorMessage', () => {
  it('says the connection is down, and that nothing was saved, when offline', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.stubGlobal('navigator', { onLine: false });
    const msg = networkErrorMessage('/dispatch/queue', new TypeError('Failed to fetch'));
    expect(msg).toMatch(/No internet connection/);
    expect(msg).not.toMatch(/CORS|Failed to fetch|http/i);
  });

  it('says the server could not be reached when online', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.stubGlobal('navigator', { onLine: true });
    const msg = networkErrorMessage('/x', new TypeError('Failed to fetch'));
    expect(msg).toMatch(/Could not reach the Ziren server/);
    expect(msg).not.toMatch(/CORS|localhost|8000/);
  });
});

describe('httpErrorMessage', () => {
  it('quotes the reason the server gave', () => {
    expect(httpErrorMessage(409, { detail: 'Station is already active.' })).toBe('Station is already active.');
  });
  it('never shows a bare "HTTP 500"', () => {
    expect(httpErrorMessage(500, null)).not.toMatch(/HTTP/);
    expect(httpErrorMessage(502, null)).toMatch(/not responding/);
  });
  it('does not print a validation object as text', () => {
    expect(httpErrorMessage(422, { detail: [{ loc: ['body'], msg: 'x' }] })).toMatch(/error 422/);
  });
});
