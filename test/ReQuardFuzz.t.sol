// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ReQuardReactive} from "../src/ReQuardReactive.sol";
import {ReQuardLending} from "../src/ReQuardLending.sol";
import {ReQuardHook, BalanceDelta} from "../src/ReQuardHook.sol";
import {IPoolManager, IHooks} from "../src/interfaces/IUniswapV4Hooks.sol";

import {PoolManagerMock} from "./mocks/PoolManagerMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract ReQuardFuzzTest is Test {
    uint64 internal constant ORIGIN_CHAIN_ID = 84531;
    uint64 internal constant DEST_CHAIN_ID = 84531;
    uint256 internal constant MIN_HF = 1.2e18;
    uint64 internal constant CALLBACK_GAS_LIMIT = 500000;

    bytes32 internal constant SALT = bytes32(uint256(0xABCDEF));

    address internal constant BORROWER = address(0xB0B);
    address internal constant EXECUTOR = address(0xE);

    IPoolManager.PoolKey internal key;
    IPoolManager.ModifyLiquidityParams internal params;

    ReQuardReactive internal reactive;

    // Re-deployed inside fuzz tests to keep each run isolated.
    PoolManagerMock internal poolManager;
    ERC20Mock internal collateralToken;
    ERC20Mock internal debtToken;
    ReQuardLending internal lending;
    ReQuardHook internal hook;

    function setUp() public {
        key = IPoolManager.PoolKey({
            currency0: uint160(0x100),
            currency1: uint160(0x200),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0x999))
        });

        params = IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: SALT});

        // Destination address doesn't matter for this fuzz test; payload correctness is checked.
        reactive = new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, address(0xD00D), MIN_HF, CALLBACK_GAS_LIMIT);
    }

    function _positionId(address owner) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                owner, key.currency0, key.currency1, key.fee, params.tickLower, params.tickUpper, params.salt
            )
        );
    }

    function testFuzz_reactiveCallbackEmitsOnlyWhenBelowMin(uint256 healthFactor) public {
        bytes32 positionId = keccak256(abi.encodePacked("pos", healthFactor));

        vm.recordLogs();
        reactive.onPositionHealthUpdated(positionId, address(0xBEEF), 0, 0, healthFactor);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 callbackSig = keccak256("Callback(uint64,address,uint64,bytes)");
        bool sawCallback = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) {
                sawCallback = true;
                break;
            }
        }

        if (healthFactor >= MIN_HF) {
            assertTrue(!sawCallback);
        } else {
            assertTrue(sawCallback);
        }
    }

    function testFuzz_lendingHealthFactor_matchesFormula(uint256 collateralValue, uint256 borrowedAmount) public {
        collateralValue = bound(collateralValue, 0, 1e28);
        borrowedAmount = bound(borrowedAmount, 0, 1e28);

        bytes32 lendingPositionId = keccak256(abi.encodePacked("lendpos", collateralValue, borrowedAmount));
        bytes32 lpPositionId = keccak256(abi.encodePacked("lppos", collateralValue));

        ERC20Mock collat = new ERC20Mock("COLL", "COLL", 18);
        ERC20Mock debt = new ERC20Mock("DEBT", "DEBT", 18);
        ReQuardLending lend = new ReQuardLending(address(collat), address(debt));

        lend.upsertPosition(lendingPositionId, BORROWER, lpPositionId, collateralValue, borrowedAmount);

        uint256 actual = lend.getHealthFactor(lendingPositionId);

        if (borrowedAmount == 0) {
            assertEq(actual, type(uint256).max);
        } else {
            uint256 expected = (collateralValue * MIN_HF) / borrowedAmount;
            assertEq(actual, expected);
        }
    }

    function testFuzz_hookLiquidation_revertsOrSucceedsBasedOnHealthFactor(uint128 liquidity, uint256 borrowedAmount)
        public
    {
        vm.assume(liquidity > 0);
        liquidity = uint128(bound(uint256(liquidity), 1, 1e18));
        borrowedAmount = bound(borrowedAmount, 0, 1e28);

        uint256 collateralValue = uint256(liquidity) * 1e10;
        bytes32 lpPositionId = _positionId(BORROWER);
        bytes32 lendingPositionId = keccak256(abi.encodePacked("lending-pos", collateralValue, borrowedAmount));

        poolManager = new PoolManagerMock();
        collateralToken = new ERC20Mock("COLL", "COLL", 18);
        debtToken = new ERC20Mock("DEBT", "DEBT", 18);

        lending = new ReQuardLending(address(collateralToken), address(debtToken));
        hook = new ReQuardHook(address(poolManager), address(lending), EXECUTOR);
        lending.setLiquidator(address(hook));

        poolManager.setLiquidity(key, BORROWER, params.tickLower, params.tickUpper, params.salt, liquidity);

        // Create LP position.
        vm.prank(address(poolManager));
        hook.afterModifyPosition(BORROWER, key, params, BalanceDelta(0, 0), "");

        // Link collateral to lending (creates the lending association inside the hook).
        lending.upsertPosition(lendingPositionId, BORROWER, lpPositionId, collateralValue, borrowedAmount);
        vm.prank(BORROWER);
        hook.registerCollateral(lpPositionId, lendingPositionId);

        // Make unwind deterministic.
        poolManager.setModifyLiquidityDeltas(1, 1);

        if (borrowedAmount == 0 || borrowedAmount <= collateralValue) {
            vm.prank(EXECUTOR);
            vm.expectRevert(bytes("position healthy"));
            hook.liquidatePosition(lpPositionId);
        } else {
            vm.prank(EXECUTOR);
            hook.liquidatePosition(lpPositionId);

            (,,,, uint128 liquidityStored,, uint256 collateralStored,, bool liquidated) = hook.lpPositions(lpPositionId);
            assertEq(liquidated, true);
            assertEq(liquidityStored, 0);
            assertEq(collateralStored, 0);
        }
    }
}

