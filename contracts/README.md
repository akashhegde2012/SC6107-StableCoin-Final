# StableCoin Protocol Smart Contracts

This directory contains the core smart contracts for the StableCoin Protocol, a decentralized, over-collateralized stablecoin system built with Foundry.

## Overview

The StableCoin Protocol allows users to mint a USD-pegged stablecoin (SC) through two primary mechanisms:
1.  **Collateralized Debt Positions (CDPs)**: Users deposit volatile assets (WETH, WBTC) as collateral to mint SC.
2.  **Price Stability Module (PSM)**: Users can swap other stablecoins (USDC, USDT) 1:1 for SC to maintain the peg.

The protocol features algorithmic stability fees, auction-based liquidations, and hardened oracle integrations.

## Environment Setup

### Prerequisites

-   **Foundry**: You must have Foundry installed. If you don't, run:
    ```bash
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```

### Installation

1.  Clone the repository and navigate to the `contracts` directory:
    ```bash
    cd contracts
    ```
2.  Install dependencies:
    ```bash
    forge install
    ```

## Usage

### Build

Compile the smart contracts:
```bash
forge build
```

### Test

Run the comprehensive test suite (Unit, Integration, and Invariant tests):
```bash
forge test
```

To run a specific test:
```bash
forge test --match-test testName
```

### Coverage

Generate a test coverage report:
```bash
forge coverage --report summary
```

### Local Development (Anvil)

Start a local Ethereum node:
```bash
anvil
```

### Deployment

Deploy the protocol to a local or remote network using the deployment script:
```bash
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

## Project Structure

-   `src/`: Core protocol logic.
    -   `StableCoin.sol`: The ERC20 stablecoin token.
    -   `StableCoinEngine.sol`: Manages CDPs, minting, and stability fees.
    -   `PSM.sol`: Price Stability Module for 1:1 swaps.
    -   `LiquidationAuction.sol`: Competitive auction system for liquidations.
    -   `libraries/OracleLib.sol`: Hardened Chainlink oracle integration.
-   `test/`: Comprehensive test suite.
    -   `fuzz/`: Invariant and handler-based fuzz tests.
    -   `Integration.t.sol`: Full user journey simulations.
-   `script/`: Deployment and configuration scripts.
-   `lib/`: External dependencies (OpenZeppelin, Chainlink).

## Documentation

For detailed technical information, refer to the `docs/` directory in the project root:
-   `architecture.md`: System design and component interactions.
-   `security-analysis.md`: Security measures and audit summary.
-   `gas-optimization.md`: Gas-saving techniques used in the protocol.
