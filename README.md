# ReQuard

**Autonomous MEV-Triggered Liquidation Hook for Uniswap V4**

ReQuard is a Uniswap V4 hook that uses Reactive Contracts to autonomously monitor collateralized LP positions and trigger on-chain liquidations the moment a position's health factor drops below a safe threshold — **no keeper bots, no manual intervention**.

## Overview

ReQuard combines:
- **Uniswap V4 Hooks** - Customizable pool logic for LP position management
- **Reactive Network** - Event-driven smart contract execution layer
- **Minimal Lending Protocol** - Custom lending system for LP-backed collateral

## Architecture

### Contracts

1. **ReQuardLending** (`src/ReQuardLending.sol`)
   - Minimal custom lending protocol
   - Tracks LP positions as collateral
   - Manages borrowing and health factors
   - Handles liquidations

2. **ReQuardHook** (`src/ReQuardHook.sol`)
   - Uniswap V4 hook implementing `IHooks` interface
   - Tracks LP positions and their collateral values
   - Emits `PositionHealthUpdated` events for Reactive Network
   - Executes liquidations by unwinding LP positions

3. **ReQuardDestination** (`src/ReQuardDestination.sol`)
   - Receives callbacks from Reactive Network
   - Calls hook's liquidation function
   - Deployed on Base Sepolia

4. **ReQuardReactive** (`src/ReQuardReactive.sol`)
   - Reactive Contract deployed on Reactive Network
   - Monitors `PositionHealthUpdated` events from Base Sepolia
   - Emits `Callback` events to trigger liquidations
   - Implements correct Reactive Network patterns

## Features

- ✅ **Autonomous Liquidations** - No keeper bots required
- ✅ **Real-time Monitoring** - Reactive Network monitors positions continuously
- ✅ **Uniswap V4 Integration** - Proper hook interfaces and LP management
- ✅ **Health Factor Tracking** - Automatic health calculation and threshold monitoring
- ✅ **Fee Redistribution** - Liquidation fees redistributed to LPs

## Quick Start

### Prerequisites

- Foundry installed
- Base Sepolia testnet access
- Reactive Network Lasna Testnet access

### Build

```bash
forge build
```

### Deploy

1. Configure environment variables (see `.env.example`)

2. Deploy contracts on Base Sepolia:
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
```

3. Deploy Reactive Contract on Reactive Network Lasna Testnet

4. Configure Reactive Network subscription (see `REACTIVE_SETUP.md`)

### Configuration

**Chain IDs:**
- Base Sepolia: `84531`
- Reactive Network Lasna Testnet: `5318007`

**Health Factor Threshold:**
- Default: `1.2e18` (120%)
- Positions below this threshold are liquidated

**Gas Limits:**
- Callback Gas Limit: `500000`

## Project Structure

```
src/
├── interfaces/
│   └── IUniswapV4Hooks.sol    # Uniswap V4 hook interfaces
├── ReQuardLending.sol          # Minimal lending protocol
├── ReQuardHook.sol             # Uniswap V4 hook
├── ReQuardDestination.sol       # Callback receiver
└── ReQuardReactive.sol         # Reactive Contract

script/
└── Deploy.s.sol                # Deployment script

REACTIVE_SETUP.md               # Reactive Network setup guide
ReQuard-PRD.md                  # Product requirements document
```

## How It Works

1. **User creates LP position** in a Uniswap V4 pool with ReQuard hook
2. **User registers LP as collateral** in ReQuardLending and borrows
3. **Hook emits PositionHealthUpdated** event whenever position changes
4. **Reactive Contract monitors** events via Reactive Network subscription
5. **When health factor < threshold**, Reactive Contract emits Callback
6. **Destination contract receives callback** and calls hook's liquidation
7. **Hook unwinds LP position** and repays debt automatically
8. **Liquidation fees** are captured and redistributed to LPs

## Testing

```bash
forge test
```

## Resources

- [Reactive Network Docs](https://dev.reactive.network/)
- [Reactive Contracts Guide](https://dev.reactive.network/reactive-contracts)
- [Uniswap V4 Documentation](https://docs.uniswap.org/)
- [Demo Repository](https://github.com/Reactive-Network/reactive-smart-contract-demos)

## License

UNLICENSED
