// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title ReQuardReactive
/// @notice Reactive Contract to be deployed on Reactive Network.
///         It subscribes to `PositionHealthUpdated` events from the
///         `ReQuardHook` contract on the origin chain and, when a position's
///         health factor falls below a configured threshold, emits a
///         `Callback` that instructs Reactive Network to call into the
///         destination contract on the Uniswap chain to perform liquidation.
///
/// This contract focuses on implementing the Reactive-specific patterns:
///   - Inversion of control via event subscriptions.
///   - Emitting `Callback` events with ABI-encoded payloads.
///   - Reserving the first argument slot in the payload for the RVM address.
contract ReQuardReactive {
    /// @notice Emitted by Reactive Contracts to request a callback on a
    ///         destination chain.
    /// @dev This event signature matches the pattern used in the Reactive
    ///      Network demos. The Reactive infrastructure listens for this
    ///      event and submits the encoded call to the destination chain.
    event Callback(
        uint64 indexed destinationChainId, address indexed destinationContract, uint64 gasLimit, bytes payload
    );

    /// @notice Origin chain identifier where the Uniswap V4 hook lives.
    /// @dev Base Sepolia testnet chain ID: 84531
    uint64 public immutable originChainId;

    /// @notice Destination chain identifier where the `ReQuardDestination`
    ///         contract is deployed. In many cases this will equal the
    ///         origin chain ID, but we keep them separate to allow
    ///         cross-chain variants.
    /// @dev Base Sepolia testnet chain ID: 84531
    uint64 public immutable destinationChainId;

    /// @notice Address of the destination contract that receives callbacks
    ///         and calls the hook's `liquidatePosition`.
    address public immutable destinationContract;

    /// @notice Minimum acceptable health factor. If a position's health
    ///         factor falls below this threshold, a liquidation callback
    ///         is emitted.
    /// @dev Recommended: 1.2e18 (120%) - positions below this will be liquidated
    uint256 public immutable minHealthFactor;

    /// @notice Gas limit hint for the callback execution on the destination
    ///         chain.
    /// @dev Recommended: 500000 gas for LP unwinding + liquidation operations
    uint64 public immutable callbackGasLimit;

    constructor(
        uint64 _originChainId,
        uint64 _destinationChainId,
        address _destinationContract,
        uint256 _minHealthFactor,
        uint64 _callbackGasLimit
    ) {
        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        destinationContract = _destinationContract;
        minHealthFactor = _minHealthFactor;
        callbackGasLimit = _callbackGasLimit;
    }

    /// @notice Reactive entrypoint that is conceptually invoked when a
    ///         `PositionHealthUpdated` event is observed on the origin chain.
    /// @dev In the real Reactive Network environment, the ReactVM will
    ///      deserialize the event log and feed the relevant fields into this
    ///      function (or an equivalent handler, depending on the subscription
    ///      configuration).
    ///
    /// @param positionId Identifier of the LP-backed collateral position.
    /// @param owner The owner of the position.
    /// @param collateralValue Latest collateral value.
    /// @param debtValue Latest debt value.
    /// @param healthFactor Computed health factor associated with the
    ///        position (e.g. collateral / debt in 1e18 precision).
    function onPositionHealthUpdated(
        bytes32 positionId,
        address owner,
        uint256 collateralValue,
        uint256 debtValue,
        uint256 healthFactor
    ) external {
        // Silence unused variable warnings for fields that are not strictly
        // needed by the Reactive logic but may be useful in more advanced
        // versions of ReQuard.
        owner;
        collateralValue;
        debtValue;

        // If the health factor is above the threshold, do nothing.
        if (healthFactor >= minHealthFactor) {
            return;
        }

        // Health factor is below the safe threshold:
        // instruct Reactive Network to execute a liquidation callback on the
        // destination chain.
        //
        // IMPORTANT: The first argument in the encoded payload is reserved
        // for the RVM address. Reactive Network will overwrite this slot
        // with the correct RVM identifier before sending the transaction.
        bytes memory payload = abi.encodeWithSignature(
            "liquidate(address,bytes32)",
            address(0), // reserved for RVM address
            positionId
        );

        emit Callback(destinationChainId, destinationContract, callbackGasLimit, payload);
    }

    // --- Funding helpers (stubs) ------------------------------------------------

    /// @notice Reactive Contracts must remain solvent to stay active on
    ///         Reactive Network. These helpers make it explicit that the
    ///         contract can be funded and drained as needed.
    receive() external payable {}

    /// @notice Withdraw native tokens from this contract. In practice this
    ///         would be restricted to an admin or governance.
    function withdraw(address payable to, uint256 amount) external {
        require(to != address(0), "zero address");
        require(amount <= address(this).balance, "insufficient balance");
        to.transfer(amount);
    }
}

