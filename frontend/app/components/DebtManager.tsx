'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useMintStableCoin, useBurnStableCoin } from '@/lib/hooks/useContractWrite';
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from '@/app/components/ui/card';
import { Button } from '@/app/components/ui/button';
import { Input } from '@/app/components/ui/input';
import { Alert, AlertDescription, AlertTitle } from '@/app/components/ui/alert';
import { AlertCircle, CheckCircle2, XCircle, TrendingUp, DollarSign } from 'lucide-react';

interface DebtManagerProps {
  scBalance: string;
  totalDebt: string;
  maxMintable: string;
  stabilityFee: string;
  healthFactor: string;
}

type ActionTab = 'mint' | 'burn';

export default function DebtManager({
  scBalance,
  totalDebt,
  maxMintable,
  stabilityFee,
  healthFactor,
}: DebtManagerProps) {
  const [actionTab, setActionTab] = useState<ActionTab>('mint');
  const [amount, setAmount] = useState('');
  const router = useRouter();

  const { execute: mint, isPending: isMinting, error: mintError, step: mintStep } = useMintStableCoin();
  const { execute: burn, isPending: isBurning, error: burnError, step: burnStep } = useBurnStableCoin();

  const isPending = isMinting || isBurning;
  const error = actionTab === 'mint' ? mintError : burnError;
  const step = actionTab === 'mint' ? mintStep : burnStep;

  const availableBalance = actionTab === 'mint' ? maxMintable : scBalance;
  const balanceLabel = actionTab === 'mint' ? 'Max Mintable' : 'SC Balance';

  useEffect(() => {
    setAmount('');
  }, [actionTab]);

  const handleAction = async () => {
    if (!amount || parseFloat(amount) <= 0) return;

    let result;
    if (actionTab === 'mint') {
      result = await mint(amount);
    } else {
      result = await burn(amount);
    }

    if (result) {
      setAmount('');
      router.refresh();
    }
  };

  const setMaxAmount = () => {
    if (actionTab === 'burn') {
      const maxBurn = Math.min(parseFloat(scBalance), parseFloat(totalDebt));
      setAmount(maxBurn.toFixed(6));
    } else {
      setAmount(parseFloat(availableBalance).toFixed(6));
    }
  };

  const debtAfterAction = () => {
    if (!amount || parseFloat(amount) <= 0) return null;
    const current = parseFloat(totalDebt);
    const change = parseFloat(amount);
    if (actionTab === 'mint') {
      return (current + change).toFixed(4);
    } else {
      return Math.max(0, current - change).toFixed(4);
    }
  };

  const newDebt = debtAfterAction();

  const getHealthFactorColor = (hf: string) => {
    if (hf === '∞') return 'text-emerald-500';
    const val = parseFloat(hf);
    if (val > 1.5) return 'text-emerald-500';
    if (val >= 1.2) return 'text-yellow-500';
    return 'text-red-500';
  };

  const hfColor = getHealthFactorColor(healthFactor);
  const isHealthFactorLow = healthFactor !== '∞' && parseFloat(healthFactor) < 1.5;
  const isHealthFactorCritical = healthFactor !== '∞' && parseFloat(healthFactor) < 1.2;

  const showMintWarning = actionTab === 'mint' && isHealthFactorLow;

  return (
    <Card className="bg-[#0d0d14] border-[#1a1a24] text-slate-200 shadow-xl">
      <CardHeader className="pb-4 border-b border-[#1a1a24]">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base font-bold text-slate-100 flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 flex items-center justify-center text-emerald-500">
              <DollarSign size={16} />
            </div>
            Debt Manager
          </CardTitle>
          <div className="flex items-center gap-2 px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 rounded-full">
            <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            <span className="text-[11px] font-bold text-emerald-400 tracking-wide">
              1 SC = $1.00
            </span>
          </div>
        </div>
      </CardHeader>

      <CardContent className="pt-6 space-y-6">
        <div className="grid grid-cols-2 gap-3">
          <div className="p-3 bg-[#13131f] rounded-lg border border-[#1e1e2e]">
            <div className="text-[11px] text-slate-500 mb-1">Your Debt</div>
            <div className="text-lg font-bold font-mono text-slate-100">
              {parseFloat(totalDebt).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 })}
            </div>
            <div className="text-[10px] text-slate-600">SC minted</div>
          </div>
          <div className="p-3 bg-[#13131f] rounded-lg border border-[#1e1e2e]">
            <div className="text-[11px] text-slate-500 mb-1">Health Factor</div>
            <div className={`text-lg font-bold font-mono ${hfColor}`}>
              {healthFactor === '∞' ? '∞' : parseFloat(healthFactor).toFixed(4)}
            </div>
            <div className="text-[10px] text-slate-600">
              {isHealthFactorCritical ? 'Risk of Liquidation' : 'Safety Score'}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3 p-3 bg-indigo-500/5 border border-indigo-500/10 rounded-lg">
          <TrendingUp size={16} className="text-indigo-400" />
          <div className="text-xs text-slate-400">
            Current stability fee: <span className="text-indigo-400 font-bold">{stabilityFee}% APR</span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-1 p-1 bg-[#13131f] rounded-lg border border-[#1e1e2e]">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setActionTab('mint')}
            className={`text-xs font-bold transition-all ${
              actionTab === 'mint' 
                ? 'bg-[#1e1e2e] text-amber-500 shadow-sm' 
                : 'text-slate-500 hover:text-slate-300'
            }`}
          >
            + Mint SC
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setActionTab('burn')}
            className={`text-xs font-bold transition-all ${
              actionTab === 'burn' 
                ? 'bg-[#1e1e2e] text-red-500 shadow-sm' 
                : 'text-slate-500 hover:text-slate-300'
            }`}
          >
            - Burn SC
          </Button>
        </div>

        <div className="space-y-3">
          <div className="flex justify-between items-center text-xs">
            <span className="text-slate-500">{balanceLabel}</span>
            <button 
              onClick={setMaxAmount}
              className={`font-mono font-bold hover:underline ${
                actionTab === 'mint' ? 'text-amber-500' : 'text-red-500'
              }`}
            >
              MAX: {parseFloat(availableBalance).toFixed(4)}
            </button>
          </div>
          
          <div className="relative">
            <Input
              type="number"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-[#0d0d14] border-[#1e1e2e] text-slate-100 pr-12 font-mono focus:ring-1 focus:ring-slate-700"
            />
            <div className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-bold text-slate-500">
              SC
            </div>
          </div>

          {newDebt && (
            <div className="flex justify-between items-center px-3 py-2 bg-[#13131f] rounded border border-[#1e1e2e] text-xs">
              <span className="text-slate-500">New Debt</span>
              <span className={`font-mono font-bold ${actionTab === 'mint' ? 'text-amber-500' : 'text-emerald-500'}`}>
                {newDebt} SC
              </span>
            </div>
          )}
        </div>

        {showMintWarning && (
          <Alert variant="destructive" className="bg-red-900/10 border-red-900/20 text-red-400 py-2">
            <AlertCircle className="h-4 w-4" />
            <AlertTitle className="text-xs font-bold ml-2">Health Factor Warning</AlertTitle>
            <AlertDescription className="text-[11px] ml-2">
              Your health factor is low. Minting more SC increases liquidation risk.
            </AlertDescription>
          </Alert>
        )}

        <Button
          className={`w-full font-bold ${
            actionTab === 'mint' 
              ? 'bg-amber-500 hover:bg-amber-600 text-black' 
              : 'bg-red-500 hover:bg-red-600 text-white'
          }`}
          disabled={isPending || !amount || parseFloat(amount) <= 0}
          onClick={handleAction}
        >
          {isPending ? (
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
              {step === 'approving' ? 'Approving...' : 'Executing...'}
            </div>
          ) : (
            <>{actionTab === 'mint' ? 'Mint StableCoin' : 'Burn StableCoin'}</>
          )}
        </Button>

        {step === 'success' && (
          <Alert className="bg-emerald-500/10 border-emerald-500/20 text-emerald-400 py-2">
            <CheckCircle2 className="h-4 w-4" />
            <AlertTitle className="text-xs font-bold ml-2">Success</AlertTitle>
            <AlertDescription className="text-[11px] ml-2">
              Transaction completed successfully.
            </AlertDescription>
          </Alert>
        )}
        {step === 'error' && error && (
          <Alert variant="destructive" className="bg-red-900/10 border-red-900/20 text-red-400 py-2">
            <XCircle className="h-4 w-4" />
            <AlertTitle className="text-xs font-bold ml-2">Error</AlertTitle>
            <AlertDescription className="text-[11px] ml-2 break-all">
              {error}
            </AlertDescription>
          </Alert>
        )}
      </CardContent>

      <CardFooter className="pt-0 pb-4 px-6">
        <div className="w-full text-[10px] text-slate-600 text-center leading-relaxed">
          {actionTab === 'mint' 
            ? 'Minting increases debt. Keep Health Factor > 1.5 for safety.'
            : 'Burning reduces debt and improves Health Factor.'}
        </div>
      </CardFooter>
    </Card>
  );
}
