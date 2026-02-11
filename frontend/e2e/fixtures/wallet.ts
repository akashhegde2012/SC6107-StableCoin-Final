import { test as base } from '@playwright/test';
import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

type WalletFixture = {
  injectWallet: () => Promise<string>;
};

export const test = base.extend<WalletFixture>({
  injectWallet: async ({ page }, use) => {
    const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
    const rpcUrl = process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL || process.env.SEPOLIA_RPC_URL;

    if (!privateKey || !rpcUrl) {
      throw new Error('Missing DEPLOYER_PRIVATE_KEY or NEXT_PUBLIC_SEPOLIA_RPC_URL');
    }

    const account = privateKeyToAccount(privateKey as `0x${string}`);
    const client = createWalletClient({
      account,
      chain: sepolia,
      transport: http(rpcUrl),
    });

    // Expose helper to sign/send transactions from the browser
    await page.exposeFunction('mockWalletRequest', async (payload: any) => {
      const { method, params } = payload;
      console.log(`MockWallet: ${method}`, params);

      try {
        switch (method) {
          case 'eth_requestAccounts':
          case 'eth_accounts':
            return [account.address];
          case 'eth_chainId':
            return '0xaa36a7'; // Sepolia 11155111
          case 'net_version':
            return '11155111';
          case 'eth_sendTransaction':
            const txParams = params[0];
            const hash = await client.sendTransaction({
              to: txParams.to,
              value: txParams.value ? BigInt(txParams.value) : undefined,
              data: txParams.data,
              account,
              chain: sepolia,
            });
            return hash;
          default:
            return null;
        }
      } catch (error) {
        console.error(`MockWallet Error [${method}]:`, error);
        throw error;
      }
    });

    await page.addInitScript(({ rpcUrl, address }) => {
      const listeners = new Map<string, Set<(...args: unknown[]) => void>>();
      const emit = (event: string, ...args: unknown[]) => {
        const handlers = listeners.get(event);
        if (!handlers) return;
        for (const handler of handlers) {
          handler(...args);
        }
      };

      const provider = {
        isMetaMask: true,
        providers: [] as unknown[],
        _metamask: {
          isUnlocked: async () => true,
        },
        selectedAddress: address,
        chainId: '0xaa36a7',
        request: async ({ method, params }: { method: string; params?: unknown[] }) => {
          if (['eth_requestAccounts', 'eth_accounts', 'eth_chainId', 'net_version', 'eth_sendTransaction'].includes(method)) {
            const result = await (window as any).mockWalletRequest({ method, params });
            if (method === 'eth_requestAccounts') {
              emit('connect', { chainId: '0xaa36a7' });
              emit('accountsChanged', [address]);
            }
            return result;
          }

          const response = await fetch(rpcUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              jsonrpc: '2.0',
              id: 1,
              method,
              params: params ?? [],
            }),
          });
          const data = await response.json();
          if (data.error) throw new Error(data.error.message);
          return data.result;
        },
        on: (event: string, handler: (...args: unknown[]) => void) => {
          if (!listeners.has(event)) {
            listeners.set(event, new Set());
          }
          listeners.get(event)?.add(handler);
          return provider;
        },
        removeListener: (event: string, handler: (...args: unknown[]) => void) => {
          listeners.get(event)?.delete(handler);
          return provider;
        },
      };

      provider.providers = [provider];
      (window as any).ethereum = provider;
      window.dispatchEvent(new Event('ethereum#initialized'));

      const announce = () => {
        window.dispatchEvent(
          new CustomEvent('eip6963:announceProvider', {
            detail: {
              info: {
                uuid: '5f2a6b17-a06d-4f79-bf7b-e2e-metamask',
                name: 'MetaMask',
                icon: 'https://metamask.io/images/favicon-256.png',
                rdns: 'io.metamask',
              },
              provider,
            },
          }),
        );
      };

      window.addEventListener('eip6963:requestProvider', announce);
      announce();
    }, { rpcUrl, address: account.address });

    await use(async () => account.address);
  },
});
