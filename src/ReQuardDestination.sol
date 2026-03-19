// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReQuardHook} from "./ReQuardHook.sol";

/// @title ReQuardDestination
/// @notice Destination-chain contract that receives callbacks from Reactive
///         Network and calls into the Uniswap V4 hook to perform liquidations.
///
/// Reactive Network will emit callbacks whose payload encodes a call to:
///   `liquidate(bytes32 positionId)`
/// with an extra first argument reserved for the RVM address.
contract ReQuardDestination {
    /// @dev Address of the Reactive VM (RVM) that is allowed to call
    ///      liquidation entrypoints via callbacks.
    address public immutable reactiveVm;

    /// @dev The hook that actually unwinds and liquidates LP positions.
    ReQuardHook public immutable hook;

    constructor(address _reactiveVm, address _hook) {
        reactiveVm = _reactiveVm;
        hook = ReQuardHook(_hook);
    }

    modifier onlyReactiveVm() {
        require(msg.sender == reactiveVm, "not RVM");
        _;
    }

    /// @notice Entry point that Reactive Network will call via a callback.
    /// @param rvmAddress Reserved slot that Reactive overwrites with the RVM
    ///        address. This must be present as the first parameter per
    ///        Reactive Network's ABI convention.
    /// @param positionId Identifier of the LP-backed position to liquidate.
    function liquidate(address rvmAddress, bytes32 positionId) external onlyReactiveVm {
        // `rvmAddress` is not used directly in this example, but it is
        // required to satisfy the Reactive callback ABI convention.
        rvmAddress;

        hook.liquidatePosition(positionId);
    }
}

