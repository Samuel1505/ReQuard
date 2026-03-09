# Reactive Network Setup Guide for ReQuard

This guide explains how to configure Reactive Network subscriptions for ReQuard.

## Overview

ReQuard uses Reactive Network to autonomously monitor LP position health factors and trigger liquidations when positions become undercollateralized.

## Architecture

1. **Origin Chain (Base Sepolia)**: 
   - `ReQuardHook` emits `PositionHealthUpdated` events
   - `ReQuardDestination` receives liquidation callbacks

2. **Reactive Network (Lasna Testnet)**:
   - `ReQuardReactive` monitors events and emits callbacks

## Deployment Steps

### 1. Deploy Contracts on Base Sepolia

Deploy the following contracts using the deployment script:

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
```

**Contracts to deploy:**
- `ReQuardLending` - Minimal lending protocol
- `ReQuardHook` - Uniswap V4 hook
- `ReQuardDestination` - Callback receiver

### 2. Deploy Reactive Contract on Reactive Network

Deploy `ReQuardReactive` on Reactive Network Lasna Testnet (Chain ID: 5318007).

**Constructor Parameters:**
```solidity
constructor(
    uint64 _originChainId,        // 84531 (Base Sepolia)
    uint64 _destinationChainId,   // 84531 (Base Sepolia)
    address _destinationContract, // ReQuardDestination address
    uint256 _minHealthFactor,     // 1.2e18 (120%)
    uint64 _callbackGasLimit      // 500000
)
```

### 3. Configure Reactive Network Subscription

After deploying `ReQuardReactive`, you need to configure a subscription to monitor `PositionHealthUpdated` events.

**Event Signature:**
```
PositionHealthUpdated(bytes32 indexed positionId, address indexed owner, uint256 collateralValue, uint256 debtValue, uint256 healthFactor)
```

**Subscription Configuration:**
- **Origin Chain**: Base Sepolia (84531)
- **Target Contract**: `ReQuardHook` address
- **Event Topic**: `keccak256("PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)")`
- **Handler Function**: `onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)`

### 4. Fund the Reactive Contract

Reactive Contracts must maintain a balance to stay active. Fund `ReQuardReactive` with native tokens:

```solidity
// Send native tokens to ReQuardReactive contract
// Or call coverDebt() if using Reactive Network's debt management
```

### 5. Test the Integration

1. Create an LP position using `ReQuardHook`
2. Register it as collateral in `ReQuardLending`
3. Borrow against the collateral
4. Simulate price movement that reduces health factor below threshold
5. Verify that `ReQuardReactive` emits a `Callback` event
6. Verify that `ReQuardDestination` receives the callback and liquidates the position

## Configuration Parameters

### Chain IDs
- **Base Sepolia**: 84531
- **Reactive Network Lasna Testnet**: 5318007

### Health Factor Threshold
- **Minimum Health Factor**: 1.2e18 (120%)
- Positions with health factor below this threshold will be liquidated

### Gas Limits
- **Callback Gas Limit**: 500000
- Adjust based on actual gas consumption of liquidation operations

## Monitoring

Use Reactscan (Reactive Network's block explorer) to monitor:
- Contract status (Active/Inactive)
- Event subscriptions
- Callback executions
- Contract balance

## Troubleshooting

### Contract Status: Inactive
- **Cause**: Insufficient balance to cover callback gas costs
- **Solution**: Fund the contract with native tokens

### Callbacks Not Executing
- **Cause**: Incorrect subscription configuration or insufficient gas
- **Solution**: Verify subscription settings and increase `callbackGasLimit`

### Health Factor Not Updating
- **Cause**: Events not being emitted or subscription not configured
- **Solution**: Verify `PositionHealthUpdated` events are emitted and subscription is active

## Resources

- [Reactive Network Docs](https://dev.reactive.network/)
- [Reactive Contracts Guide](https://dev.reactive.network/reactive-contracts)
- [Events & Callbacks](https://dev.reactive.network/events-&-callbacks)
- [Demo Repository](https://github.com/Reactive-Network/reactive-smart-contract-demos)
