'use client';

import { useAccount, useReadContracts, useBalance } from 'wagmi';
import { formatEther } from 'viem';
import { 
  CONTRACTS, 
  STABLE_COIN_ENGINE_ABI, 
  ERC20_ABI, 
  activeChain 
} from '@/lib/contracts';
import Header from '@/app/components/Header';
import AccountInfo from '@/app/components/AccountInfo';
import CollateralManager from '@/app/components/CollateralManager';
import DebtManager from '@/app/components/DebtManager';

export default function Home() {
  const { address: connectedAddress } = useAccount();
  const address = connectedAddress ?? (process.env.NEXT_PUBLIC_E2E_ADDRESS as `0x${string}` | undefined);

  // 1. Protocol Stats & Prices
  const { data: protocolData } = useReadContracts({
    contracts: [
      { address: CONTRACTS.STABLE_COIN, abi: ERC20_ABI, functionName: 'totalSupply' },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getLiquidationThreshold' },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getLiquidationBonus' },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getCurrentStabilityFeeBps' },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getProtocolReserve' },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getProtocolBadDebt' },
    ],
    query: { refetchInterval: 10000 }
  });

  // 2. User Position Data
  const { data: userData } = useReadContracts({
    contracts: [
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getAccountInformation', args: [address!] },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getHealthFactor', args: [address!] },
      // Collateral Balances
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getCollateralBalanceOfUser', args: [address!, CONTRACTS.WETH] },
      { address: CONTRACTS.STABLE_COIN_ENGINE, abi: STABLE_COIN_ENGINE_ABI, functionName: 'getCollateralBalanceOfUser', args: [address!, CONTRACTS.WBTC] },
      // Wallet Balances (ERC20)
      { address: CONTRACTS.WETH, abi: ERC20_ABI, functionName: 'balanceOf', args: [address!] },
      { address: CONTRACTS.WBTC, abi: ERC20_ABI, functionName: 'balanceOf', args: [address!] },
      { address: CONTRACTS.STABLE_COIN, abi: ERC20_ABI, functionName: 'balanceOf', args: [address!] },
    ],
    query: { enabled: !!address, refetchInterval: 5000 }
  });

  // ETH Balance
  const { data: ethBalance } = useBalance({ address });

  // Process Protocol Data
  const stats = {
    totalSupply: protocolData?.[0].result ? formatEther(protocolData[0].result) : '0',
    liquidationThreshold: protocolData?.[1].result?.toString() ?? '50',
    liquidationBonus: protocolData?.[2].result?.toString() ?? '10',
    stabilityFee: protocolData?.[3].result ? (Number(protocolData[3].result) / 100).toFixed(2) : '2.00',
    protocolReserve: protocolData?.[4].result ? formatEther(protocolData[4].result) : '0',
    protocolBadDebt: protocolData?.[5].result ? formatEther(protocolData[5].result) : '0',
  };

  // Process User Data
  const accountInfo = userData?.[0].result;
  const healthFactor = userData?.[1].result;
  const wethCollateral = userData?.[2].result ?? 0n;
  const wbtcCollateral = userData?.[3].result ?? 0n;
  
  const wethWallet = userData?.[4].result ?? 0n;
  const wbtcWallet = userData?.[5].result ?? 0n;
  const scWallet = userData?.[6].result ?? 0n;

  // Calculate Max Mintable
  let maxMintable = '0';
  if (accountInfo && protocolData?.[1].result) {
    const collateralValueUsd = accountInfo[1];
    const totalDebt = accountInfo[0];
    const threshold = protocolData[1].result;
    const maxDebt = (collateralValueUsd * threshold) / 100n;
    const available = maxDebt > totalDebt ? maxDebt - totalDebt : 0n;
    maxMintable = formatEther(available);
  }

  const position = {
    totalDebt: accountInfo ? formatEther(accountInfo[0]) : '0',
    collateralValueUsd: accountInfo ? formatEther(accountInfo[1]) : '0',
    healthFactor: healthFactor 
      ? (healthFactor === BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff') ? '∞' : formatEther(healthFactor))
      : '∞',
    collateralBalances: [
      { symbol: 'WETH', balance: formatEther(wethCollateral), token: CONTRACTS.WETH, valueUsd: '0' }, // Value USD would need another call or calc
      { symbol: 'WBTC', balance: formatEther(wbtcCollateral), token: CONTRACTS.WBTC, valueUsd: '0' },
    ]
  };

  const balances = {
    eth: ethBalance ? ethBalance.formatted : '0',
    weth: formatEther(wethWallet),
    wbtc: formatEther(wbtcWallet),
    sc: formatEther(scWallet),
  };

  return (
    <div className="min-h-screen bg-black">
      <Header />

      <main className="max-w-[1400px] mx-auto px-6 py-7 pb-12">
        <div className="mb-4 flex justify-end">
          <span className={`text-[11px] px-3 py-1 rounded-[20px] border font-semibold tracking-wide ${
            activeChain.id === 11155111 
              ? 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20' 
              : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
          }`}>
            ● {activeChain.name}
          </span>
        </div>

        {/* Main content grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5 items-start">
          {/* Left column: Position + Wallet */}
          <div className="flex flex-col gap-4">
            <AccountInfo 
              address={address}
              walletBalances={balances}
              collateralBalances={{
                weth: formatEther(wethCollateral),
                wbtc: formatEther(wbtcCollateral)
              }}
              debt={position.totalDebt}
            />
          </div>

          {/* Right column: Actions (Spans 2 columns on desktop) */}
          <div className="md:col-span-2 flex flex-col gap-4">
            {/* How it works banner */}
            <div className="p-4 md:p-5 bg-gradient-to-br from-amber-500/5 to-indigo-500/5 border border-amber-500/10 rounded-xl flex items-start gap-4">
              <div className="text-2xl flex-shrink-0">💡</div>
              <div>
                <div className="text-[13px] font-bold text-slate-100 mb-1.5">
                  How it works
                </div>
                <div className="flex flex-wrap gap-5">
                  {[
                    { step: '1', text: 'Deposit WETH or WBTC as collateral' },
                    { step: '2', text: 'Mint SC up to 50% of your collateral value' },
                    { step: '3', text: 'Repay debt to reclaim your collateral' },
                  ].map((item) => (
                    <div key={item.step} className="flex items-center gap-1.5">
                      <div className="w-[18px] h-[18px] rounded-full bg-amber-500/20 border border-amber-500/30 flex items-center justify-center text-[10px] font-bold text-amber-500 flex-shrink-0">
                        {item.step}
                      </div>
                      <span className="text-xs text-slate-400">{item.text}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Action panels */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <CollateralManager
                wethBalance={balances.weth}
                wbtcBalance={balances.wbtc}
                wethDeposited={formatEther(wethCollateral)}
                wbtcDeposited={formatEther(wbtcCollateral)}
              />
              <DebtManager
                scBalance={balances.sc}
                totalDebt={position.totalDebt}
                maxMintable={maxMintable}
                stabilityFee={stats.stabilityFee}
                healthFactor={position.healthFactor}
              />
            </div>

            {/* Protocol mechanics info */}
            <div className="bg-[#0d0d14] border border-[#1a1a24] rounded-lg p-5">
              <div className="flex items-center gap-2 mb-3.5">
                <h3 className="text-sm font-bold text-slate-100 m-0">
                  Protocol Mechanics
                </h3>
                <div className="flex-1 h-px bg-[#1e1e2e]" />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                {[
                  {
                    title: 'Stability Fees',
                    icon: '📈',
                    textColor: 'text-[#6366f1]',
                    desc: `${stats.stabilityFee}% APR — dynamically adjusts based on SC peg. Increases when SC trades below $0.99, decreases above $1.01.`,
                  },
                  {
                    title: 'Liquidations',
                    icon: '🔨',
                    textColor: 'text-[#ef4444]',
                    desc: `Positions below health factor 1.0 are eligible for liquidation via English auction. Liquidators receive ${stats.liquidationBonus}% bonus collateral.`,
                  },
                  {
                    title: 'Price Stability Module',
                    icon: '⚖️',
                    textColor: 'text-[#f59e0b]',
                    desc: 'PSM enables 1:1 swaps between collateral tokens and SC to maintain the $1.00 peg through arbitrage.',
                  },
                  {
                    title: 'Oracle Safety',
                    icon: '🔮',
                    textColor: 'text-[#10b981]',
                    desc: 'Hardened Chainlink oracles with 3-hour stale timeout, 30% circuit breaker, and 30-minute TWAP smoothing.',
                  },
                ].map((item) => (
                  <div
                    key={item.title}
                    className="p-3 bg-[#0d0d14] rounded-lg border border-[#1a1a24]"
                  >
                    <div className="flex items-center gap-1.5 mb-1.5">
                      <span className="text-sm">{item.icon}</span>
                      <span
                        className={`text-xs font-bold ${item.textColor}`}
                      >
                        {item.title}
                      </span>
                    </div>
                    <p className="text-[11px] text-gray-500 leading-relaxed m-0">
                      {item.desc}
                    </p>
                  </div>
                ))}
              </div>
            </div>

            {/* Contract Addresses */}
            <div className="bg-[#0d0d14] border border-[#1a1a24] rounded-lg p-5">
              <div className="flex items-center gap-2 mb-3.5">
                <h3 className="text-sm font-bold text-slate-100 m-0">
                  Deployed Contracts
                </h3>
                <div className="flex-1 h-px bg-[#1e1e2e]" />
                <span className={`text-[10px] px-2 py-0.5 rounded-[10px] border ${
                  activeChain.id === 11155111 
                    ? 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20' 
                    : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                }`}>
                  {activeChain.name} {activeChain.id}
                </span>
              </div>

              <div className="flex flex-col gap-1.5">
                {[
                  { label: 'StableCoin (SC)', addr: CONTRACTS.STABLE_COIN, textColor: 'text-[#10b981]' },
                  { label: 'StableCoinEngine', addr: CONTRACTS.STABLE_COIN_ENGINE, textColor: 'text-[#f59e0b]' },
                  { label: 'WETH Token', addr: CONTRACTS.WETH, textColor: 'text-[#627EEA]' },
                  { label: 'WBTC Token', addr: CONTRACTS.WBTC, textColor: 'text-[#F7931A]' },
                ].map((c) => (
                  <div
                    key={c.addr}
                    className="flex items-center justify-between px-3 py-2 bg-[#0d0d14] rounded-md border border-[#1a1a24]"
                  >
                    <span className="text-xs text-slate-400 font-medium">{c.label}</span>
                    <span
                      className={`text-[11px] font-mono opacity-80 ${c.textColor}`}
                    >
                      {c.addr.slice(0, 10)}...{c.addr.slice(-6)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-[#1e1e2e] py-5 px-6 text-center text-xs text-gray-700">
        <div className="max-w-[1400px] mx-auto flex justify-between items-center">
          <span>SC Protocol — MakerDAO-style Collateralized Stablecoin</span>
          <span>Built with Foundry · Next.js · Viem · Tailwind CSS</span>
        </div>
      </footer>
    </div>
  );
}
