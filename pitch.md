    ## ReQuard – Autonomous MEV-Triggered Liquidation Hook for Uniswap V4

    ReQuard is a Uniswap V4-native liquidation infrastructure that uses Reactive Network’s Reactive Contracts to autonomously monitor LP-backed lending positions and execute liquidations the instant a position’s health factor deteriorates below a safe threshold — **without keeper bots, cron jobs, or manual intervention**. It turns Uniswap V4 hooks into a real-time risk engine that makes lending against LP collateral safer, more capital efficient, and significantly more automated.
    
    ReQuard integrates Reactive Network by using Reactive Contracts to subscribe to `PositionHealthUpdated` events emitted by `ReQuardHook` on Base Sepolia, continuously evaluate each LP-backed position against deterministic health-factor thresholds, and automatically trigger cross-chain callbacks to `ReQuardDestination`, which then invokes `ReQuardHook` and `ReQuardLending` to execute immediate on-chain liquidation without keeper bots, cron jobs, or manual intervention.

    ---

    ## Description & High-Level Overview

    **ReQuard** is composed of:
    - **ReQuardHook** – a Uniswap V4 hook deployed alongside a pool, responsible for tracking LP positions, computing health factors, and unwinding positions on liquidation.
    - **ReQuardLending** – a minimal lending protocol that treats Uniswap V4 LP positions as collateral, tracks borrow balances, and exposes liquidation entrypoints.
    - **ReQuardReactive** – a Reactive Contract on Reactive Network that continuously listens to on-chain signals from the hook and determines when a liquidation should be triggered.
    - **ReQuardDestination** – a destination contract on Base Sepolia that receives callbacks from Reactive Network and executes the actual liquidation on-chain.

    End-to-end, the system:
    1. Lets users post Uniswap V4 LP positions as collateral and borrow against them.
    2. Continuously monitors position health (based on price and collateral value).
    3. Automatically liquidates unhealthy positions by unwinding LP and repaying debt.
    4. Redistributes liquidation fees back to LPs, making the system self-sustaining and aligned with liquidity providers.

    ---

    ## Problem Statement

    - **Keeper dependency and latency**: Traditional DeFi liquidations rely on external keeper bots polling for undercollateralized positions. This introduces:
    - Latency between a position becoming unsafe and a liquidation transaction.
    - Operational overhead in running and incentivizing keepers.
    - Failure modes where keepers don’t show up, leading to bad debt.

    - **LP-backed lending risk**: Lending against LP positions (especially Uniswap V4) is attractive but complex:
    - LP value is path-dependent and sensitive to volatility.
    - Health factor must be recalculated frequently as pool state changes.
    - Existing systems are not optimized for real-time risk on LP collateral.

    - **Fragmented cross-chain and off-chain automation**: Existing automation tools are:
    - Chain-specific or tied to specialized keeper networks.
    - Hard to generalize across chains and protocols without bespoke integrations.

    **Core problem**: There is no **general-purpose, autonomous liquidation primitive** for Uniswap V4 LP-backed loans that:
    - Reacts immediately to price and position state changes.
    - Operates without bespoke keeper bots.
    - Is robust, composable, and programmable using standard smart contract patterns.

    ---

    ## Solution

    ReQuard introduces a **Reactive Contract-driven Uniswap V4 hook** that:

    - **Directly monitors LP-backed lending positions**:
    - The hook has visibility into LP positions (via the Uniswap V4 pool state and position accounting).
    - A minimal lending protocol (`ReQuardLending`) tracks borrow balances and links them to LP collateral.

    - **Emits structured health events**:
    - On each relevant pool interaction or position update, the hook computes a **health factor** for each collateralized LP position.
    - It emits a `PositionHealthUpdated` event containing position ID, health factor, and collateral metadata.

    - **Uses Reactive Network to watch and react**:
    - A Reactive Contract (`ReQuardReactive`) on Reactive Network subscribes to the hook’s events on Base Sepolia.
    - Off-chain infrastructure continuously monitors these events and applies deterministic conditions:
        - If `healthFactor < threshold` (e.g., `1.2e18`), it emits a `Callback` event targeting the destination chain (Base Sepolia).

    - **Triggers on-chain liquidation with no keepers**:
    - `ReQuardDestination` receives the callback from Reactive Network.
    - It calls into `ReQuardHook` / `ReQuardLending` to execute liquidation:
        - Unwind LP position.
        - Repay debt directly from collateral.
        - Collect liquidation fees and redistribute them to remaining LPs.

    The result is a **self-triggering liquidation system** that removes keeper complexity, reduces bad debt risk, and offers a plug-and-play building block for LP-backed lending.

    ---

    ## Deep Technical Architecture

    ### On-Chain Components (Base Sepolia)

    - **`ReQuardHook` (Uniswap V4 Hook)**
    - Implements the Uniswap V4 `IHooks` interface.
    - Is attached to a Uniswap V4 pool at deployment time.
    - Responsibilities:
        - Track LP positions that are registered as collateral.
        - On position updates, derive the **collateral value** using the current pool price and liquidity ranges.
        - Compute a **health factor**: $HF = \\frac{CollateralValue}{DebtValue} \\times scaling$.
        - Emit `PositionHealthUpdated` events for positions whose state changes.
        - Expose a liquidation entrypoint callable only by the authorized destination contract.
        - When invoked for liquidation:
        - Unwind the LP position (burn liquidity, collect underlying tokens).
        - Transfer tokens to `ReQuardLending` to repay debt.
        - Distribute any residual value as liquidation fees to LPs.

    - **`ReQuardLending` (Minimal Lending Protocol)**
    - Maintains:
        - A mapping from **position IDs** (Uniswap V4 LP positions) to **borrow positions**.
        - Debt balances and interest logic (minimal for demo; extendable).
    - Functions:
        - **Register collateral**: Link a Uniswap V4 LP position with a borrowing position.
        - **Borrow**: Let users borrow against their LP collateral.
        - **Repay / liquidate**: Update debt balances when liquidation is executed via the hook.
    - Integration:
        - Trusts the hook as the canonical source of collateral valuation.
        - Exposes the data structures needed to compute health factors and liquidation conditions.

    - **`ReQuardDestination` (Reactive Network Destination Contract)**
    - Deployed on Base Sepolia.
    - Authorized receiver of callbacks from Reactive Network.
    - Responsibilities:
        - Verify that callbacks come from the expected Reactive Network relayer / bridge mechanism.
        - Decode callback payloads (position ID, action type, metadata).
        - Forward liquidation calls to the hook / lending contract with correct parameters.

    ### Reactive Network Components (Lasna Testnet)

    - **`ReQuardReactive` (Reactive Contract)**
    - Deployed on the Reactive Network Lasna Testnet.
    - Subscribes to `PositionHealthUpdated` events emitted by `ReQuardHook` on Base Sepolia.
    - Encodes **reactivity logic**:
        - Filtering: Only consider events for positions that are collateralized and have non-zero debt.
        - Thresholding: If `healthFactor < threshold` (e.g., 1.2), mark the position as needing liquidation.
        - Idempotency: Avoid duplicate callbacks for the same position unless its state improves and deteriorates again.
    - When a liquidation condition is met:
        - Emits a `Callback` event targeting `ReQuardDestination` on Base Sepolia.
        - Includes payload: position ID, relevant metadata, and gas limits (e.g., 500,000 gas).

    - **Reactive Network Infrastructure**
    - Off-chain nodes monitor Base Sepolia for the hook’s events.
    - When conditions encoded in `ReQuardReactive` are satisfied, they automatically submit a transaction to `ReQuardDestination` on Base Sepolia.
    - This creates a **cross-chain event → callback** loop with deterministic, programmable behavior.

    ### Data & Event Flow

    1. **User supplies LP and borrows**
    - User opens a Uniswap V4 LP position in a pool with `ReQuardHook` attached.
    - User registers the LP position as collateral in `ReQuardLending` and borrows assets.

    2. **Pool state changes**
    - Any relevant Uniswap V4 action (swap, mint, burn, fee accumulation) can impact LP value.
    - `ReQuardHook` is triggered through its hook callbacks.

    3. **Health factor computation**
    - `ReQuardHook`:
        - Reads pool state and position liquidity.
        - Derives collateral value and fetches associated debt.
        - Computes current health factor.
        - Emits `PositionHealthUpdated(positionId, healthFactor, …)` on Base Sepolia.

    4. **Reactive monitoring**
    - `ReQuardReactive` on Reactive Network:
        - Subscribes to `PositionHealthUpdated` events.
        - Maintains internal state / rules about which positions are at risk.
        - If `healthFactor < threshold`:
        - Emits `Callback` targeting `ReQuardDestination` on Base Sepolia with the relevant position ID.

    5. **On-chain liquidation execution**
    - Reactive Network infrastructure:
        - Picks up the `Callback` event.
        - Submits a transaction to `ReQuardDestination` on Base Sepolia (with configured gas limit).
    - `ReQuardDestination`:
        - Validates origin and payload.
        - Invokes `ReQuardHook` / `ReQuardLending` to perform liquidation for `positionId`.
    - `ReQuardHook`:
        - Unwinds the LP position.
        - Transfers underlying tokens to `ReQuardLending` to repay the debt.
        - Distributes liquidation fees to LPs.

    ---

    ## Market Opportunity & Scalability

    - **Growing demand for LP-backed credit**:
    - Uniswap V4 enables more expressive LP positions (customizable curves, hooks).
    - There is a large unmet need to **borrow against LPs** without assuming excessive liquidation risk.
    - ReQuard can be the **standard module** for LP-backed risk management.

    - **Generalizable primitive**:
    - The architecture is not limited to a single pool or asset pair.
    - Any Uniswap V4 pool that supports hooks can integrate ReQuard as a risk and liquidation layer.
    - The same pattern extends to other chains and pool configurations as Uniswap V4 is deployed cross-chain.

    - **Scalability via Reactive Network**:
    - Monitoring and triggering logic is offloaded to Reactive Network’s Reactive Contracts.
    - As the number of tracked positions grows, scaling is primarily a function of:
        - Event volume from `PositionHealthUpdated`.
        - Reactive Network’s ability to process and dispatch callbacks.
    - This is **more scalable than per-protocol keeper fleets**, since the automation is shared, programmable infrastructure.

    - **Composable DeFi building block**:
    - Protocols can integrate ReQuard’s hook and lending contracts as a **module**, rather than rebuilding liquidations.
    - Enables new products:
        - Auto-hedged LP lending markets.
        - Cross-chain LP-backed debt with unified risk management.
        - Structured products that rely on precise liquidation guarantees.

    ---

    ## Technical Competitive Advantage

    - **Reactive Contract-native design**:
    - Instead of bolting on keepers, ReQuard is designed around Reactive Network from day one.
    - Liquidation conditions are encoded directly as Reactive Contract logic, making them:
        - Verifiable on-chain (on Reactive Network).
        - Upgradable via well-defined smart contract patterns.

    - **Hook-level visibility and control**:
    - Operating at the Uniswap V4 hook layer gives ReQuard **first-class access** to:
        - Pool state.
        - LP positions.
        - Swap / mint / burn flows.
    - This allows for more accurate, lower-latency health calculations than external oracles or off-chain risk engines.

    - **Autonomous, deterministic execution**:
    - No reliance on off-chain bots with opaque logic.
    - Trigger conditions are transparent and encoded in smart contracts.
    - Cross-chain execution path (Base Sepolia ↔ Reactive Network Lasna) is deterministic and parameterized (e.g., gas limits).

    - **Fee-aligned incentives**:
    - Liquidation fees are captured and redistributed to LPs, providing:
        - Economic incentive to route liquidity through ReQuard-enabled pools.
        - A self-sustaining reward loop for providing collateral that can be safely liquidated.

    ---

    ## Technical Components & Integration Points

    - **Uniswap V4 Pool + `ReQuardHook`**
    - Deployed as a pool with hooks enabled.
    - Integration:
        - During pool deployment, specify `ReQuardHook` as the hook contract.
        - LPs interacting with the pool automatically pass through hook logic.

    - **`ReQuardLending`**
    - Minimal lending protocol that:
        - Accepts LP positions as collateral.
        - Tracks borrow balances and provides the data needed to compute health factors.
    - Integration:
        - Other protocols can wrap or extend `ReQuardLending`.
        - Risk parameters (LTV, threshold, interest) are configurable per market.

    - **`ReQuardDestination`**
    - The on-chain endpoint that Reactive Network calls.
    - Integration:
        - Whitelisted to call liquidation functions on the hook / lending contract.
        - Configured with gas limits (e.g., 500,000) and security checks.

    - **`ReQuardReactive` (Reactive Contract on Lasna)**
    - Encodes the monitoring and triggering logic.
    - Integration:
        - Subscribed to `PositionHealthUpdated` events from Base Sepolia.
        - Configured with:
        - Source chain ID: `84531` (Base Sepolia).
        - Destination chain ID: `84531` (for callbacks to the same chain) or cross-chain if extended.
        - Thresholds and callback parameters.

    - **Reactive Network Subscription**
    - Off-chain configuration that binds:
        - Source: Base Sepolia, `ReQuardHook` contract, `PositionHealthUpdated` event.
        - Reactive Contract: `ReQuardReactive` on Lasna.
        - Destination: Base Sepolia, `ReQuardDestination` contract, callback selector.

    ---

    ## How the Hook Works (Step-by-Step)

    1. **Hook deployment and pool setup**
    - A Uniswap V4 pool is created with `ReQuardHook` attached.
    - The hook implements required interfaces to receive callbacks on key pool actions (e.g., swaps, mints, burns).

    2. **Position registration**
    - A user opens an LP position in this pool.
    - The user then:
        - Registers the position as collateral in `ReQuardLending`.
        - Takes out a borrow against this LP-backed collateral.
    - `ReQuardLending` tracks the relationship between `positionId`, collateral, and debt.

    3. **Ongoing monitoring via hook callbacks**
    - Whenever:
        - The user adjusts liquidity.
        - Other traders swap through the pool (changing price).
        - Fees accumulate.
    - Uniswap V4 invokes the hook’s callbacks.
    - Inside these callbacks, `ReQuardHook`:
        - Fetches the latest pool state and position data.
        - Recomputes the position’s collateral value and health factor.
        - Emits a `PositionHealthUpdated` event with:
        - `positionId`
        - `healthFactor`
        - Additional metadata (e.g., timestamps, collateral and debt data).

    4. **Reactive Contract decisioning**
    - The Reactive Contract (`ReQuardReactive`) subscribed to these events:
        - Receives `PositionHealthUpdated`.
        - Checks if the health factor is below the configured threshold (e.g., `1.2e18`).
        - If below:
        - Emits a `Callback` event targeting `ReQuardDestination` on Base Sepolia, including the `positionId` and other needed data.

    5. **Callback and liquidation execution**
    - Reactive Network infrastructure:
        - Observes the `Callback` event.
        - Submits a transaction to `ReQuardDestination` on Base Sepolia with the encoded payload and gas limit (e.g., `500000`).
    - `ReQuardDestination`:
        - Validates the call’s authenticity.
        - Calls `ReQuardHook` / `ReQuardLending` to trigger liquidation for the specified `positionId`.
    - Inside the hook’s liquidation logic:
        - The LP position is unwound by burning liquidity and collecting underlying tokens.
        - Proceeds are used by `ReQuardLending` to repay the outstanding debt.
        - Any surplus is distributed as liquidation fees to remaining LPs, aligning incentives.

    6. **System convergence**
    - After liquidation, the position is no longer undercollateralized.
    - Future `PositionHealthUpdated` events for this position will reflect that it has been closed or restored to a safe state.

    ---

    ## Summary

    ReQuard is a **Reactive Network-powered Uniswap V4 liquidation hook** that transforms LP-backed lending from a keeper-dependent, latency-prone process into a **fully autonomous, event-driven risk engine**. By combining Uniswap V4 hooks, a minimal lending protocol, and Reactive Contracts for cross-chain automation, it offers a scalable, composable, and technically differentiated solution for real-time liquidations — with incentives that naturally reward LPs and make on-chain lending safer by design.

