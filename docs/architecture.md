## ReQuard Architecture

This document explains the internal architecture of ReQuard and how its components interact across chains.

---

## System Diagram (Conceptual)

On a high level, the system looks like this:

- **Base Sepolia (Chain ID 84531)**
  - `ReQuardLending`
  - `ReQuardHook` (Uniswap V4 hook)
  - `ReQuardDestination`
  - Uniswap V4 pool with ReQuard hook enabled

- **Reactive Network – Lasna Testnet (Chain ID 5318007)**
  - `ReQuardReactive` (Reactive Contract)
  - Event subscription for `PositionHealthUpdated`

The information flow:

1. LP positions change → `ReQuardHook` updates position health and emits an event.
2. `ReQuardReactive` on Reactive Network receives the event data.
3. If liquidation is needed, `ReQuardReactive` triggers a callback.
4. Reactive Network submits a transaction to `ReQuardDestination` on Base Sepolia.
5. `ReQuardDestination` calls `ReQuardHook` to execute liquidation in the lending protocol.

---

## Contracts on Base Sepolia

### `ReQuardLending`

**Responsibilities:**

- Maintains a **registry of collateralized positions**:
  - Who owns the position.
  - What LP tokens or position IDs back it.
  - The outstanding debt for each position.
- Calculates and exposes the **health factor** of each position.
- Provides functions to:
  - Open positions and supply collateral.
  - Borrow against collateral.
  - Repay loans.
  - Handle liquidations when called by authorized contracts (e.g. the hook).

**Key design points:**

- Keeps the lending logic decoupled from Uniswap and from the Reactive Network.
- Enables reuse with other collateral types if extended.

---

### `ReQuardHook` (Uniswap V4 Hook)

**Responsibilities:**

- Integrates with the Uniswap V4 pool as a **hook contract**.
- Tracks LP positions and their corresponding collateral in `ReQuardLending`.
- On relevant Uniswap actions (e.g. minting/burning liquidity, swaps, fee collection):
  - Recomputes the position’s collateral value.
  - Updates the health factor.
  - Emits:
    - `PositionHealthUpdated(bytes32 positionId, address owner, uint256 collateralValue, uint256 debtValue, uint256 healthFactor)`.
- Provides an entry point that performs:
  - LP position unwinding.
  - Debt repayment in `ReQuardLending`.
  - Distribution of liquidation fees.

**Why a hook?**

- Hooks give direct access to LP position changes:
  - No need to scrape logs or poll on-chain state.
  - Guarantees that health metrics are updated atomically with state transitions.

---

### `ReQuardDestination`

**Responsibilities:**

- Acts as the on-chain **receiver of callbacks** from the Reactive Network.
- Exposes a function (e.g. `onCallback(...)`) that:
  - Validates that the caller is a trusted Reactive Network entrypoint / executor.
  - Decodes which position should be liquidated.
  - Calls into `ReQuardHook` (and/or `ReQuardLending`) to perform the liquidation.

**Security considerations:**

- Should restrict who can call the callback entrypoint.
- Should validate parameters that identify positions to avoid malicious or malformed callbacks.

---

## Contracts on Reactive Network

### `ReQuardReactive`

**Responsibilities:**

- Lives entirely on the **Reactive Network** chain.
- In its constructor, is configured with:
  - `originChainId` – the chain where events are observed (Base Sepolia).
  - `destinationChainId` – where callbacks go (Base Sepolia in this design).
  - `destinationContract` – address of `ReQuardDestination` on Base Sepolia.
  - `minHealthFactor` – the liquidation threshold.
  - `callbackGasLimit` – suggested gas limit for each callback execution.

**Event Handling:**

- Subscribed to the `PositionHealthUpdated` event from `ReQuardHook` on Base Sepolia.
- For each event:
  - Parses `positionId`, `owner`, `collateralValue`, `debtValue`, and `healthFactor`.
  - Compares `healthFactor` against `minHealthFactor`.
  - If below threshold, prepares and emits a **callback request** back to Base Sepolia.

**Callback Emission:**

- Emits a `Callback` (or equivalent) event that the Reactive Network runtime interprets.
- Instructs the runtime to:
  - Call `ReQuardDestination` on `destinationChainId`.
  - Provide encoded data specifying which position to liquidate.
  - Use `callbackGasLimit` when constructing the transaction.

---

## Cross-Chain / Cross-Environment Flow

This is the full lifecycle of a typical position:

1. **Position Creation**
   - User provides liquidity to a Uniswap V4 pool with ReQuard’s hook.
   - User registers the LP position as collateral in `ReQuardLending`.
   - Lending protocol tracks the initial collateral value and sets debt capacity.

2. **Borrowing**
   - User borrows assets against their LP‑backed collateral.
   - The system records the new debt and updates the health factor.

3. **Monitoring**
   - Any price movement or LP change that affects collateral value:
     - Causes `ReQuardHook` to recalculate the health factor.
     - Triggers a `PositionHealthUpdated` event on Base Sepolia.
   - Reactive Network relays this event to `ReQuardReactive` on Lasna.

4. **Trigger Decision**
   - `ReQuardReactive` checks if:
     - `healthFactor < minHealthFactor`.
   - If the position is unsafe:
     - `ReQuardReactive` emits a callback instruction with:
       - Identifiers for the position.
       - Any parameters needed to unwind the LP and repay the loan.

5. **Callback Execution**
   - Reactive Network sends a transaction on Base Sepolia to `ReQuardDestination`.
   - `ReQuardDestination`:
     - Validates the call.
     - Calls `ReQuardHook` to liquidate the position.

6. **Liquidation**
   - `ReQuardHook` unwinds the LP position:
     - Withdraws underlying tokens.
     - Repays as much debt as possible in `ReQuardLending`.
   - Any excess (liquidation fees) is redistributed to LPs according to the protocol rules.

7. **Post-Liquidation State**
   - `ReQuardLending` updates the position record (closed or reduced).
   - The system remains ready for the next event and cycle.

---

## Configuration Parameters

Key parameters that affect behavior:

- **`minHealthFactor`**
  - Set in `ReQuardReactive` constructor.
  - Controls conservativeness of liquidations.

- **`callbackGasLimit`**
  - Also configured during deployment of `ReQuardReactive`.
  - Must be high enough to cover:
    - Unwinding LP positions.
    - Debt repayment.
    - Any accounting or fee distribution logic.

- **Origin / Destination Chain IDs**
  - In this reference implementation:
    - Origin: Base Sepolia (`84531`).
    - Destination: Base Sepolia (`84531`).
  - Can be adapted for true cross‑chain builds (e.g. origin ≠ destination).

---

## Extensibility & Variations

ReQuard’s architecture is intentionally modular:

- You can swap out:
  - The lending logic in `ReQuardLending`.
  - The liquidation mechanics in `ReQuardHook`.
  - The decision logic in `ReQuardReactive`.

Potential extensions include:

- Using **different collateral sources** (e.g. other LP tokens, vault tokens).
- Supporting **multiple pools and hooks** with different thresholds.
- Implementing **time‑based triggers** (e.g. forced rebalancing, periodic fee sweeping).
- Extending `ReQuardReactive` to:
  - Consider oracles, TWAPs, or volatility metrics.
  - Manage more complex portfolios across chains.

