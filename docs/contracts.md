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

