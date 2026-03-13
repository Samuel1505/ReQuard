## Deployment & Usage Guide

This document walks through building, deploying, and using ReQuard with Base Sepolia and Reactive Network.
It complements `README.md` and `REACTIVE_SETUP.md`.

---

## 1. Prerequisites

- **Tooling**
  - [Foundry](https://book.getfoundry.sh/) installed (`forge`, `cast`, `anvil`).
  - Access to a **Base Sepolia** RPC endpoint.
  - Access to a **Reactive Network – Lasna Testnet** endpoint.

- **Accounts & Keys**
  - A funded EOA (private key) with:
    - Base Sepolia ETH for gas.
    - Permissions to deploy contracts.
  - An account suitable for deploying to Reactive Network.

- **Environment**
  - Create and configure a `.env` (see `.env.example` if present) with:
    - `BASE_SEPOLIA_RPC_URL`
    - `PRIVATE_KEY` / `DEPLOYER_KEY` or similar.
    - Any required Reactive Network credentials.

---

## 2. Build & Test Locally

From the repository root:

```bash
forge build
forge test
```

Confirm that tests pass before deploying to any public testnet.

---

## 3. Deploy to Base Sepolia

ReQuard uses a Foundry script to deploy the Base Sepolia contracts.

### 3.1 Run the Deployment Script

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

This script should:

- Deploy:
  - `ReQuardLending`
  - `ReQuardHook`
  - `ReQuardDestination`
- Optionally configure:
  - Initial parameters for the lending protocol.
  - Uniswap V4 pool with the ReQuard hook.

### 3.2 Record Deployed Addresses

After deployment, make sure to save the addresses:

- `ReQuardLending` address
- `ReQuardHook` address
- `ReQuardDestination` address
- Any Uniswap V4 pool(s) associated with ReQuard

You will need the `ReQuardHook` and `ReQuardDestination` addresses for configuring Reactive Network.

---

## 4. Deploy `ReQuardReactive` on Reactive Network

Refer to `REACTIVE_SETUP.md` for deeper detail. The summary:

### 4.1 Compile & Deploy

- Compile the contracts for Reactive Network as usual (`forge build` already covers this).
- Deploy `ReQuardReactive` to **Lasna Testnet** (Chain ID: `5318007`).

**Constructor Arguments:**

- `originChainId` – `84531` (Base Sepolia).
- `destinationChainId` – `84531` (Base Sepolia in this reference).
- `destinationContract` – the deployed `ReQuardDestination` address.
- `minHealthFactor` – typically `1.2e18` (120%).
- `callbackGasLimit` – e.g. `500000`.

Example (pseudocode; adapt to your deployment tooling):

```bash
forge create src/ReQuardReactive.sol:ReQuardReactive \
  --rpc-url $REACTIVE_RPC_URL \
  --private-key $REACTIVE_DEPLOYER_KEY \
  --constructor-args 84531 84531 $REQUARD_DESTINATION 1200000000000000000 500000
```

Record the `ReQuardReactive` address on Reactive Network.

---

## 5. Configure Reactive Network Subscription

### 5.1 Event Definition

ReQuard relies on the `PositionHealthUpdated` event from `ReQuardHook`:

```text
PositionHealthUpdated(
  bytes32 indexed positionId,
  address indexed owner,
  uint256 collateralValue,
  uint256 debtValue,
  uint256 healthFactor
)
```

The event topic (Keccak-256 hash of the signature) is:

```text
keccak256("PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)")
```

### 5.2 Subscription Parameters

When setting up a subscription in Reactive Network:

- **Origin Chain**: Base Sepolia (`84531`).
- **Target Contract**: `ReQuardHook` address on Base Sepolia.
- **Event Topic**: `keccak256("PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)")`.
- **Handler Function** on `ReQuardReactive`:
  - Something like `onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)` (see `REACTIVE_SETUP.md` and contract source).
- **Destination Chain**: Base Sepolia (`84531`).
- **Destination Contract**: `ReQuardDestination` address.

Consult the Reactive Network docs and UI/CLI for the exact steps to create this subscription.

---

## 6. Funding the Reactive Contract

Reactive Contracts must be funded to cover callback gas costs.

- Send native tokens on Reactive Network to the `ReQuardReactive` address.
- Use the tools provided by Reactive Network to:
  - Check contract balance.
  - Cover potential debt or top-up when needed.

Refer to:

- `REACTIVE_SETUP.md`
- Reactive Network documentation

for details on funding models and optional `coverDebt()` helpers.

---

## 7. Using ReQuard End-to-End

Once all pieces are deployed and configured:

### 7.1 Create & Register an LP Position

1. On Base Sepolia:
   - Provide liquidity to a Uniswap V4 pool configured with `ReQuardHook`.
2. Register the resulting LP position in `ReQuardLending`:
   - Call the relevant function to:
     - Associate the LP with your address.
     - Set up collateralization.

### 7.2 Borrow Against LP Collateral

1. From `ReQuardLending`, call the borrow function.
2. Ensure the initial health factor is safely above the minimum (e.g. > 1.5).

### 7.3 Let the System Monitor & Liquidate

- When market conditions change:
  - `ReQuardHook` emits `PositionHealthUpdated` with the new health factor.
  - `ReQuardReactive` evaluates whether to trigger liquidation.
- If `healthFactor < minHealthFactor`:
  - `ReQuardReactive` requests a callback.
  - Reactive Network calls `ReQuardDestination` on Base Sepolia.
  - `ReQuardDestination` instructs `ReQuardHook` to liquidate the position.

### 7.4 Verifying Behavior

- Use:
  - Base Sepolia block explorers to inspect:
    - `PositionHealthUpdated` events.
    - Liquidation transactions.
  - Reactive Network explorers (e.g. Reactscan) to:
    - Confirm subscription activity.
    - View callback executions and contract status.

---

## 8. Troubleshooting

Common issues and checks:

- **No callbacks firing**
  - Verify subscription configuration (origin chain, topics, target contract).
  - Ensure `ReQuardReactive` is deployed with correct `originChainId` and `destinationChainId`.
  - Confirm `ReQuardReactive` is funded.

- **Contract status shows as inactive on Reactive Network**
  - Typically indicates insufficient balance to pay for callbacks.
  - Top up the `ReQuardReactive` contract.

- **Health factor not changing**
  - Make sure `ReQuardHook` is actually installed for the pool you’re using.
  - Confirm that LP operations are going through the hooked pool.
  - Check that `PositionHealthUpdated` events are being emitted.

For deeper integration details, see:

- `REACTIVE_SETUP.md`
- `docs/architecture.md`
- `docs/contracts.md`

