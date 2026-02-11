import { defineConfig, devices } from '@playwright/test';
import path from 'path';
import dotenv from 'dotenv';

// Load frontend env first.
dotenv.config({ path: path.resolve(__dirname, '.env.local') });
// Then load acceptance env for shared test secrets (does not override existing vars).
dotenv.config({
  path: path.resolve(__dirname, '../specs/002-Acceptance/.env.local'),
  override: false,
});

// Normalize env names used by fixtures/tests.
if (!process.env.DEPLOYER_PRIVATE_KEY && process.env.PRIVATE_KEY) {
  process.env.DEPLOYER_PRIVATE_KEY = process.env.PRIVATE_KEY;
}
if (!process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL && process.env.SEPOLIA_RPC_URL) {
  process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
}

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['list', { printSteps: true }],
    ['html', { open: 'never' }],
  ],
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    env: {
      ...process.env,
      NEXT_PUBLIC_E2E_PRIVATE_KEY: process.env.DEPLOYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY ?? '',
      NEXT_PUBLIC_E2E_ADDRESS: process.env.NEXT_PUBLIC_DEPLOYER_ADDRESS ?? '',
    },
  },
});
