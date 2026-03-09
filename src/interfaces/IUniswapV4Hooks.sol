// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

/// @title IHooks
/// @notice Interface for hooks that can be called at various stages of a Uniswap V4 pool action
interface IHooks {
    /// @notice Hook flags that determine which hooks are enabled
    /// @dev Each bit represents a hook callback
    function getHookPermissions() external pure returns (uint256);
}

/// @title IPoolManager
/// @notice Interface for Uniswap V4 PoolManager
interface IPoolManager {
    struct PoolKey {
        uint160 currency0;
        uint160 currency1;
        uint24 fee;
        int24 tickSpacing;
        IHooks hooks;
    }

    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function modifyLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external returns (int256, int256);

    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) external returns (int256, int256);

    function getSlot0(
        PoolKey memory key
    ) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 hookFee);

    function getLiquidity(
        PoolKey memory key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external view returns (uint128);
}

/// @title ICurrencyManager
/// @notice Interface for managing currencies in Uniswap V4
interface ICurrencyManager {
    function settle(address currency) external payable returns (uint256 paid);

    function take(address currency, address from, uint256 amount) external;
}
