'use client';

import { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card';
import { Button } from '@/app/components/ui/button';
import { Input } from '@/app/components/ui/input';
import { Label } from '@/app/components/ui/label';
import { ArrowDownUp, Wallet, ShieldCheck, AlertCircle, Loader2 } from 'lucide-react';
import { useDepositCollateral, useWithdrawCollateral } from '@/lib/hooks/useContractWrite';
import { CONTRACTS } from '@/lib/contracts';

interface CollateralManagerProps {
  wethBalance: string;
  wbtcBalance: string;
  wethDeposited: string;
  wbtcDeposited: string;
}

type Token = 'WETH' | 'WBTC';
type Action = 'deposit' | 'withdraw';

export default function CollateralManager({
  wethBalance,
  wbtcBalance,
  wethDeposited,
  wbtcDeposited
}: CollateralManagerProps) {
  const [activeTab, setActiveTab] = useState<Action>('deposit');
  const [selectedToken, setSelectedToken] = useState<Token>('WETH');
  const [amount, setAmount] = useState('');

  const deposit = useDepositCollateral();
  const withdraw = useWithdrawCollateral();

  const isDeposit = activeTab === 'deposit';
  const activeHook = isDeposit ? deposit : withdraw;
  
  // Reset state when switching tabs or tokens
  useEffect(() => {
    setAmount('');
  }, [activeTab, selectedToken]);

  const handleAction = async () => {
    if (!amount || parseFloat(amount) <= 0) return;
    
    const tokenAddress = selectedToken === 'WETH' ? CONTRACTS.WETH : CONTRACTS.WBTC;
    
    try {
      await activeHook.execute(tokenAddress, amount);
      // Optional: Clear amount on success if needed, but keeping it might be better for UX until confirmed
      if (activeHook.step === 'success') {
        setAmount('');
      }
    } catch (e) {
      console.error(e);
    }
  };

  const getBalance = () => {
    if (isDeposit) {
      return selectedToken === 'WETH' ? wethBalance : wbtcBalance;
    } else {
      return selectedToken === 'WETH' ? wethDeposited : wbtcDeposited;
    }
  };

  const getButtonText = () => {
    if (activeHook.step === 'approving') return 'Approving Token...';
    if (activeHook.step === 'executing') return isDeposit ? 'Depositing...' : 'Withdrawing...';
    if (activeHook.step === 'success') return 'Transaction Successful';
    return isDeposit ? `Deposit ${selectedToken}` : `Withdraw ${selectedToken}`;
  };

  const isPending = activeHook.isPending;
  const isSuccess = activeHook.step === 'success';

  return (
    <Card className="w-full bg-[#0d0d14] border-[#1a1a24] text-slate-200 shadow-xl">
      <CardHeader className="pb-4 border-b border-[#1a1a24]">
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg font-bold flex items-center gap-2 text-white">
            <ShieldCheck className="w-5 h-5 text-indigo-500" />
            Collateral Manager
          </CardTitle>
          <div className="flex bg-[#1a1a24] p-1 rounded-lg">
            <button
              onClick={() => setActiveTab('deposit')}
              className={`px-3 py-1 text-xs font-medium rounded-md transition-all ${
                activeTab === 'deposit' 
                  ? 'bg-indigo-600 text-white shadow-lg' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Deposit
            </button>
            <button
              onClick={() => setActiveTab('withdraw')}
              className={`px-3 py-1 text-xs font-medium rounded-md transition-all ${
                activeTab === 'withdraw' 
                  ? 'bg-indigo-600 text-white shadow-lg' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Withdraw
            </button>
          </div>
        </div>
      </CardHeader>
      
      <CardContent className="pt-6 space-y-6">
        {/* Token Selector */}
        <div className="space-y-3">
          <Label className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
            Select Asset
          </Label>
          <div className="grid grid-cols-2 gap-3">
            {(['WETH', 'WBTC'] as Token[]).map((token) => (
              <div
                key={token}
                onClick={() => setSelectedToken(token)}
                className={`cursor-pointer relative flex items-center justify-between p-3 rounded-xl border transition-all ${
                  selectedToken === token
                    ? 'bg-indigo-500/10 border-indigo-500/50 shadow-[0_0_15px_rgba(99,102,241,0.15)]'
                    : 'bg-[#13131a] border-[#22222e] hover:border-slate-600'
                }`}
              >
                <div className="flex items-center gap-3">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-xs ${
                    token === 'WETH' ? 'bg-blue-500/20 text-blue-400' : 'bg-orange-500/20 text-orange-400'
                  }`}>
                    {token[0]}
                  </div>
                  <span className={`font-bold ${selectedToken === token ? 'text-white' : 'text-slate-400'}`}>
                    {token}
                  </span>
                </div>
                {selectedToken === token && (
                  <div className="w-2 h-2 rounded-full bg-indigo-500 shadow-[0_0_8px_#6366f1]" />
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Amount Input */}
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <Label className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
              Amount
            </Label>
            <div className="flex items-center gap-1.5 text-xs text-slate-400">
              <Wallet className="w-3 h-3" />
              <span>
                {isDeposit ? 'Wallet: ' : 'Deposited: '}
                <span className="text-slate-200 font-mono">{getBalance()}</span>
              </span>
            </div>
          </div>
          
          <div className="relative group">
            <Input
              type="number"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-[#13131a] border-[#22222e] text-white placeholder:text-slate-600 h-12 pl-4 pr-16 text-lg font-mono focus-visible:ring-indigo-500/50 focus-visible:border-indigo-500 transition-all"
            />
            <div className="absolute right-4 top-1/2 -translate-y-1/2 text-sm font-bold text-slate-500 pointer-events-none">
              {selectedToken}
            </div>
          </div>
        </div>

        {/* Status & Error Messages */}
        {activeHook.error && (
          <div className="p-3 bg-red-500/10 border border-red-500/20 rounded-lg flex items-start gap-2 text-red-400 text-xs">
            <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
            <span>{activeHook.error}</span>
          </div>
        )}

        {isSuccess && (
          <div className="p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-lg flex items-center gap-2 text-emerald-400 text-xs">
            <ShieldCheck className="w-4 h-4" />
            <span>Transaction completed successfully!</span>
          </div>
        )}

        {/* Action Button */}
        <Button
          onClick={handleAction}
          disabled={!amount || parseFloat(amount) <= 0 || isPending}
          className={`w-full h-12 text-sm font-bold tracking-wide transition-all ${
            isPending 
              ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
              : isDeposit
                ? 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-[0_4px_20px_rgba(99,102,241,0.2)] hover:shadow-[0_4px_25px_rgba(99,102,241,0.3)]'
                : 'bg-slate-700 hover:bg-slate-600 text-white'
          }`}
        >
          {isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
          {getButtonText()}
        </Button>

        {/* Step Indicator (only when active) */}
        {isPending && (
          <div className="flex items-center justify-center gap-2 text-[10px] text-slate-500 uppercase tracking-widest font-semibold">
            <span className={activeHook.step === 'approving' ? 'text-indigo-400 animate-pulse' : 'text-slate-600'}>
              1. Approve
            </span>
            <span className="text-slate-700">→</span>
            <span className={activeHook.step === 'executing' ? 'text-indigo-400 animate-pulse' : 'text-slate-600'}>
              2. Execute
            </span>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
