// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ReQuardReactive} from "../src/ReQuardReactive.sol";

contract ReQuardReactiveTest is Test {
    uint64 internal constant ORIGIN_CHAIN_ID = 84531;
    uint64 internal constant DEST_CHAIN_ID = 84531;
    uint256 internal constant MIN_HF = 1.2e18;
    uint64 internal constant GAS_LIMIT = 500000;

    function test_onPositionHealthUpdated_WhenHealthy_DoesNotEmitCallback(uint256 healthFactor) public {
        vm.assume(healthFactor >= MIN_HF);

        address destinationContract = address(0x1234);
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, destinationContract, MIN_HF, GAS_LIMIT);

        bytes32 positionId = keccak256(abi.encodePacked("pos", healthFactor));

        vm.recordLogs();
        reactive.onPositionHealthUpdated(positionId, address(0xBEEF), 1 ether, 1 ether, healthFactor);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 callbackSig = keccak256("Callback(uint64,address,uint64,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics.length == 0 || logs[i].topics[0] != callbackSig);
        }
    }

    function test_onPositionHealthUpdated_WhenUnhealthy_EmitsCallbackWithCorrectPayload() public {
        address destinationContract = address(0xD00D);
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, destinationContract, MIN_HF, GAS_LIMIT);

        bytes32 positionId = keccak256("position-1");
        uint256 healthFactor = MIN_HF - 1;

        bytes memory expectedPayload =
            abi.encodeWithSignature("liquidate(address,bytes32)", address(0), positionId);

        vm.expectEmit(true, true, true, true);
        emit ReQuardReactive.Callback(DEST_CHAIN_ID, destinationContract, GAS_LIMIT, expectedPayload);

        reactive.onPositionHealthUpdated(positionId, address(0xBEEF), 123, 456, healthFactor);
    }

    function test_withdraw_revertsForZeroAddress() public {
        address destinationContract = address(0xD00D);
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, destinationContract, MIN_HF, GAS_LIMIT);

        vm.deal(address(reactive), 1 ether);

        vm.expectRevert(bytes("zero address"));
        reactive.withdraw(payable(address(0)), 1 ether);
    }

    function test_withdraw_revertsForInsufficientBalance() public {
        address destinationContract = address(0xD00D);
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, destinationContract, MIN_HF, GAS_LIMIT);

        vm.deal(address(reactive), 0.5 ether);
        address payable recipient = payable(address(0xBEEF));

        vm.expectRevert(bytes("insufficient balance"));
        reactive.withdraw(recipient, 1 ether);
    }

    function test_withdrawTransfersNativeValue() public {
        address destinationContract = address(0xD00D);
        ReQuardReactive reactive =
            new ReQuardReactive(ORIGIN_CHAIN_ID, DEST_CHAIN_ID, destinationContract, MIN_HF, GAS_LIMIT);

        vm.deal(address(reactive), 2 ether);
        address payable recipient = payable(address(0xBEEF));

        uint256 beforeRecipient = recipient.balance;
        uint256 beforeVault = address(reactive).balance;

        reactive.withdraw(recipient, 1 ether);

        assertEq(recipient.balance, beforeRecipient + 1 ether);
        assertEq(address(reactive).balance, beforeVault - 1 ether);
    }
}

