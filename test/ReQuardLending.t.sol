// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ReQuardLending} from "../src/ReQuardLending.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract ReQuardLendingTest is Test {
    ERC20Mock internal collateralToken;
    ERC20Mock internal debtToken;
    ReQuardLending internal lending;

    address internal borrower = address(0xB0B);
    address internal other = address(0xCAFE);
    uint256 internal constant MIN_HEALTH_FACTOR = 1.2e18;
    uint256 internal constant LIQUIDATION_FEE_BPS = 50;

    function setUp() public {
        collateralToken = new ERC20Mock("COLL", "COLL", 18);
        debtToken = new ERC20Mock("DEBT", "DEBT", 18);
        lending = new ReQuardLending(address(collateralToken), address(debtToken));
    }

    function test_setLiquidator_canBeSetOnce() public {
        address executor1 = address(0x1111);
        lending.setLiquidator(executor1);
        assertEq(lending.liquidator(), executor1);

        vm.expectRevert(bytes("liquidator already set"));
        lending.setLiquidator(address(0x2222));
    }

    function test_upsertPosition_revertsOnZeroBorrower() public {
        bytes32 positionId = keccak256("p1");
        vm.expectRevert(bytes("zero borrower"));
        lending.upsertPosition(positionId, address(0), bytes32(uint256(1)), 0, 0);
    }

    function test_upsertPosition_addsNewPositionToBorrowerList() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, 123, 456);

        bytes32[] memory ids = lending.getBorrowerPositions(borrower);
        assertEq(ids.length, 1);
        assertEq(ids[0], lendingPositionId);
    }

    function test_updateCollateralValue_revertsWhenPositionNotFound() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(bytes("position not found"));
        lending.updateCollateralValue(unknown, 999);
    }

    function test_updateCollateralValue_revertsWhenLiquidated() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        // Make position unhealthy: borrowedAmount > collateralValue
        uint256 collateralValue = 1000;
        uint256 borrowedAmount = 1001;

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        lending.setLiquidator(address(this));
        lending.liquidatePosition(lendingPositionId);

        vm.expectRevert(bytes("position liquidated"));
        lending.updateCollateralValue(lendingPositionId, 2000);
    }

    function test_getHealthFactor_returnsMaxWhenNoDebt() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, 123, 0);

        assertEq(lending.getHealthFactor(lendingPositionId), type(uint256).max);
    }

    function test_getHealthFactor_matchesFormula() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        uint256 collateralValue = 10_000;
        uint256 borrowedAmount = 2_000;

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        uint256 expected = (collateralValue * MIN_HEALTH_FACTOR) / borrowedAmount;
        assertEq(lending.getHealthFactor(lendingPositionId), expected);
    }

    function test_repayDebt_revertsIfNotBorrower() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        uint256 borrowedAmount = 100;
        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, 200, borrowedAmount);

        vm.prank(other);
        vm.expectRevert(bytes("not borrower"));
        lending.repayDebt(lendingPositionId, 1);
    }

    function test_repayDebt_transfersAndReducesDebt() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        uint256 initialBorrowed = 100;
        uint256 repayAmount = 30;

        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, 200, initialBorrowed);

        // Fund borrower with debt tokens and approve the lending contract.
        debtToken.mint(borrower, repayAmount);
        vm.prank(borrower);
        debtToken.approve(address(lending), repayAmount);

        vm.prank(borrower);
        lending.repayDebt(lendingPositionId, repayAmount);

        ReQuardLending.Position memory pos = lending.getPosition(lendingPositionId);
        assertEq(pos.borrowedAmount, initialBorrowed - repayAmount);
        assertEq(debtToken.balanceOf(address(lending)), repayAmount);
        assertEq(debtToken.balanceOf(borrower), 0);
    }

    function test_liquidatePosition_revertsIfPositionHealthy() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        uint256 collateralValue = 1000;
        uint256 borrowedAmount = 800; // collateral >= debt => healthy
        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        lending.setLiquidator(address(this));
        vm.expectRevert(bytes("position healthy"));
        lending.liquidatePosition(lendingPositionId);
    }

    function test_liquidatePosition_success_marksLiquidatedAndZeroesState() public {
        bytes32 lendingPositionId = keccak256("lendpos-1");
        bytes32 lpPositionId = keccak256("lppos-1");

        uint256 collateralValue = 1000;
        uint256 borrowedAmount = 1001; // unhealthy: borrowed > collateral
        lending.upsertPosition(lendingPositionId, borrower, lpPositionId, collateralValue, borrowedAmount);

        lending.setLiquidator(address(this));

        uint256 expectedLiquidationFee = (collateralValue * LIQUIDATION_FEE_BPS) / 10000;

        (uint256 repaidAmount, uint256 liquidationFee) = lending.liquidatePosition(lendingPositionId);
        assertEq(repaidAmount, borrowedAmount);
        assertEq(liquidationFee, expectedLiquidationFee);

        ReQuardLending.Position memory pos = lending.getPosition(lendingPositionId);
        assertEq(pos.borrowedAmount, 0);
        assertEq(pos.collateralValue, 0);
        assertEq(pos.liquidated, true);
    }
}

