// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ReQuardHook, BalanceDelta} from "../src/ReQuardHook.sol";
import {ReQuardLending} from "../src/ReQuardLending.sol";
import {ReQuardReactive} from "../src/ReQuardReactive.sol";
import {ReQuardDestination} from "../src/ReQuardDestination.sol";
import {IPoolManager, IHooks} from "../src/interfaces/IUniswapV4Hooks.sol";

import {PoolManagerMock} from "./mocks/PoolManagerMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {HookLiquidationProxy} from "./mocks/HookLiquidationProxy.sol";

contract ReQuardIntegrationTest is Test {
    uint64 internal constant ORIGIN_CHAIN_ID = 84531;
    uint64 internal constant DEST_CHAIN_ID = 84531;
    uint256 internal constant MIN_HF = 1.2e18;
    uint64 internal constant CALLBACK_GAS_LIMIT = 500000;

    address internal constant REACTIVE_VM = address(0x123);
    address internal constant BORROWER = address(0xB0B);

    PoolManagerMock internal poolManager;
    ERC20Mock internal collateralToken;
    ERC20Mock internal debtToken;
    ReQuardLending internal lending;
    HookLiquidationProxy internal hookProxy;
    ReQuardDestination internal destination;
    ReQuardHook internal hook;

    IPoolManager.PoolKey internal key;
    IPoolManager.ModifyLiquidityParams internal params;
    bytes32 internal salt;

    function setUp() public {
        poolManager = new PoolManagerMock();

        collateralToken = new ERC20Mock("COLL", "COLL", 18);
        debtToken = new ERC20Mock("DEBT", "DEBT", 18);
        lending = new ReQuardLending(address(collateralToken), address(debtToken));

        // Deploy hook proxy + destination to avoid constructor circularity in tests.
        hookProxy = new HookLiquidationProxy();
        destination = new ReQuardDestination(REACTIVE_VM, address(hookProxy));

        // Deploy hook with liquidationExecutor == hookProxy, so destination->proxy->hook is authorized.
        hook = new ReQuardHook(address(poolManager), address(lending), address(hookProxy));
        hookProxy.setTarget(address(hook));

        // Hook calls into lending.liquidatePosition, so the hook must be the liquidator.
        lending.setLiquidator(address(hook));

        key = IPoolManager.PoolKey({
            currency0: uint160(0x100),
            currency1: uint160(0x200),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0x999))
        });

        salt = bytes32(uint256(0xABCDEF));
        params = IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 0, // not used by mock
            salt: salt
        });
    }

    function _positionId(address owner) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            owner,
            key.currency0,
            key.currency1,
            key.fee,
            params.tickLower,
            params.tickUpper,
            params.salt
        ));
    }

    function test_endToEnd_liquidationTriggeredByReactiveCallback() public {
        // Safe initial state: HF >= MIN_HEALTH_FACTOR.
        uint128 safeLiquidity = 100;
        uint256 collateralValueSafe = uint256(safeLiquidity) * 1e10;
        uint256 borrowedAmount = collateralValueSafe / 2;

        poolManager.setLiquidity(key, BORROWER, params.tickLower, params.tickUpper, salt, safeLiquidity);

        // 1) Create LP position (no health event yet because no collateral is linked).
        vm.prank(address(poolManager));
        hook.afterModifyPosition(BORROWER, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(BORROWER);
        bytes32 lendingPositionId = keccak256("lending-pos-1");
        lending.upsertPosition(lendingPositionId, BORROWER, lpPositionId, collateralValueSafe, borrowedAmount);

        // 2) Link LP collateral to lending so future afterModifyPosition emits health updates.
        vm.prank(BORROWER);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        // Deploy reactive contract observing the hook on origin chain.
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, address(destination), MIN_HF, CALLBACK_GAS_LIMIT);

        // 3) Make the position unhealthy by decreasing liquidity.
        uint128 unsafeLiquidity = 49; // collateralValue becomes < borrowedAmount
        uint256 collateralValueUnsafe = uint256(unsafeLiquidity) * 1e10;
        poolManager.setLiquidity(key, BORROWER, params.tickLower, params.tickUpper, salt, unsafeLiquidity);

        // Call afterModifyPosition again: hook should update lending collateral and emit a health event.
        vm.prank(address(poolManager));
        hook.afterModifyPosition(BORROWER, key, params, BalanceDelta(0, 0), "");

        uint256 healthFactor = lending.getHealthFactor(lendingPositionId);
        assertTrue(healthFactor < MIN_HF);

        // 4) Reactive emits the liquidation callback.
        bytes32 expectedPositionId = lpPositionId;
        bytes memory expectedPayload =
            abi.encodeWithSignature("liquidate(address,bytes32)", address(0), expectedPositionId);

        vm.expectEmit(true, true, true, true);
        emit ReQuardReactive.Callback(DEST_CHAIN_ID, address(destination), CALLBACK_GAS_LIMIT, expectedPayload);

        reactive.onPositionHealthUpdated(expectedPositionId, BORROWER, collateralValueUnsafe, borrowedAmount, healthFactor);

        // 5) Simulate Reactive Network executing destination callback from the reactive VM.
        // We don't need to parse payload; destination expects the reserved RVM address slot.
        vm.prank(REACTIVE_VM);
        destination.liquidate(address(0), expectedPositionId);

        // 6) Verify end-to-end liquidation effects.
        (
            address ownerStored,
            ,
            ,
            ,
            uint128 liquidityStored,
            ,
            uint256 collateralStored,
            bytes32 storedLendingPositionId,
            bool liquidated
        ) = hook.lpPositions(expectedPositionId);

        assertEq(ownerStored, BORROWER);
        assertEq(liquidated, true);
        assertEq(liquidityStored, 0);
        assertEq(collateralStored, 0);
        assertEq(storedLendingPositionId, lendingPositionId);

        ReQuardLending.Position memory pos = lending.getPosition(lendingPositionId);
        assertEq(pos.liquidated, true);
        assertEq(pos.borrowedAmount, 0);
        assertEq(pos.collateralValue, 0);

        // Fee accumulator should have grown by at least the hook liquidation fee.
        uint256 expectedHookFee = (collateralValueUnsafe * 50) / 10000;
        assertEq(hook.accumulatedFees(), expectedHookFee);
    }
}

