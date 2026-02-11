import { ConnectButton } from '@rainbow-me/rainbowkit';

export default function Header() {
  return (
    <header className="bg-[#0a0a0f]/95 border-b border-[#1e1e2e] backdrop-blur-md sticky top-0 z-50">
      <div className="max-w-[1400px] mx-auto px-6 h-16 flex items-center justify-between">
        {/* Logo */}
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#f59e0b] to-[#d97706] flex items-center justify-center text-base font-extrabold text-black">
            S
          </div>
          <div>
            <div className="text-base font-bold text-[#f1f5f9] leading-[1.2]">
              SC Protocol
            </div>
            <div className="text-[11px] text-[#6b7280] tracking-wider">
              COLLATERALIZED STABLECOIN
            </div>
          </div>
        </div>

        {/* Center nav */}
        <nav className="flex gap-1">
          {[
            { label: 'Dashboard', active: true },
          ].map((item) => (
            <button
              key={item.label}
              className={`px-3.5 py-1.5 rounded-md text-sm transition-all duration-200 cursor-pointer border-none ${
                item.active 
                  ? 'font-semibold text-[#f59e0b] bg-[#f59e0b]/10' 
                  : 'font-normal text-[#94a3b8] bg-transparent'
              }`}
            >
              {item.label}
            </button>
          ))}
        </nav>

        {/* Right: Connect Button */}
        <div className="flex items-center gap-3">
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}

