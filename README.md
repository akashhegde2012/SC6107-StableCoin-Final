# StableCoin Protocol (SCP)

A robust, over-collateralized stablecoin system inspired by MakerDAO, featuring hardened oracle integrations and algorithmic stability mechanisms.

## 🚀 Overview

The StableCoin Protocol (SCP) allows users to mint a decentralized, USD-pegged stablecoin (**SC**) through two primary mechanisms:

1.  **Collateralized Debt Positions (CDPs)**: Deposit volatile assets (WETH, WBTC) to mint SC at a 200% collateralization ratio.
2.  **Price Stability Module (PSM)**: Swap supported stablecoins 1:1 for SC to maintain the peg through arbitrage.

## 🏗️ Project Structure

-   `contracts/`: Solidity smart contracts built with Foundry.
    -   `src/StableCoinEngine.sol`: Core logic for CDPs, health factors, and stability fees.
    -   `src/libraries/OracleLib.sol`: Hardened Chainlink integration (Stale checks, TWAP, Circuit Breakers).
    -   `src/PSM.sol`: 1:1 peg stability module.
    -   `src/LiquidationAuction.sol`: Competitive auction system for under-collateralized positions.
-   `frontend/`: Next.js web application using Wagmi, Viem, and Tailwind CSS.
-   `docs/`: Detailed technical documentation on architecture, security, and gas optimizations.

## 🛡️ Security & Oracle Safety

The protocol uses **OracleLib** to enforce strict guardrails on all price data:
-   **Stale Price Check**: Reverts if the oracle heartbeat (3 hours) is exceeded.
-   **Circuit Breaker**: Reverts if price deviates >30% within a 30-minute window.
-   **TWAP Smoothing**: 30-minute time-weighted average to prevent flash-loan manipulation.

## ⚙️ Development

### Smart Contracts (Foundry)
```bash
cd contracts
forge build
forge test
```

### Frontend (Next.js)
```bash
cd frontend
npm install
npm run dev
```

## 🔮 Maintenance: Refreshing Mock Oracles

On testnets like Sepolia, mock oracles may become "stale" if they aren't updated regularly. If transactions fail with `OracleLib__StalePrice`, you must refresh the price feed timestamp.

**Update StableCoin (SC) Price Feed:**
```bash
cast send 0x26818a983a4c93D211515d142B77c6566EdfE2E7 "updateAnswer(int256)" 100000000 --private-key $PRIVATE_KEY --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

## 📄 License
MIT
