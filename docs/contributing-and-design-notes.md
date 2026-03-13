## Contributing & Design Notes

This document captures design considerations, non‑obvious trade‑offs, and guidelines for contributors extending ReQuard.

---

## Project Goals

- Provide a **clear reference implementation** of:
  - A Uniswap V4 hook,
  - A minimal LP‑backed lending protocol,
  - A Reactive Contract that automates liquidations.
- Showcase how **Reactive Network** can remove keeper dependencies.
- Stay **minimal but realistic**:
  - Enough detail to be instructive.
  - Not a full‑blown production protocol.

---

## Design Principles

- **Modularity**
  - Keep lending, hook logic, and Reactive logic separated into distinct contracts.
  - Make it easy to swap out:
    - Collateral types.
    - Liquidation strategies.
    - Trigger conditions.

- **Clarity Over Cleverness**
  - Favor explicit, commented logic over micro‑optimizations.
  - Use descriptive names for events, variables, and functions.

- **Deterministic Triggers**
  - Liquidation decisions should be based on transparent, on‑chain data (health factor).
  - Avoid introducing opaque off‑chain heuristics in the reference implementation.

- **Security Awareness**
  - Restrict external entrypoints (`ReQuardDestination`, liquidation functions).
  - Consider reentrancy, price manipulation, and oracle risk when modifying logic.

---

## Extending the Protocol

If you want to extend or modify ReQuard, consider the following areas:

### 1. Collateral & Lending Logic

- **Add new collateral types**
  - Additional LP pools.
  - Non‑LP assets (vault shares, other yield‑bearing tokens).

- **Improve risk models**
  - More nuanced health factor formulas.
  - Per‑asset risk parameters (LTVs, liquidation bonuses).
  - Time‑weighted or volatility‑aware thresholds.

- **Enhance accounting**
  - Interest accrual.
  - Fee sharing models (protocol fees, guardians, etc.).

When changing lending logic:

- Ensure `ReQuardHook` and `ReQuardReactive` are still receiving and interpreting the right values.
- Maintain backward compatibility or document breaking changes in `docs/contracts.md`.

### 2. Hook Behavior

- **Custom fee routing**
  - Direct liquidation proceeds to specialized fee receivers.
  - Support multi‑token distribution strategies.

- **Advanced hooks**
  - Implement more Uniswap V4 hook callbacks (`beforeSwap`, `afterSwap`, etc.).
  - Add safeguards that block actions that would instantly make positions unsafe.

Ensure that:

- Hook changes do not violate Uniswap invariants.
- Hook functions are gas‑efficient enough for real‑world usage.

### 3. Reactive Logic & Automation

- **More complex trigger conditions**
  - Use moving averages or TWAP‑based health metrics.
  - Incorporate off‑chain risk metrics into decision‑making (while keeping final enforcement on‑chain).

- **Multiple destinations or chains**
  - Use different `destinationChainId` or `destinationContract` values.
  - Route callbacks to multiple protocols (e.g. rebalancing, hedging).

Document any new Reactive patterns you introduce so others can build on them.

---

## Development Workflow

### Setup

1. Install Foundry.
2. Install dependencies (e.g. `forge-std` under `lib/` is already checked in).
3. Build and test:

```bash
forge build
forge test
```

### Suggested Branch Flow

- Use feature branches for changes:
  - `feat/...`, `fix/...`, `docs/...`, etc.
- Keep PRs:
  - Focused on a single concern.
  - Accompanied by updates to relevant docs in `docs/`.

---

## Testing Guidelines

- **Unit tests**
  - Focus on:
    - Lending logic (health factor, liquidation).
    - Hook behavior on position changes.

- **Integration tests**
  - Simulate:
    - LP creation and registration.
    - Borrowing and leveraging.
    - Price movements leading to undercollateralization.
    - Liquidations triggered via the Reactive flow (as much as is practical in local tests).

- Aim for:
  - Clear test names.
  - Separate happy‑path and failure‑path tests.

---

## Security & Review Checklist

Before considering any change “production‑like”, review:

- **Access Control**
  - Who can call:
    - Liquidation functions.
    - Administrative setters (thresholds, gas limits, addresses).

- **Reentrancy & External Calls**
  - Everywhere external calls occur:
    - From hooks to lending contracts.
    - From destination to hooks.

- **Economic Safety**
  - Are there paths where:
    - A user can under‑repay or escape liquidation?
    - A malicious actor can force wrong liquidations?

- **Upgrade & Migration**
  - For a simple reference, upgrades are likely out of scope.
  - If you add upgradeability, document and test it thoroughly.

---

## Documentation Expectations

When you add or change functionality, please:

- Update or create relevant docs under `docs/`, such as:
  - `architecture.md`
  - `contracts.md`
  - `deployment-and-usage.md`
  - New docs for any major feature families.
- Keep `README.md` as a **high‑level entrypoint**, and defer deeper details to `docs/`.

This will help new contributors and integrators understand the project quickly.

