import path from 'node:path';
import { defineConfig } from 'vitest/config';

// Unit tests for the dashboard's logic (evaluator finding #25, 2026-10-05).
// `npm test` runs them; they need no browser and no backend.
export default defineConfig({
  resolve: { alias: { '@': path.resolve(__dirname, '.') } },
  test: {
    include: ['**/*.test.ts'],
    exclude: ['node_modules/**', '.next/**'],
    environment: 'node',
  },
});
