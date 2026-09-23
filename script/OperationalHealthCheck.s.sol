// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {OperationalSafetyVault} from "../src/OperationalSafetyVault.sol";

/// @title OperationalHealthCheck
/// @notice Read-only incident check for a deployed OperationalSafetyVault.
contract OperationalHealthCheck is Script {
    error Insolvent(uint256 assets, uint256 liabilities);
    error SequencerStale(uint256 age, uint256 threshold);
    error DegradedMode(uint256 mode);

    function run() external {
        address vaultAddress = vm.envAddress("OPERATIONAL_VAULT");
        OperationalSafetyVault vault = OperationalSafetyVault(vaultAddress);

        uint256 currentAssets = vault.assets();
        uint256 liabilities = vault.totalLiabilities();
        uint256 lastUpdate = vault.lastSequencerUpdate();
        uint256 threshold = vault.inactivityThreshold();
        uint256 age = block.timestamp - lastUpdate;
        uint256 currentMode = uint256(vault.mode());

        console2.log("vault", vaultAddress);
        console2.log("mode", currentMode);
        console2.log("assets", currentAssets);
        console2.log("liabilities", liabilities);
        console2.log("sequencer age", age);
        console2.log("inactivity threshold", threshold);
        console2.log("recovery ready at", vault.recoveryReadyAt());

        if (currentAssets < liabilities) revert Insolvent(currentAssets, liabilities);
        if (age >= threshold) revert SequencerStale(age, threshold);
        if (currentMode != uint256(OperationalSafetyVault.Mode.Active)) {
            revert DegradedMode(currentMode);
        }
    }
}
