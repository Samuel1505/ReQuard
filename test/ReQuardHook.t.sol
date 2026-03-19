// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ReQuardHook, BalanceDelta} from "../src/ReQuardHook.sol";
import {ReQuardLending} from "../src/ReQuardLending.sol";
import {IPoolManager, IHooks} from "../src/interfaces/IUniswapV4Hooks.sol";
import {PoolManagerMock} from "./mocks/PoolManagerMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract ReQuardHookTest is Test {
    PoolManagerMock internal poolManager;
    ERC20Mock internal collateralToken;
    ERC20Mock internal debtToken;
    ERC20Mock internal payoutToken;

    ReQuardLending internal lending;
    ReQuardHook internal hook;

    address internal executor = address(0xE);
    address internal borrower = address(0xB0B);
    uint256 internal constant MIN_HEALTH_FACTOR = 1.2e18;

    IPoolManager.PoolKey internal key;
    IPoolManager.ModifyLiquidityParams internal params;
    bytes32 internal salt;

    function setUp() public {
        poolManager = new PoolManagerMock();

        collateralToken = new ERC20Mock("COLL", "COLL", 18);
        debtToken = new ERC20Mock("DEBT", "DEBT", 18);
        payoutToken = new ERC20Mock("PAY", "PAY", 18);

        lending = new ReQuardLending(address(collateralToken), address(debtToken));
        hook = new ReQuardHook(address(poolManager), address(lending), executor);

        // Hook calls into lending.liquidatePosition, so the hook must be the liquidator.
        lending.setLiquidator(address(hook));

        salt = bytes32(uint256(0xABCDEF));
        key = IPoolManager.PoolKey({
            currency0: uint160(0x100),
            currency1: uint160(0x200),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0x999))
        });

        params = IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            salt: salt
        });
    }

    function _positionId(address owner) internal view returns (bytes32) {
        // ReQuardHook computes positionId ignoring currentLiquidity; it only uses key + params + owner.
        return keccak256(
            abi.encodePacked(owner, key.currency0, key.currency1, key.fee, params.tickLower, params.tickUpper, salt)
        );
    }

    function test_getHookPermissions_returnsExpected() public view {
        uint256 expected = (1 << 0) | (1 << 1);
        assertEq(hook.getHookPermissions(), expected);
    }

    function test_beforeModifyPosition_onlyPoolManager() public {
        vm.expectRevert(bytes("not pool manager"));
        hook.beforeModifyPosition(address(this), key, params, "");

        vm.prank(address(poolManager));
        bytes4 ret = hook.beforeModifyPosition(address(this), key, params, "");
        assertEq(ret, hook.beforeModifyPosition.selector);
    }

    function test_afterModifyPosition_createsAndSetsLPPosition() public {
        uint128 liquidity = 1234;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 positionId = _positionId(borrower);

        (
            address storedOwner,
            IPoolManager.PoolKey memory storedKey,
            int24 storedTickLower,
            int24 storedTickUpper,
            uint128 storedLiquidity,
            bytes32 storedSalt,
            uint256 storedCollateralValue,
            bytes32 storedLendingPositionId,
            bool storedLiquidated
        ) = hook.lpPositions(positionId);

        assertEq(storedOwner, borrower);
        assertEq(storedKey.currency0, key.currency0);
        assertEq(storedKey.currency1, key.currency1);
        assertEq(storedKey.fee, key.fee);
        assertEq(storedKey.tickSpacing, key.tickSpacing);
        assertEq(address(storedKey.hooks), address(key.hooks));
        assertEq(storedTickLower, params.tickLower);
        assertEq(storedTickUpper, params.tickUpper);
        assertEq(storedSalt, salt);
        assertEq(storedLiquidity, liquidity);
        assertEq(storedCollateralValue, uint256(liquidity) * 1e10);
        assertEq(storedLendingPositionId, bytes32(0));
        assertEq(storedLiquidated, false);
    }

    function test_registerCollateral_linksLPToLendingAndUpdatesCollateralValue() public {
        // Create LP position first.
        uint128 liquidity = 50;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(borrower);

        // Create lending position before linking.
        bytes32 lendingPositionId = keccak256("lending-pos-1");
        uint256 expectedCollateralValue = uint256(liquidity) * 1e10;

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, expectedCollateralValue, 200);

        vm.prank(borrower);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 collateralValue,
            bytes32 linkedLendingPosId,
            bool liquidated
        ) = hook.lpPositions(lpPositionId);
        assertEq(linkedLendingPosId, lendingPositionId);
        assertEq(collateralValue, expectedCollateralValue);
        assertEq(liquidated, false);

        ReQuardLending.Position memory pos = lending.getPosition(lendingPositionId);
        assertEq(pos.collateralValue, expectedCollateralValue);
        assertEq(pos.borrower, borrower);
        assertEq(pos.lpPositionId, lpPositionId);
    }

    function test_registerCollateral_revertsIfNotOwner() public {
        uint128 liquidity = 50;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(borrower);
        bytes32 lendingPositionId = keccak256("lending-pos-1");

        uint256 expectedCollateralValue = uint256(liquidity) * 1e10;
        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, expectedCollateralValue, 200);

        vm.expectRevert(bytes("not owner"));
        hook.registerCollateral(lpPositionId, lendingPositionId);
    }

    function test_afterModifyPosition_updatesLendingAndEmitsHealthEventWhenCollateralized() public {
        // Create LP.
        uint128 liquidity = 200;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(borrower);

        // Create lending position and link collateral.
        bytes32 lendingPositionId = keccak256("lending-pos-1");
        uint256 collateralValue = uint256(liquidity) * 1e10;
        uint256 borrowedAmount = collateralValue / 2; // healthy (HF >= MIN)

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);
        vm.prank(borrower);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        // Change liquidity to force a different collateralValue.
        uint128 newLiquidity = 150;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, newLiquidity);

        uint256 newCollateralValue = uint256(newLiquidity) * 1e10;
        uint256 expectedHealthFactor = (newCollateralValue * MIN_HEALTH_FACTOR) / borrowedAmount;

        bytes32 eventSig = keccak256("PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)");

        vm.recordLogs();
        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == eventSig) {
                // topics[1] = positionId, topics[2] = owner (as indexed address)
                assertEq(logs[i].topics[1], bytes32(lendingPositionId));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), borrower);

                (uint256 emittedCollateralValue, uint256 emittedDebtValue, uint256 emittedHealthFactor) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));
                assertEq(emittedCollateralValue, newCollateralValue);
                assertEq(emittedDebtValue, borrowedAmount);
                assertEq(emittedHealthFactor, expectedHealthFactor);
                found = true;
                break;
            }
        }

        assertTrue(found);
    }

    function test_liquidatePosition_onlyExecutor_andZeroesState() public {
        uint128 liquidity = 100;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(borrower);

        // Make position unhealthy: borrowedAmount > collateralValue.
        bytes32 lendingPositionId = keccak256("lending-pos-1");
        uint256 collateralValue = uint256(liquidity) * 1e10;
        uint256 borrowedAmount = collateralValue + 1;

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        vm.prank(borrower);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        // Configure pool unwind deltas.
        poolManager.setModifyLiquidityDeltas(500, 700);

        // Unauthorized caller.
        vm.expectRevert(bytes("not executor"));
        hook.liquidatePosition(lpPositionId);

        uint256 expectedHookLiquidationFee = (collateralValue * 50) / 10000;
        uint256 expectedRemainingCollateral = 1200;
        uint256 expectedLendingLiquidationFee = expectedHookLiquidationFee; // same formula + same collateral
        uint256 expectedTotalFee = expectedLendingLiquidationFee + expectedHookLiquidationFee;

        vm.prank(executor);
        hook.liquidatePosition(lpPositionId);

        (
            address storedOwner,
            ,
            ,
            ,
            uint128 storedLiquidity,
            ,
            uint256 storedCollateralValue,
            ,
            bool storedLiquidated
        ) = hook.lpPositions(lpPositionId);

        assertEq(storedOwner, borrower);
        assertEq(storedLiquidity, 0);
        assertEq(storedCollateralValue, 0);
        assertEq(storedLiquidated, true);

        ReQuardLending.Position memory pos = lending.getPosition(lendingPositionId);
        assertEq(pos.liquidated, true);
        assertEq(pos.borrowedAmount, 0);
        assertEq(pos.collateralValue, 0);

        assertEq(hook.accumulatedFees(), expectedHookLiquidationFee);

        // Second liquidation should fail.
        vm.prank(executor);
        vm.expectRevert(bytes("already liquidated"));
        hook.liquidatePosition(lpPositionId);

        // Basic sanity check on accumulated fees: events are covered elsewhere.
        expectedRemainingCollateral; // keep variable for future event checks
        expectedTotalFee; // keep variable for future event checks
    }

    function test_distributeFeesToLPs_transfersAndDecrements() public {
        // Reuse liquidation to populate accumulatedFees.
        uint128 liquidity = 100;
        poolManager.setLiquidity(key, borrower, params.tickLower, params.tickUpper, salt, liquidity);

        vm.prank(address(poolManager));
        hook.afterModifyPosition(borrower, key, params, BalanceDelta(0, 0), "");

        bytes32 lpPositionId = _positionId(borrower);

        bytes32 lendingPositionId = keccak256("lending-pos-1");
        uint256 collateralValue = uint256(liquidity) * 1e10;
        uint256 borrowedAmount = collateralValue + 1;
        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        vm.prank(borrower);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        // Configure pool unwind deltas.
        poolManager.setModifyLiquidityDeltas(1, 1);

        vm.prank(executor);
        hook.liquidatePosition(lpPositionId);

        uint256 feeBalance = hook.accumulatedFees();
        assertTrue(feeBalance > 0);

        // Fund hook with payout tokens so transfer succeeds.
        payoutToken.mint(address(hook), feeBalance);

        uint256 amount = feeBalance / 2;
        uint256 before = payoutToken.balanceOf(borrower);

        vm.prank(borrower);
        hook.distributeFeesToLPs(address(payoutToken), amount);

        assertEq(hook.accumulatedFees(), feeBalance - amount);
        assertEq(payoutToken.balanceOf(borrower), before + amount);

        // Not enough fees.
        vm.expectRevert(bytes("insufficient fees"));
        hook.distributeFeesToLPs(address(payoutToken), feeBalance);
    }
}

