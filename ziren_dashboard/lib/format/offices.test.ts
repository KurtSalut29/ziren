import { describe, expect, it } from 'vitest';
import { provincialAdminLabel, provincialOffice } from './offices';

// Evaluator finding #35: the provincial disaster office is the PDRRMO.
describe('provincial office names', () => {
  it('names the provincial disaster office PDRRMO, not MDRRMO', () => {
    expect(provincialOffice('MDRRMO')).toBe('PDRRMO');
    expect(provincialAdminLabel('MDRRMO')).toBe('PDRRMO Admin');
  });
  it('keeps BFP and PNP as provincial offices', () => {
    expect(provincialOffice('BFP')).toBe('BFP Provincial Office');
    expect(provincialAdminLabel('pnp')).toBe('PNP Provincial Admin');
  });
});
