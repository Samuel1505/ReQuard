# TRACK 1: Reactive Network

Reactive Contracts are the key differentiator here — they let you trigger on-chain logic based on off-chain or cross-chain events without manual intervention.

---

## 1. 🔴 ReGuard — Autonomous MEV-Triggered Liquidation Hook

**Novelty:**  
Liquidation hooks exist conceptually, but nobody has built one that self-triggers via Reactive Contracts without requiring a keeper bot.

---

## How it Works

- A lending position is collateralized by an LP position in a V4 pool.  
- A Reactive Contract monitors the pool's price continuously off-chain.  
- When collateral value drops below a health threshold, the Reactive Contract automatically calls the hook to liquidate the LP position and repay the debt — **no human keeper needed**.  
- The hook captures liquidation fees and redistributes them to LPs in the pool as an incentive.

---

## Impact

Eliminates keeper dependency, reduces bad debt risk, and makes on-chain lending safer and more capital efficient. This is **infrastructure-level impact**.

---

## Detailed Description

A **Uniswap V4 hook** that uses **Reactive Contracts** to autonomously monitor collateralized LP positions and trigger on-chain liquidations the moment a position's health factor drops below a safe threshold — **no keeper bots, no manual intervention**.

When a wallet's **LP-backed collateral** loses value, the Reactive Contract detects it in real time and calls the hook to:

1. Unwind the LP position  
2. Repay the associated debt automatically  

Liquidation fees captured by the hook are **redistributed to pool LPs as an additional yield incentive**, making the system **self-sustaining and aligned with liquidity providers**.

## Resources
- https://dev.reactive.network/
- https://dev.reactive.network/reactive-contracts
- https://github.com/Reactive-Network/reactive-smart-contract-demos

# Note
### How to think about using Reactive Network

Here’s how Reactive Network works: Reactive Smart Contracts (RSCs) let you monitor on-chain events on chain A and react to those events by triggering callbacks (submitting transactions) on another chain B (or chain A). This enables cross-chain automation and modularity, where your logic can respond to activity in existing smart contracts without modifying them. We believe that our technology will be especially useful when combined with Uniswap Hooks, supercharging them with time-based or conditional automations and cross-chain functionality.

To add reactivity to your smart contract setup, you will just need to deploy two additional Solidity smart contracts: on Reactive Network and on the destination chain.

### Hookathon Judging Guidance

For our prize track, we’ll be looking for the most innovative hooks that implement Reactive Smart Contracts correctly.