// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title ReQuardHook
/// @notice Simplified Uniswap V4-style hook that:
///         - tracks LP-backed collateral positions
///         - exposes a liquidation entrypoint that can be called by a
///           destination contract triggered by Reactive Network.
///
/// NOTE: This file intentionally abstracts away the real Uniswap V4 hook
/// interfaces so that we can focus on the Reactive Network integration
/// pattern. In a full implementation you would:
///   - import the official Uniswap V4 hook interface
///   - wire this hook into a real V4 pool
///   - replace the stubbed unwind/repay logic with actual AMM + lending ops.
contract ReQuardHook {
    /// @dev Basic representation of a collateralized LP position.
    struct Position {
        address owner;
        uint256 collateralValue; // e.g. in some unit (USD or token-denominated)
        uint256 debtValue;
        bool liquidated;
    }

    /// @notice Emitted whenever a position's health changes and needs to be
    ///         observed by the Reactive Contract.
    /// @dev This is the event that the Reactive Contract will subscribe to
    ///      via Reactive Network.
    event PositionHealthUpdated(
        bytes32 indexed positionId,
        address indexed owner,
        uint256 collateralValue,
        uint256 debtValue,
        uint256 healthFactor
    );

    /// @notice Emitted when a position is liquidated through the hook.
    /// @dev Liquidation fees are captured here and can be redistributed to LPs.
    event PositionLiquidated(
        bytes32 indexed positionId,
        address indexed owner,
        uint256 repaidDebt,
        uint256 remainingCollateral,
        uint256 liquidationFee
    );

    mapping(bytes32 => Position) public positions;

    /// @dev Address of the destination liquidation executor contract that is
    ///      authorized to call `liquidatePosition`. This contract will be the
    ///      one that Reactive Network calls into.
    address public liquidationExecutor;

    modifier onlyLiquidationExecutor() {
        require(msg.sender == liquidationExecutor, "not executor");
        _;
    }

    constructor(address _liquidationExecutor) {
        liquidationExecutor = _liquidationExecutor;
    }

    /// @notice Hook-style function to register or update an LP-backed position.
    /// @dev In a real Uniswap V4 hook this would be invoked as part of the
    ///      swap/mint/burn workflow.
    function upsertPosition(
        bytes32 positionId,
        address owner,
        uint256 collateralValue,
        uint256 debtValue
    ) external {
        positions[positionId] = Position({
            owner: owner,
            collateralValue: collateralValue,
            debtValue: debtValue,
            liquidated: positions[positionId].liquidated
        });

        uint256 healthFactor = _computeHealthFactor(collateralValue, debtValue);

        emit PositionHealthUpdated(
            positionId,
            owner,
            collateralValue,
            debtValue,
            healthFactor
        );
    }

    /// @notice Called by the destination executor when the Reactive Contract
    ///         decides that a position must be liquidated.
    /// @param positionId The identifier of the LP-backed collateral position.
    /// @dev For the purposes of this repo we stub the actual AMM + lending
    ///      interactions and simply mark the position as liquidated and
    ///      emit an event that would conceptually redistribute fees to LPs.
    function liquidatePosition(bytes32 positionId)
        external
        onlyLiquidationExecutor
    {
        Position storage pos = positions[positionId];
        require(!pos.liquidated, "already liquidated");
        require(pos.owner != address(0), "unknown position");

        // In a real implementation, this function would:
        //  1. Unwind the LP position in the Uniswap V4 pool.
        //  2. Use the proceeds to repay the associated debt.
        //  3. Capture a liquidation fee that can be routed back to LPs.

        uint256 repaidDebt = pos.debtValue;
        uint256 remainingCollateral = 0;
        uint256 liquidationFee = (pos.collateralValue * 5) / 1000; // e.g. 0.5%

        pos.liquidated = true;
        pos.collateralValue = remainingCollateral;
        pos.debtValue = 0;

        emit PositionLiquidated(
            positionId,
            pos.owner,
            repaidDebt,
            remainingCollateral,
            liquidationFee
        );
    }

    /// @dev Simple placeholder health factor computation.
    ///      In practice, health factor may depend on oracle prices, risk
    ///      parameters, etc.
    function _computeHealthFactor(uint256 collateralValue, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        if (debtValue == 0) return type(uint256).max;
        return (collateralValue * 1e18) / debtValue;
    }
}

