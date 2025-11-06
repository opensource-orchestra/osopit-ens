// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {L2Registrar} from "../src/examples/L2Registrar.sol";

contract DeployL2Registrar is Script {
    function run() external {
        address l2Registry = vm.envAddress("L2_REGISTRY_ADDRESS");

        console.log("Deploying L2Registrar...");
        console.log("L2Registry:", l2Registry);
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        L2Registrar registrar = new L2Registrar(l2Registry);

        vm.stopBroadcast();

        console.log("");
        console.log("=================================================");
        console.log("L2Registrar deployed to:", address(registrar));
        console.log("Owner:", registrar.owner());
        console.log("Chain ID:", registrar.chainId());
        console.log("Coin Type:", registrar.coinType());
        console.log("=================================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contract on BaseScan");
        console.log("2. Call L2Registry.addRegistrar(", address(registrar), ")");
        console.log("3. Call L2Registrar.addInviter(0x0cf84f01c311dc093969136b1814f05b5b3167f6)");
        console.log("4. Update frontend with address:", address(registrar));
    }
}
