// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ReQuardLending} from "../src/ReQuardLending.sol";
import {ReQuardHook} from "../src/ReQuardHook.sol";
import {ReQuardDestination} from "../src/ReQuardDestination.sol";
import {ReQuardReactive} from "../src/ReQuardReactive.sol";

/// @title Deployment Script for ReQuard
/// @notice Deploys all contracts needed for ReQuard on Base Sepolia
/// @dev Configure addresses and parameters before running
contract DeployScript is Script {
    // Base Sepolia Chain ID
    uint64 constant BASE_SEPOLIA_CHAIN_ID = 84531;
    
    // Reactive Network Lasna Testnet Chain ID (for Reactive Contract deployment)
    uint64 constant REACTIVE_LASNA_CHAIN_ID = 5318007;
    
    // Configuration parameters
    uint256 constant MIN_HEALTH_FACTOR = 1.2e18; // 120% - positions below this will be liquidated
    uint64 constant CALLBACK_GAS_LIMIT = 500000; // Gas limit for liquidation callbacks
    
    // Token addresses on Base Sepolia (update these with actual testnet addresses)
    address constant COLLATERAL_TOKEN = address(0x1234567890123456789012345678901234567890); // Update with actual token
    address constant DEBT_TOKEN = address(0x0987654321098765432109876543210987654321); // Update with actual token
    
    // PoolManager address on Base Sepolia (update with actual Uniswap V4 PoolManager)
    address constant POOL_MANAGER = address(0x000000000004444c5dc75cB358380D2e3dE08A90); // Update with actual PoolManager
    
    // Reactive VM address (will be provided by Reactive Network after deployment)
    // This should be set after deploying the Reactive contract
    address reactiveVmAddress;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying ReQuard contracts...");
        console.log("Deployer:", deployer);
        console.log("Base Sepolia Chain ID:", BASE_SEPOLIA_CHAIN_ID);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy Lending Protocol
        console.log("\n1. Deploying ReQuardLending...");
        ReQuardLending lending = new ReQuardLending(COLLATERAL_TOKEN, DEBT_TOKEN);
        console.log("ReQuardLending deployed at:", address(lending));
        
        // Step 2: Deploy Destination Contract (temporary address for hook constructor)
        // We'll redeploy after getting the Reactive VM address
        console.log("\n2. Deploying ReQuardDestination (temporary)...");
        address tempReactiveVm = address(0); // Will be updated
        ReQuardDestination destination = new ReQuardDestination(tempReactiveVm, address(0));
        console.log("ReQuardDestination deployed at:", address(destination));
        
        // Step 3: Deploy Hook
        console.log("\n3. Deploying ReQuardHook...");
        ReQuardHook hook = new ReQuardHook(
            POOL_MANAGER,
            address(lending),
            address(destination)
        );
        console.log("ReQuardHook deployed at:", address(hook));
        
        // Step 4: Update destination with hook address
        // Note: This requires updating the destination contract or redeploying
        // For now, we'll note that destination needs to be redeployed with correct hook address
        
        // Step 5: Set hook as liquidator in lending protocol
        console.log("\n4. Setting hook as liquidator in lending protocol...");
        lending.setLiquidator(address(hook));
        
        // Step 6: Deploy Reactive Contract on Reactive Network
        // NOTE: This contract should be deployed on Reactive Network (Lasna Testnet)
        // The deployment address will be different
        console.log("\n5. Deploying ReQuardReactive (for Reactive Network)...");
        console.log("NOTE: Deploy this contract on Reactive Network Lasna Testnet (Chain ID:", REACTIVE_LASNA_CHAIN_ID, ")");
        console.log("Constructor parameters:");
        console.log("  originChainId:", BASE_SEPOLIA_CHAIN_ID);
        console.log("  destinationChainId:", BASE_SEPOLIA_CHAIN_ID);
        console.log("  destinationContract:", address(destination));
        console.log("  minHealthFactor:", MIN_HEALTH_FACTOR);
        console.log("  callbackGasLimit:", CALLBACK_GAS_LIMIT);
        
        // For demonstration, we'll deploy it here, but in production deploy on Reactive Network
        ReQuardReactive reactive = new ReQuardReactive(
            BASE_SEPOLIA_CHAIN_ID,
            BASE_SEPOLIA_CHAIN_ID,
            address(destination),
            MIN_HEALTH_FACTOR,
            CALLBACK_GAS_LIMIT
        );
        console.log("ReQuardReactive deployed at:", address(reactive));
        console.log("NOTE: Redeploy this on Reactive Network Lasna Testnet!");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("ReQuardLending:", address(lending));
        console.log("ReQuardDestination:", address(destination));
        console.log("ReQuardHook:", address(hook));
        console.log("ReQuardReactive:", address(reactive));
        console.log("\nNext Steps:");
        console.log("1. Update ReQuardDestination with correct hook address (or redeploy)");
        console.log("2. Deploy ReQuardReactive on Reactive Network Lasna Testnet");
        console.log("3. Configure Reactive Network subscription to monitor PositionHealthUpdated events");
        console.log("4. Fund ReQuardReactive contract to keep it active");
    }
}
