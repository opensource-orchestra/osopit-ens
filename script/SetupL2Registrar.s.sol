// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {L2Registrar} from "../src/examples/L2Registrar.sol";
import {IL2Registry} from "../src/interfaces/IL2Registry.sol";

contract SetupL2Registrar is Script {
    function run() external {
        address registrarAddress = vm.envAddress("L2_REGISTRAR_ADDRESS");
        address registryAddress = vm.envAddress("L2_REGISTRY_ADDRESS");

        // Inviter address specified by user
        address inviterAddress = 0xD70450BA109f0A1b1971f330A0A4a86b99a94E57;

        IL2Registry registry = IL2Registry(registryAddress);
        L2Registrar registrar = L2Registrar(registrarAddress);

        console.log("Setting up L2Registrar...");
        console.log("Registry:", registryAddress);
        console.log("Registrar:", registrarAddress);
        console.log("Inviter to add:", inviterAddress);
        console.log("");

        vm.startBroadcast();

        // Step 1: Add registrar to L2Registry (requires registry owner)
        console.log("Adding registrar to L2Registry...");
        registry.addRegistrar(registrarAddress);
        console.log("  Registrar added successfully");

        // Step 2: Add inviter to L2Registrar (requires registrar owner)
        console.log("Adding inviter to L2Registrar...");
        registrar.addInviter(inviterAddress);
        console.log("  Inviter added successfully");

        vm.stopBroadcast();

        // Verify setup
        console.log("");
        console.log("=================================================");
        console.log("Setup complete!");
        console.log("=================================================");
        console.log("Registrar approved in registry:", registry.registrars(registrarAddress));
        console.log("Inviter approved in registrar:", registrar.inviters(inviterAddress));
        console.log("");
        console.log("Ready to generate invites and register names!");
    }
}
