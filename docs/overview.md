## ReQuard Overview

**ReQuard** is an autonomous liquidation system built on top of **Uniswap V4 hooks** and the **Reactive Network**.
It allows LP-backed lending positions to be monitored and liquidated automatically **without keeper bots or manual intervention**.

At a high level:

- **LP positions** in a Uniswap V4 pool are used as **collateral** in a minimal lending protocol.
- A **Reactive Contract** continuously evaluates the health of each collateralized position.
- When a position’s **health factor** falls below a configurable threshold, the system:
  - Unwinds the LP position,
  - Repays the outstanding debt, and
  - Distributes liquidation fees back to LPs as additional yield.

This turns ReQuard into an **infrastructure primitive** for safer, more capital‑efficient on-chain lending against LP positions.

---

## Problem & Motivation

Traditional on-chain lending protocols generally rely on:

- **Keeper bots** to monitor positions and submit liquidation transactions.
- **User vigilance** to avoid undercollateralization.

This creates several issues:

- **Keeper dependency**: If keeper incentive markets fail (e.g. gas spikes, network congestion), liquidations can be delayed.
- **Bad debt risk**: Slow or missed liquidations can leave protocols with insolvent positions.
- **Operational complexity**: Running or integrating with reliable keeper infrastructure is non-trivial.

ReQuard removes this dependency by using **Reactive Contracts** as a programmable automation and monitoring layer:

- Monitoring is **continuous** and **off-chain**, but
- Enforcement (liquidation) is **on-chain** and **trustless**.

---

## High-Level Architecture

ReQuard spans two environments:

- **Origin / Destination Chain (Base Sepolia in this repo)**
  - Hosts the Uniswap V4 pool and the ReQuard protocol contracts.
  - LP positions and lending positions live here.

- **Reactive Network (Lasna Testnet)**
  - Hosts the **Reactive Contract** (`ReQuardReactive`).
  - Subscribes to on-chain events from Base Sepolia.
  - Triggers callbacks back to Base Sepolia when conditions are met.

Key components:

- **`ReQuardLending`** – minimal lending protocol that:
  - Accepts LP positions as collateral.
  - Tracks each position’s debt and collateral value.
  - Exposes liquidation functionality.

- **`ReQuardHook`** – Uniswap V4 hook that:
  - Observes LP position changes.
  - Emits `PositionHealthUpdated` events.
  - Performs the actual unwinding and liquidation of positions.

- **`ReQuardDestination`** – destination contract on Base Sepolia:
  - Receives callbacks initiated from the Reactive Network.
  - Calls the hook’s liquidation function for a specific position.

- **`ReQuardReactive`** – Reactive Contract on Reactive Network:
  - Subscribes to `PositionHealthUpdated` events.
  - Computes / checks health factors against thresholds.
  - Emits callback requests to `ReQuardDestination` when liquidations are needed.

---

## Core Concepts

### Health Factor

- Each collateralized position has a **health factor** $H$ representing the relative safety of the position.
- The default configuration is:
  - **Minimum health factor**: `1.2e18` (120%).
  - If $H < 1.2$, the position becomes eligible for liquidation.

The protocols in this repository:

- Track and emit the current health factor,
- Use it as the primary trigger for liquidation,
- Allow configuration via deployment parameters.

### Autonomous Liquidation

Liquidation is fully automated:

1. The hook emits `PositionHealthUpdated` whenever:
   - Prices move, or
   - Positions are adjusted.
2. `ReQuardReactive` receives event data via the Reactive Network subscription.
3. If the health factor is below the threshold:
   - `ReQuardReactive` prepares a callback execution.
   - The Reactive Network submits a transaction to `ReQuardDestination` on Base Sepolia.
4. `ReQuardDestination` calls into `ReQuardHook` to:
   - Unwind the LP position.
   - Repay the debt in `ReQuardLending`.
   - Distribute liquidation fees to LPs.

This removes the need for:

- External bots,
- Crons,
- Manually-maintained keeper infrastructure.

---

## User & Integrator Personas

- **LPs / Borrowers**
  - Provide liquidity in the Uniswap V4 pool with the ReQuard hook.
  - Register their LP positions as collateral in `ReQuardLending`.
  - Borrow against these positions.
  - Benefit from **predictable, automated risk management**.

- **Protocol Integrators**
  - Can reuse the ReQuard pattern for other pools or chains.
  - Can adjust health factor thresholds, callback gas limits, and event filters.
  - Can plug into the Reactive Network for other cross‑chain or time‑based automations.

- **Reactive Network Developers**
  - Use `ReQuardReactive` as a reference for:
    - Subscribing to on-chain events.
    - Emitting callbacks.
    - Coordinating actions across chains.

---

## When to Use ReQuard

ReQuard is useful if you need:

- Automated safety rails for **LP‑backed lending**, particularly on volatile or concentrated liquidity pools.
- A **decentralized, protocol‑level replacement for keeper bots**.
- A reference architecture for **event-driven automation** across chains using Reactive Network + Uniswap V4 hooks.

It is **not** intended to be a full-featured production lending protocol out of the box, but rather:

- A **minimal, focused implementation**,
- Designed for experimentation, extension, and integration.

