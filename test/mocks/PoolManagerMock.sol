// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IHooks, IPoolManager} from "../../src/interfaces/IUniswapV4Hooks.sol";

/**
 * @dev Simplified Uniswap V4 PoolManager mock used by `ReQuardHook`.
 * It supports:
 * - getLiquidity (read from a mapping set by the test)
 * - modifyLiquidity (returns fixed deltas set by the test)
 */
contract PoolManagerMock is IPoolManager {
    mapping(bytes32 => uint128) public liquidityByParams;

    int256 public nextDelta0;
    int256 public nextDelta1;

    function setLiquidity(
        PoolKey memory key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt,
        uint128 liquidity
    ) external {
        liquidityByParams[_hash(key, owner, tickLower, tickUpper, salt)] = liquidity;
    }

    function setModifyLiquidityDeltas(int256 delta0, int256 delta1) external {
        nextDelta0 = delta0;
        nextDelta1 = delta1;
    }

    function _hash(
        PoolKey memory key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    key.currency0,
                    key.currency1,
                    key.fee,
                    key.tickSpacing,
                    address(key.hooks),
                    owner,
                    tickLower,
                    tickUpper,
                    salt
                )
            );
    }

    function modifyLiquidity(
        PoolKey memory /* key */,
        ModifyLiquidityParams memory /* params */,
        bytes calldata /* hookData */
    ) external override returns (int256, int256) {
        return (nextDelta0, nextDelta1);
    }

    function swap(
        PoolKey memory /* key */,
        SwapParams memory /* params */,
        bytes calldata /* hookData */
    ) external override returns (int256, int256) {
        revert("swap not implemented");
    }

    function getSlot0(PoolKey memory /* key */)
        external
        pure
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 hookFee)
    {
        sqrtPriceX96 = 0;
        tick = 0;
        protocolFee = 0;
        hookFee = 0;
    }

    function getLiquidity(
        PoolKey memory key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external view override returns (uint128) {
        return liquidityByParams[_hash(key, owner, tickLower, tickUpper, salt)];
    }
}

