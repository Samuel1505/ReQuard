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

#### Option A: Using Deployment Script (Recommended)

1. **Set environment variables** in your `.env` file:
```bash
PRIVATE_KEY=your_private_key
REACTIVE_LASNA_RPC_URL=https://lasna-rpc.rnk.dev/
DESTINATION_CONTRACT=0x...  # ReQuardDestination address from Base Sepolia
ORIGIN_CHAIN_ID=84531        # Optional, defaults to 84531
DESTINATION_CHAIN_ID=84531    # Optional, defaults to 84531
MIN_HEALTH_FACTOR=1200000000000000000  # Optional, defaults to 1.2e18
CALLBACK_GAS_LIMIT=500000    # Optional, defaults to 500000
```

2. **Run the deployment script**:
```bash
forge script script/DeployReactive.s.sol:DeployReactiveScript \
  --rpc-url $REACTIVE_LASNA_RPC_URL \
  --broadcast
```

The script will:
- Deploy `ReQuardReactive` with the configured parameters
- Display the deployed contract address
- Show configuration details
- Provide next steps for setup

#### Option B: Manual Deployment with forge create

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

**Command:**
```bash
forge create src/ReQuardReactive.sol:ReQuardReactive \
  --rpc-url $REACTIVE_LASNA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args 84531 84531 <DESTINATION_CONTRACT_ADDRESS> 1200000000000000000 500000 \
  --broadcast
```

### 3. Configure Reactive Network Subscription

After deploying `ReQuardReactive`, you need to configure a subscription to monitor `PositionHealthUpdated` events from the `ReQuardHook` contract on Base Sepolia.

#### Understanding the Subscription

The subscription tells Reactive Network to:
1. Monitor `PositionHealthUpdated` events emitted by `ReQuardHook` on Base Sepolia
2. When an event is detected, call `onPositionHealthUpdated()` on your `ReQuardReactive` contract
3. The Reactive Contract then evaluates if liquidation is needed and emits a `Callback` event if so

#### Required Information

Before configuring the subscription, gather these details:

1. **ReQuardHook Address** (on Base Sepolia)
   - This is the contract that emits `PositionHealthUpdated` events
   - You should have this from Step 1 deployment

2. **ReQuardReactive Address** (on Reactive Network)
   - This is the contract that will receive the event notifications
   - You should have this from Step 2 deployment

3. **Event Details:**
   - **Event Name**: `PositionHealthUpdated`
   - **Event Signature**: `PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)`
   - **Event Topic Hash**: `0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887`
     - Calculate with: `cast sig-event "PositionHealthUpdated(bytes32 indexed,address indexed,uint256,uint256,uint256)"`
   - **Handler Function**: `onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)`

#### Configuration Steps

##### Option A: Using Reactive Network Dashboard/UI

1. **Access Reactive Network Dashboard**
   - Navigate to the Rc/UI (check [Reactive Network Docs](https://dev.reactive.network/) for the current URL)
   - Connect your wallet that deployed the `ReQuardReactive` contract

2. **Create New Subscription**
   - Click "Create Subscription" or "Add Event Subscription"
   - Select "Event Subscription" type

3. **Configure Subscription Parameters:**
   ```
   Origin Chain ID: 84531 (Base Sepolia)
   Target Contract Address: <ReQuardHook address on Base Sepolia>
   Event Topic: 0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887
   Reactive Contract Address: <ReQuardReactive address on Reactive Network>
   Handler Function: onPositionHealthUpdated
   ```

4. **Verify Configuration**
   - Review all parameters
   - Confirm the subscription is created
   - Check subscription status (should be "Active")

##### Option B: Using Reactive Network CLI (if available)

If Reactive Network provides a CLI tool, you can configure subscriptions programmatically:

```bash
# Example command (check Reactive Network docs for actual CLI syntax)
reactive subscribe \
  --origin-chain 84531 \
  --target-contract <REQUARD_HOOK_ADDRESS> \
  --event-topic 0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887 \
  --reactive-contract <REQUARD_REACTIVE_ADDRESS> \
  --handler onPositionHealthUpdated
```

##### Option C: Programmatic Configuration (via Smart Contract)

If Reactive Network supports programmatic subscription creation, you may need to call a subscription manager contract. Check the [Reactive Network documentation](https://dev.reactive.network/events-&-callbacks) for the latest API.

#### Verification Steps

After configuring the subscription:

1. **Check Subscription Status**
   - In the Reactive Network dashboard, verify the subscription shows as "Active"
   - Ensure the Reactive Contract address matches your deployed `ReQuardReactive`

2. **Verify Event Topic**
   - Confirm the event topic hash matches: `0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887`
   - You can verify with: `cast sig-event "PositionHealthUpdated(bytes32 indexed,address indexed,uint256,uint256,uint256)"`

3. **Test Event Monitoring**
   - Create a test LP position using `ReQuardHook`
   - Register it as collateral in `ReQuardLending`
   - Trigger a position update that emits `PositionHealthUpdated`
   - Check Reactscan (Reactive Network explorer) to see if the event was detected
   - Verify that `ReQuardReactive.onPositionHealthUpdated()` was called

4. **Monitor on Reactscan**
   - Visit Reactscan (Reactive Network's block explorer)
   - Search for your `ReQuardReactive` contract address
   - Check the "Subscriptions" or "Events" tab
   - Verify recent event processing

#### Troubleshooting

**Subscription Not Active:**
- Verify the Reactive Contract has sufficient balance (fund it if needed)
- Check that all addresses are correct (no typos)
- Ensure the event topic hash matches exactly

**Events Not Being Detected:**
- Verify `ReQuardHook` is actually emitting `PositionHealthUpdated` events
- Check that the origin chain ID is correct (84531 for Base Sepolia)
- Ensure the target contract address is the correct `ReQuardHook` address

**Handler Not Being Called:**
- Verify the handler function signature matches exactly: `onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)`
- Check that `ReQuardReactive` contract is deployed and active
- Review Reactive Network logs for any errors

#### Event Details Reference

**Event Signature:**
```solidity
event PositionHealthUpdated(
    bytes32 indexed positionId,
    address indexed owner,
    uint256 collateralValue,
    uint256 debtValue,
    uint256 healthFactor
);
```

**Event Topic Hash:**
```
0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887
```

**Handler Function:**
```solidity
function onPositionHealthUpdated(
    bytes32 positionId,
    address owner,
    uint256 collateralValue,
    uint256 debtValue,
    uint256 healthFactor
) external;
```

#### Quick Reference: Subscription Configuration Checklist

Use this checklist when configuring your subscription:

- [ ] **Origin Chain ID**: `84531` (Base Sepolia)
- [ ] **Target Contract**: `<Your ReQuardHook address on Base Sepolia>`
- [ ] **Event Topic Hash**: `0xcb8da267c0c5f7a8e001e6d2bbf4daa73f7f53c3b560c9d553af7c5d8082e887`
- [ ] **Reactive Contract**: `<Your ReQuardReactive address on Reactive Network>`
- [ ] **Handler Function**: `onPositionHealthUpdated`
- [ ] **Reactive Contract Funded**: Ensure contract has native tokens for callbacks
- [ ] **Subscription Status**: Verify "Active" in dashboard
- [ ] **Test Event**: Trigger a test event to verify monitoring works

**Quick Command to Calculate Event Topic:**
```bash
cast sig-event "PositionHealthUpdated(bytes32 indexed,address indexed,uint256,uint256,uint256)"
```

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
