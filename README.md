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

## Reactive Network Integration (Detailed)

Reactive Network is the automation layer that turns hook-emitted health signals into cross-chain liquidation transactions.

### Origin chain signal: `ReQuardHook` emits health

Whenever a registered collateral LP position changes (via a Uniswap V4 pool action), `ReQuardHook.afterModifyPosition(...)` updates internal LP state and, if the LP is linked to a lending position, emits:

- `PositionHealthUpdated(bytes32 indexed positionId, address indexed owner, uint256 collateralValue, uint256 debtValue, uint256 healthFactor)`

### Reactive subscription: watch `PositionHealthUpdated`

On Reactive Network, you create a subscription that monitors `ReQuardHook` on Base Sepolia for `PositionHealthUpdated` events. When an event is observed, Reactive Network calls your Reactive contract handler:

- `ReQuardReactive.onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)`

### Handler decision: emit `Callback` only when unhealthy

`ReQuardReactive` compares `healthFactor` against `minHealthFactor`:

- If `healthFactor >= minHealthFactor`: it returns without emitting anything.
- If `healthFactor < minHealthFactor`: it emits:
  - `Callback(destinationChainId, destinationContract, callbackGasLimit, payload)`

The emitted callback payload encodes the destination call:

- `abi.encodeWithSignature("liquidate(address,bytes32)", address(0), positionId)`

The first `address` argument is reserved for Reactive Network ABI conventions (Reactive Network overwrites it at execution time).

### Destination execution: validate Reactive VM, then call the hook

`ReQuardDestination` receives the callback via:

- `liquidate(address rvmAddress, bytes32 positionId)`

The destination enforces access control using:

- `onlyReactiveVm` (it checks `msg.sender == reactiveVm`)

After validation it calls:

- `hook.liquidatePosition(positionId)`

### Setup instructions

For subscription topic hashes, required handler signature checks, and operational troubleshooting, see `REACTIVE_SETUP.md`.

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

1. Configure environment variables used by the scripts (`PRIVATE_KEY`, and for Reactive deployment `DESTINATION_CONTRACT`, plus optional overrides for chain ids and thresholds).

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

1. A pool action triggers `ReQuardHook.afterModifyPosition(...)` (Uniswap V4 hook callback).
2. If the LP position has been registered as collateral in `ReQuardLending`, the hook emits `PositionHealthUpdated(...)`.
3. Reactive Network detects the event and calls `ReQuardReactive.onPositionHealthUpdated(...)`.
4. `ReQuardReactive` checks `healthFactor` against `minHealthFactor`.
5. If unhealthy, `ReQuardReactive` emits `Callback(...)` with a payload encoding `liquidate(address,bytes32)` and the `positionId`.
6. Reactive Network executes the callback on the destination chain by calling `ReQuardDestination.liquidate(...)`.
7. `ReQuardDestination` verifies the Reactive VM and forwards to `ReQuardHook.liquidatePosition(positionId)`.
8. The hook liquidates via `ReQuardLending.liquidatePosition(positionId)`, unwinds LP liquidity, and accumulates liquidation fees for distribution.

## Testing

```bash
forge test
```

This repo includes:

- Unit tests for `ReQuardReactive`, `ReQuardLending`, and `ReQuardHook`.
- An integration test that drives the liquidation flow through `ReQuardHook -> ReQuardReactive -> ReQuardDestination -> ReQuardHook -> ReQuardLending`.
- Fuzz tests for callback gating, health-factor math, and liquidation branching.

## Resources

- [Reactive Network Docs](https://dev.reactive.network/)
- [Reactive Contracts Guide](https://dev.reactive.network/reactive-contracts)
- [Uniswap V4 Documentation](https://docs.uniswap.org/)
- [Demo Repository](https://github.com/Reactive-Network/reactive-smart-contract-demos)

## License

UNLICENSED
