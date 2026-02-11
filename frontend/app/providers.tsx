'use client';

import * as React from 'react';
import {
  RainbowKitProvider,
  getDefaultConfig,
  darkTheme,
} from '@rainbow-me/rainbowkit';
import { WagmiProvider, http } from 'wagmi';
import { sepolia } from 'wagmi/chains';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

function createConfig() {
  return getDefaultConfig({
    appName: 'StableCoin Protocol',
    projectId: 'YOUR_PROJECT_ID',
    chains: [sepolia],
    transports: {
      [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
    },
    ssr: false,
  });
}

export function Providers({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = React.useState<ReturnType<typeof createConfig> | null>(
    typeof window === 'undefined' ? null : createConfig(),
  );
  const [queryClient] = React.useState(() => new QueryClient());

  React.useEffect(() => {
    if (!config) {
      setConfig(createConfig());
    }
  }, [config]);

  if (!config) {
    return null;
  }

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme()}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
