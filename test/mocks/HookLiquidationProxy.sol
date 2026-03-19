// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Thin forwarding proxy used by the integration test.
 *
 * `ReQuardDestination` stores an immutable `ReQuardHook` reference and calls
 * `liquidatePosition(positionId)`. In production, that reference is the hook
 * instance itself, but in tests we sometimes need to avoid constructor
 * circular-dependencies.
 *
 * This proxy forwards `liquidatePosition(bytes32)` to a configurable target.
 * Any caller can forward; access control is tested at the real hook level.
 */
contract HookLiquidationProxy {
    address public target;

    function setTarget(address _target) external {
        target = _target;
    }

    function liquidatePosition(bytes32 positionId) external {
        address t = target;
        require(t != address(0), "target not set");
        (bool ok, ) = t.call(abi.encodeWithSignature("liquidatePosition(bytes32)", positionId));
        require(ok, "forward failed");
    }
}

