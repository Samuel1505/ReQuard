// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHooks, IPoolManager} from "./interfaces/IUniswapV4Hooks.sol";
import {ReQuardLending} from "./ReQuardLending.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @dev BalanceDelta represents the change in token balances after a swap or modifyLiquidity
struct BalanceDelta {
    int256 amount0;
    int256 amount1;
}

/// @title ReQuardHook
/// @notice Uniswap V4 hook that:
///         - Tracks LP positions used as collateral for lending
///         - Monitors position health factors
///         - Enables autonomous liquidation via Reactive Network
///         - Redistributes liquidation fees to LPs
contract ReQuardHook is IHooks {
    /// @dev Hook flags: enable beforeModifyPosition and afterModifyPosition callbacks
    uint256 public constant HOOK_PERMISSIONS = (1 << 0) // beforeModifyPosition
        | (1 << 1); // afterModifyPosition

    /// @dev Represents an LP position tracked by this hook
    struct LPPosition {
        address owner;
        IPoolManager.PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bytes32 salt;
        uint256 collateralValue; // Current USD value of the LP position
        bytes32 lendingPositionId; // Associated lending position ID
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

    /// @notice Emitted when an LP position is modified
    event LPPositionModified(
        bytes32 indexed positionId, address indexed owner, uint128 liquidity, uint256 collateralValue
    );

    /// @dev PoolManager instance
    IPoolManager public immutable poolManager;

    /// @dev Lending protocol instance
    ReQuardLending public immutable lending;

    /// @dev Address of the destination liquidation executor contract
    address public liquidationExecutor;

    /// @dev Mapping from position ID to LP position data
    mapping(bytes32 => LPPosition) public lpPositions;

    /// @dev Mapping from (owner, poolKey, tickLower, tickUpper, salt) to positionId
    mapping(address => mapping(bytes32 => bytes32)) public positionIds;

    /// @dev Liquidation fee in basis points (50 = 0.5%)
    uint256 public constant LIQUIDATION_FEE_BPS = 50;

    /// @dev Accumulated liquidation fees to be redistributed to LPs
    uint256 public accumulatedFees;

    modifier onlyLiquidationExecutor() {
        require(msg.sender == liquidationExecutor, "not executor");
        _;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager, address _lending, address _liquidationExecutor) {
        poolManager = IPoolManager(_poolManager);
        lending = ReQuardLending(_lending);
        liquidationExecutor = _liquidationExecutor;
    }

    /// @notice Returns hook permissions flags
    function getHookPermissions() external pure returns (uint256) {
        return HOOK_PERMISSIONS;
    }

    /// @notice Called before modifying liquidity in a pool
    /// @dev This hook callback is invoked by PoolManager before modifyLiquidity
    function beforeModifyPosition(
        address,
        /* owner */
        IPoolManager.PoolKey calldata,
        /* key */
        IPoolManager.ModifyLiquidityParams calldata,
        /* params */
        bytes calldata /* hookData */
    ) external view onlyPoolManager returns (bytes4) {
        // Extract position owner from hookData if provided
        // In production, this would come from the actual transaction context
        return this.beforeModifyPosition.selector;
    }

    /// @notice Called after modifying liquidity in a pool
    /// @dev This hook callback is invoked by PoolManager after modifyLiquidity
    function afterModifyPosition(
        address owner,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta memory,
        /* delta */
        bytes calldata /* hookData */
    ) external onlyPoolManager returns (bytes4) {
        // Generate position ID
        bytes32 positionId = keccak256(
            abi.encodePacked(
                owner, key.currency0, key.currency1, key.fee, params.tickLower, params.tickUpper, params.salt
            )
        );

        // Get current liquidity from pool
        uint128 currentLiquidity = poolManager.getLiquidity(key, owner, params.tickLower, params.tickUpper, params.salt);

        // Update or create LP position
        LPPosition storage lpPos = lpPositions[positionId];

        if (lpPos.owner == address(0)) {
            // New position
            lpPos.owner = owner;
            lpPos.poolKey = key;
            lpPos.tickLower = params.tickLower;
            lpPos.tickUpper = params.tickUpper;
            lpPos.salt = params.salt;
        }

        lpPos.liquidity = currentLiquidity;

        // Calculate collateral value based on liquidity and current price
        uint256 collateralValue = _calculateCollateralValue(key, currentLiquidity, params.tickLower, params.tickUpper);
        lpPos.collateralValue = collateralValue;

        // If this position is used as collateral, update lending protocol
        if (lpPos.lendingPositionId != bytes32(0)) {
            lending.updateCollateralValue(lpPos.lendingPositionId, collateralValue);

            // Get debt value from lending protocol
            ReQuardLending.Position memory lendingPos = lending.getPosition(lpPos.lendingPositionId);
            uint256 healthFactor = lending.getHealthFactor(lpPos.lendingPositionId);

            emit PositionHealthUpdated(
                lpPos.lendingPositionId, owner, collateralValue, lendingPos.borrowedAmount, healthFactor
            );
        }

        emit LPPositionModified(positionId, owner, currentLiquidity, collateralValue);

        return this.afterModifyPosition.selector;
    }

    /// @notice Register an LP position as collateral for a lending position
    function registerCollateral(bytes32 lpPositionId, bytes32 lendingPositionId) external {
        LPPosition storage lpPos = lpPositions[lpPositionId];
        require(lpPos.owner == msg.sender, "not owner");
        require(lpPos.lendingPositionId == bytes32(0), "already registered");
        require(!lpPos.liquidated, "position liquidated");

        lpPos.lendingPositionId = lendingPositionId;

        // Update lending protocol with initial collateral value
        lending.updateCollateralValue(lendingPositionId, lpPos.collateralValue);
    }

    /// @notice Called by the destination executor when the Reactive Contract
    ///         decides that a position must be liquidated.
    /// @param positionId The identifier of the LP-backed collateral position.
    function liquidatePosition(bytes32 positionId) external onlyLiquidationExecutor {
        LPPosition storage lpPos = lpPositions[positionId];
        require(!lpPos.liquidated, "already liquidated");
        require(lpPos.owner != address(0), "unknown position");
        require(lpPos.lendingPositionId != bytes32(0), "not collateralized");

        // Liquidate the lending position
        (uint256 repaidDebt, uint256 liquidationFee) = lending.liquidatePosition(lpPos.lendingPositionId);

        // Unwind the LP position
        uint256 remainingCollateral = _unwindLPPosition(lpPos);

        // Calculate liquidation fee (additional fee on top of lending protocol fee)
        uint256 hookLiquidationFee = (lpPos.collateralValue * LIQUIDATION_FEE_BPS) / 10000;
        accumulatedFees += hookLiquidationFee;

        lpPos.liquidated = true;
        lpPos.liquidity = 0;
        lpPos.collateralValue = 0;

        emit PositionLiquidated(
            positionId, lpPos.owner, repaidDebt, remainingCollateral, liquidationFee + hookLiquidationFee
        );
    }

    /// @notice Distribute accumulated liquidation fees to active LPs
    /// @dev This is a simplified version - in production, you'd track LP shares
    function distributeFeesToLPs(address token, uint256 amount) external {
        require(accumulatedFees >= amount, "insufficient fees");
        accumulatedFees -= amount;

        // In production, this would distribute proportionally to active LPs
        // For now, we'll just allow manual distribution
        IERC20(token).transfer(msg.sender, amount);
    }

    /// @dev Calculate collateral value of an LP position
    /// @dev Simplified calculation - in production, use oracle prices
    function _calculateCollateralValue(
        IPoolManager.PoolKey memory,
        /* key */
        uint128 liquidity,
        int24,
        /* tickLower */
        int24 /* tickUpper */
    )
        internal
        pure
        returns (uint256)
    {
        // Simplified value calculation based on liquidity and price range
        // In production, use proper Uniswap V4 math libraries and oracle prices
        if (liquidity == 0) return 0;

        // This is a placeholder - real implementation would use TickMath and LiquidityMath
        // For now, return a value proportional to liquidity
        return uint256(liquidity) * 1e10; // Simplified: liquidity * scaling factor
    }

    /// @dev Unwind an LP position by removing all liquidity
    function _unwindLPPosition(LPPosition memory lpPos) internal returns (uint256) {
        // Create modify liquidity params to remove all liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: lpPos.tickLower,
            tickUpper: lpPos.tickUpper,
            liquidityDelta: -int256(uint256(lpPos.liquidity)),
            salt: lpPos.salt
        });

        // Remove liquidity from pool
        (int256 delta0, int256 delta1) = poolManager.modifyLiquidity(lpPos.poolKey, params, "");

        // Return the value of tokens received (simplified)
        // In production, convert to USD using oracles
        return uint256(delta0 > 0 ? delta0 : -delta0) + uint256(delta1 > 0 ? delta1 : -delta1);
    }

    /// @dev Compute health factor
    function _computeHealthFactor(uint256 collateralValue, uint256 debtValue) internal pure returns (uint256) {
        if (debtValue == 0) return type(uint256).max;
        return (collateralValue * 1e18) / debtValue;
    }
}
