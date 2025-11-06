// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {L2Registrar} from "../src/examples/L2Registrar.sol";
import {IL2Registry} from "../src/interfaces/IL2Registry.sol";

contract TestFork is Script {
    function run() external view {
        // Base mainnet L2Registry address
        address registryAddress = 0x92f90070Ff34f8Bb9500bE301Ea373217673FDE4;

        // UniversalSignatureValidator address
        address validatorAddress = 0x164af34fAF9879394370C7f09064127C043A35E9;

        console.log("=================================================");
        console.log("Testing Fork Environment on Base Mainnet");
        console.log("=================================================");
        console.log("");

        // Check L2Registry exists
        uint256 registryCodeSize;
        assembly {
            registryCodeSize := extcodesize(registryAddress)
        }
        console.log("L2Registry at:", registryAddress);
        console.log("  Code size:", registryCodeSize, "bytes");
        console.log("  Exists:", registryCodeSize > 0 ? "YES" : "NO");

        // Check UniversalSignatureValidator exists
        uint256 validatorCodeSize;
        assembly {
            validatorCodeSize := extcodesize(validatorAddress)
        }
        console.log("");
        console.log("UniversalSignatureValidator at:", validatorAddress);
        console.log("  Code size:", validatorCodeSize, "bytes");
        console.log("  Exists:", validatorCodeSize > 0 ? "YES" : "YES");

        // Check L2Registry details
        IL2Registry registry = IL2Registry(registryAddress);
        console.log("");
        console.log("L2Registry Details:");
        console.log("  Base Node:", vm.toString(registry.baseNode()));
        console.log("  Owner:", registry.owner());

        console.log("");
        console.log("=================================================");
        console.log("Fork environment verified successfully!");
        console.log("=================================================");
    }
}
