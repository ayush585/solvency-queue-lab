// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {OperationalSafetyVault} from "../src/OperationalSafetyVault.sol";

/// @title DeployOperationalSafetyVault
/// @notice Environment-driven deployment helper. Never commit private keys.
contract DeployOperationalSafetyVault is Script {
    function run() external returns (OperationalSafetyVault vault) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address token = vm.envAddress("SETTLEMENT_TOKEN");
        address owner = vm.envAddress("VAULT_OWNER");
        address sequencer = vm.envAddress("SEQUENCER");
        address guardian = vm.envAddress("GUARDIAN");
        address monitor = vm.envAddress("MONITOR");
        uint256 inactivityThreshold = vm.envUint("INACTIVITY_THRESHOLD_SECONDS");
        uint256 recoveryDelay = vm.envUint("RECOVERY_DELAY_SECONDS");

        vm.startBroadcast(deployerKey);
        vault = new OperationalSafetyVault(
            token, owner, sequencer, guardian, monitor, inactivityThreshold, recoveryDelay
        );
        vm.stopBroadcast();

        console2.log("OperationalSafetyVault", address(vault));
        console2.log("owner", owner);
        console2.log("sequencer", sequencer);
        console2.log("guardian", guardian);
        console2.log("monitor", monitor);
    }
}
