## Contracts Reference

This document provides a contract‑by‑contract reference for the ReQuard system.
For full Solidity implementations, see the `src/` directory.

---

## Summary Table

- **`ReQuardLending`** – Minimal LP‑backed lending protocol.
- **`ReQuardHook`** – Uniswap V4 hook that tracks positions and executes liquidations.
- **`ReQuardDestination`** – Base Sepolia callback receiver for Reactive Network.
- **`ReQuardReactive`** – Reactive Contract on Reactive Network.
- **`IUniswapV4Hooks`** – Interface definitions for Uniswap V4 hooks.
- **Scripts**:
  - `script/Deploy.s.sol` – deployment orchestration.

---

## `ReQuardLending`

**Location:** `src/ReQuardLending.sol`

### Purpose

A deliberately minimal lending protocol designed to:

- Accept **Uniswap V4 LP positions** as collateral.
- Track **debt vs. collateral value** for each position.
- Support **automated liquidations** initiated by `ReQuardHook`.

### Key Responsibilities

- **Collateral Management**
  - Register LP positions as collateral.
  - Map positions to owners.

- **Borrowing & Repayment**
  - Let users borrow supported assets against LP collateral.
  - Track outstanding principal plus any modeled interest/fees.

- **Health Factor Calculation**
  - Expose functions to compute a health factor per position.
  - Provide views used by `ReQuardHook` and off‑chain monitoring.

- **Liquidations**
  - Provide a liquidation entry point callable by the hook.
  - Reduce debt and update collateral after liquidation.

### Typical Function Categories

While exact signatures may differ, you can expect functions along lines of:

- `openPosition(...)`
- `addCollateral(...)`
- `borrow(...)`
- `repay(...)`
- `getHealthFactor(positionId) view`
- `liquidate(positionId, ...)`

Refer to the actual contract for concrete names and access control rules.

---

## `ReQuardHook`

**Location:** `src/ReQuardHook.sol`

### Purpose

Implements the **Uniswap V4 hook interface** to integrate ReQuard’s liquidation logic directly into the lifecycle of a Uniswap V4 pool.

### Key Responsibilities

- **Hook Integration**
  - Implements methods from `IUniswapV4Hooks`.
  - Hooks into Uniswap actions such as:
    - Adding/removing liquidity.
    - Swaps affecting pool state.

- **Position Tracking**
  - Maintains mapping from LP positions to:
    - Owners.
    - Collateral value (in underlying tokens).
    - Debt in `ReQuardLending`.

- **Event Emission**
  - Emits:
    - `PositionHealthUpdated(bytes32 positionId, address owner, uint256 collateralValue, uint256 debtValue, uint256 healthFactor)`.
  - This event is consumed by `ReQuardReactive` via the Reactive Network.

- **Liquidation Execution**
  - Exposes a function (e.g. `liquidatePosition(...)`) used by `ReQuardDestination`.
  - Unwinds LP, repays debt, and redistributes fees.

### Security / Design Notes

- Should validate that liquidation calls originate from a trusted source (`ReQuardDestination`).
- Must ensure hook logic does not break Uniswap invariants or create reentrancy issues.

---

## `ReQuardDestination`

**Location:** `src/ReQuardDestination.sol`

### Purpose

Acts as the **bridge endpoint on Base Sepolia** that receives callback transactions initiated by `ReQuardReactive` on Reactive Network.

### Key Responsibilities

- **Callback Handling**
  - Defines a callback function (e.g. `onCallback(...)` or similar).
  - Decodes callback payload to identify which position should be liquidated.

- **Authorization**
  - Restricts callback entrypoint to calls originating from:
    - The Reactive Network’s official executor contracts.
    - Or a designated trusted address representing the Reactive infrastructure.

- **Calling into Hook / Lending**
  - Forwards liquidation instructions to `ReQuardHook`.
  - Verifies successful execution (and can emit its own events for monitoring).

---

## `ReQuardReactive`

**Location:** `src/ReQuardReactive.sol`

### Purpose

Implements the **Reactive Contract** pattern:

- Listens to events on the origin chain (Base Sepolia).
- Decides when to execute callbacks.
- Requests transactions back to the destination chain.

### Key Responsibilities

- **Configuration via Constructor**
  - `originChainId`: chain where `PositionHealthUpdated` originates.
  - `destinationChainId`: chain to receive callbacks.
  - `destinationContract`: `ReQuardDestination` on Base Sepolia.
  - `minHealthFactor`: liquidation threshold.
  - `callbackGasLimit`: gas limit for each callback.

- **Event Handling**
  - Defines a handler like:
    - `onPositionHealthUpdated(positionId, owner, collateralValue, debtValue, healthFactor)`.
  - Called by the Reactive Network runtime when an event is matched.

- **Liquidation Decision Logic**
  - Compares `healthFactor` against `minHealthFactor`.
  - Optionally enforces extra rules (e.g. rate limits, whitelists).

- **Callback Emission**
  - Encodes a call to `ReQuardDestination` with:
    - `positionId` and any additional parameters.
  - Emits a `Callback` / `Request` event the Reactive Network uses to build and send a transaction.

---

## `IUniswapV4Hooks`

**Location:** `src/interfaces/IUniswapV4Hooks.sol`

### Purpose

Defines the interfaces required for a Uniswap V4 hook to integrate with the Uniswap V4 core contracts.
ReQuard’s `ReQuardHook` implements these interfaces.

### Typical Contents

- Hook callback signatures such as:
  - `beforeInitialize`
  - `afterInitialize`
  - `beforeSwap`
  - `afterSwap`
  - `beforeAddLiquidity`
  - `afterAddLiquidity`
  - `beforeRemoveLiquidity`
  - `afterRemoveLiquidity`

Exactly which hooks are implemented depends on ReQuard’s strategy; see the source file for details.

---

## Scripts

### `Deploy.s.sol`

**Location:** `script/Deploy.s.sol`

**Purpose:**

- Orchestrates deploying:
  - `ReQuardLending`
  - `ReQuardHook`
  - `ReQuardDestination`
  - Any related configuration for Uniswap V4 pools.

**Usage Example:**

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
```

Make sure you have:

- Proper environment variables configured for RPCs and signers.
- Access to Base Sepolia with funded deployment keys.



#== Logs ==
  Deploying ReQuard contracts...
  Deployer: 0x89a68d0731F9Bc419d606f1F31Ead04c3fBDFdd6
  Base Sepolia Chain ID: 84531
  
1. Deploying ReQuardLending...
  ReQuardLending deployed at: 0x4f43F19157e238B6136f524F460De8F901293A79
  
2. Deploying ReQuardDestination (temporary)...
  ReQuardDestination deployed at: 0x61ee9020847f656bF4b86A4d83a58F59EADe2307
  
3. Deploying ReQuardHook...
  ReQuardHook deployed at: 0x93Ebb626f8A25275c25E8aa6068d956047d6363a
  
4. Setting hook as liquidator in lending protocol...
  
5. Deploying ReQuardReactive (for Reactive Network)...
  NOTE: Deploy this contract on Reactive Network Lasna Testnet (Chain ID: 5318007 )
  Constructor parameters:
    originChainId: 84531
    destinationChainId: 84531
    destinationContract: 0x61ee9020847f656bF4b86A4d83a58F59EADe2307
    minHealthFactor: 1200000000000000000
    callbackGasLimit: 500000
  ReQuardReactive deployed at: 0x6da9d9685207E772be1c348beD5055a271B41ba5
  NOTE: Redeploy this on Reactive Network Lasna Testnet!
  
=== Deployment Summary ===
  ReQuardLending: 0x4f43F19157e238B6136f524F460De8F901293A79
  ReQuardDestination: 0x61ee9020847f656bF4b86A4d83a58F59EADe2307
  ReQuardHook: 0x93Ebb626f8A25275c25E8aa6068d956047d6363a
  ReQuardReactive: 0x6da9d9685207E772be1c348beD5055a271B41ba5
  
Next Steps:
  1. Update ReQuardDestination with correct hook address (or redeploy)
  2. Deploy ReQuardReactive on Reactive Network Lasna Testnet
  3. Configure Reactive Network subscription to monitor PositionHealthUpdated events
  4. Fund ReQuardReactive contract to keep it active

## Setting up 1 EVM.

==========================

Chain 84532

Estimated gas price: 0.011 gwei

Estimated total gas used for script: 6788237

Estimated amount required: 0.000074670607 ETH

==========================

##### base-sepolia
✅  [Success] Hash: 0xa1e83bfc1ddc984214f96dc76dd7e0a7d7a84bb4f46a642570598675cf03a5d1
Contract Address: 0x4f43F19157e238B6136f524F460De8F901293A79
Block: 38817041
Paid: 0.000009900624 ETH (1650104 gas * 0.006 gwei)


##### base-sepolia
✅  [Success] Hash: 0x4728768f6637749cc2f5a94e25f1d34f3a10f1314f518327af43a6dd8dd041f7
Contract Address: 0x93Ebb626f8A25275c25E8aa6068d956047d6363a
Block: 38817041
Paid: 0.000016061328 ETH (2676888 gas * 0.006 gwei)


##### base-sepolia
✅  [Success] Hash: 0xb55746532a5c6595cf4172f70acf7d33decfcb429fed80da214a982feda69add
Contract Address: 0x61ee9020847f656bF4b86A4d83a58F59EADe2307
Block: 38817041
Paid: 0.000001750326 ETH (291721 gas * 0.006 gwei)


##### base-sepolia
✅  [Success] Hash: 0x1605e67078f866f0b52fb0f536a0ab3009784b5782555a4cf0a4bece4bc6e0e5
Contract Address: 0x6da9d9685207E772be1c348beD5055a271B41ba5
Block: 38817041
Paid: 0.000003336024 ETH (556004 gas * 0.006 gwei)


##### base-sepolia
✅  [Success] Hash: 0x0b5ba2165a6b3103d544fa1afadc15b1eecf57501cd54140c35678878a04b45c
Block: 38817041
Paid: 0.00000026544 ETH (44240 gas * 0.006 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.000031313742 ETH (5218957 gas * avg 0.006 gwei)
                                                                                                

==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
Warning: We haven't found any matching bytecode for the following contracts: [0x4f43f19157e238b6136f524f460de8f901293a79, 0x61ee9020847f656bf4b86a4d83a58f59eade2307, 0x93ebb626f8a25275c25e8aa6068d956047d6363a, 0x6da9d9685207e772be1c348bed5055a271b41ba5].

This may occur when resuming a verification, but the underlying source code or compiler version has changed.
##
Start verification for (0) contracts
All (0) contracts were verified!

Transactions saved to: /home/admin/Desktop/dev/ReQuard/broadcast/Deploy.s.sol/84532/run-latest.json

Sensitive values saved to: /home/admin/Desktop/dev/ReQuard/cache/Deploy.s.sol/84532/run-latest.json

Reactive_Contract_Address=0xFFa3A0Ea10FE30a5d7c0F1B5597c189A38364E67