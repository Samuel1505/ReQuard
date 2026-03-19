// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ReQuardReactive} from "../src/ReQuardReactive.sol";

/// @title Deployment Script for ReQuardReactive on Reactive Network
/// @notice Deploys ReQuardReactive contract to Reactive Network Lasna Testnet
/// @dev This script should be run with Reactive Network RPC URL
///      Usage: forge script script/DeployReactive.s.sol:DeployReactiveScript --rpc-url $REACTIVE_LASNA_RPC_URL --broadcast
contract DeployReactiveScript is Script {
    // Chain IDs
    uint64 constant BASE_SEPOLIA_CHAIN_ID = 84531;
    uint64 constant REACTIVE_LASNA_CHAIN_ID = 5318007;

    // Default configuration parameters
    // These can be overridden via environment variables
    uint256 constant DEFAULT_MIN_HEALTH_FACTOR = 1.2e18; // 120%
    uint64 constant DEFAULT_CALLBACK_GAS_LIMIT = 500000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying ReQuardReactive to Reactive Network");
        console.log("========================================");
        console.log("Deployer address:", deployer);
        console.log("Chain ID:", REACTIVE_LASNA_CHAIN_ID);
        console.log("");

        // Get configuration from environment variables or use defaults
        uint64 originChainId = uint64(vm.envOr("ORIGIN_CHAIN_ID", uint256(BASE_SEPOLIA_CHAIN_ID)));
        uint64 destinationChainId = uint64(vm.envOr("DESTINATION_CHAIN_ID", uint256(BASE_SEPOLIA_CHAIN_ID)));

        // Destination contract address is required
        address destinationContract = vm.envAddress("DESTINATION_CONTRACT");

        uint256 minHealthFactor = vm.envOr("MIN_HEALTH_FACTOR", DEFAULT_MIN_HEALTH_FACTOR);
        uint64 callbackGasLimit = uint64(vm.envOr("CALLBACK_GAS_LIMIT", uint256(DEFAULT_CALLBACK_GAS_LIMIT)));

        console.log("Configuration:");
        console.log("  Origin Chain ID:", originChainId);
        console.log("  Destination Chain ID:", destinationChainId);
        console.log("  Destination Contract:", destinationContract);
        console.log("  Min Health Factor:", minHealthFactor);
        console.log("  Callback Gas Limit:", callbackGasLimit);
        console.log("");

        // Validate configuration
        require(destinationContract != address(0), "DESTINATION_CONTRACT cannot be zero address");
        require(minHealthFactor > 1e18, "MIN_HEALTH_FACTOR must be greater than 100% (1e18)");
        require(callbackGasLimit > 0, "CALLBACK_GAS_LIMIT must be greater than 0");

        console.log("Deploying ReQuardReactive...");

        vm.startBroadcast(deployerPrivateKey);

        ReQuardReactive reactive = new ReQuardReactive(
            originChainId, destinationChainId, destinationContract, minHealthFactor, callbackGasLimit
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("ReQuardReactive deployed at:", address(reactive));
        console.log("");
        console.log("Contract Configuration:");
        console.log("  originChainId:", reactive.originChainId());
        console.log("  destinationChainId:", reactive.destinationChainId());
        console.log("  destinationContract:", reactive.destinationContract());
        console.log("  minHealthFactor:", reactive.minHealthFactor());
        console.log("  callbackGasLimit:", reactive.callbackGasLimit());
        console.log("");
        console.log("========================================");
        console.log("Next Steps:");
        console.log("========================================");
        console.log("1. Fund the contract with native tokens:");
        console.log("   Send native tokens to:", address(reactive));
        console.log("   (Required to keep the contract active for callbacks)");
        console.log("");
        console.log("2. Configure Reactive Network subscription:");
        console.log("   - Origin Chain: Base Sepolia (84531)");
        console.log("   - Target Contract: ReQuardHook address");
        console.log("   - Event: PositionHealthUpdated(bytes32,address,uint256,uint256,uint256)");
        console.log("   - Handler: onPositionHealthUpdated(bytes32,address,uint256,uint256,uint256)");
        console.log("   - Reactive Contract:", address(reactive));
        console.log("");
        console.log("3. Monitor the contract on Reactscan:");
        console.log("   - Check contract status (should be Active)");
        console.log("   - Monitor event subscriptions");
        console.log("   - Track callback executions");
        console.log("");
        console.log("4. Test the integration:");
        console.log("   - Create LP position with ReQuardHook");
        console.log("   - Register as collateral in ReQuardLending");
        console.log("   - Borrow against collateral");
        console.log("   - Simulate price movement to trigger liquidation");
        console.log("   - Verify callback execution and liquidation");
        console.log("========================================");
    }
}
