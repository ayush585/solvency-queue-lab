// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OperationalSafetyVault} from "../../src/OperationalSafetyVault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract OperationalSafetyHandler is Test {
    OperationalSafetyVault public immutable vault;
    MockERC20 public immutable token;
    address public immutable sequencer;
    address public immutable guardian;
    address public immutable monitor;

    address[] public actors;

    uint256 public totalMinted;
    uint256 public highestMode;
    bool public degradedObserved;
    uint256 public liabilityCeilingAfterDegrade;
    bool public haltedObserved;
    uint256 public haltedAssets;
    uint256 public haltedLiabilities;

    constructor(
        OperationalSafetyVault vault_,
        MockERC20 token_,
        address sequencer_,
        address guardian_,
        address monitor_,
        address[] memory actors_
    ) {
        vault = vault_;
        token = token_;
        sequencer = sequencer_;
        guardian = guardian_;
        monitor = monitor_;
        actors = actors_;
    }

    function deposit(uint256 actorSeed, uint96 rawAmount) external {
        if (vault.mode() != OperationalSafetyVault.Mode.Active) return;

        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);

        token.mint(actor, amount);
        totalMinted += amount;

        vm.startPrank(actor);
        token.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        _recordMode();
    }

    function withdraw(uint256 actorSeed, uint96 rawAmount) external {
        if (vault.mode() == OperationalSafetyVault.Mode.Halted) return;

        address actor = _actor(actorSeed);
        uint256 claim = vault.balanceOf(actor);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);

        vm.prank(actor);
        vault.withdraw(amount);

        _recordMode();
    }

    function backedCredit(uint256 actorSeed, uint96 rawAmount) external {
        if (vault.mode() != OperationalSafetyVault.Mode.Active) return;

        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);

        token.mint(address(vault), amount);
        totalMinted += amount;

        vm.prank(sequencer);
        vault.applyStateChange(actor, int256(amount));

        _recordMode();
    }

    function redistribute(uint256 fromSeed, uint256 toSeed, uint96 rawAmount) external {
        if (vault.mode() != OperationalSafetyVault.Mode.Active) return;

        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == to) return;

        uint256 claim = vault.balanceOf(from);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);

        vm.prank(sequencer);
        vault.applyStateChange(from, -int256(amount));

        vm.prank(sequencer);
        vault.applyStateChange(to, int256(amount));

        _recordMode();
    }

    function heartbeat() external {
        vm.prank(sequencer);
        vault.heartbeat();
        _recordMode();
    }

    function advanceTime(uint32 rawSeconds) external {
        uint256 secondsForward = bound(uint256(rawSeconds), 1, 2 days);
        vm.warp(block.timestamp + secondsForward);
        _recordMode();
    }

    function tripInactive() external {
        if (vault.mode() != OperationalSafetyVault.Mode.Active) return;

        uint256 age = block.timestamp - vault.lastSequencerUpdate();
        if (age < vault.inactivityThreshold()) return;

        vault.enterExitOnlyIfSequencerInactive();
        _recordMode();
    }

    function monitorExitOnly(bytes32 reason) external {
        if (vault.mode() != OperationalSafetyVault.Mode.Active) return;

        vm.prank(monitor);
        vault.enterExitOnly(reason);
        _recordMode();
    }

    function guardianHalt(bytes32 reason) external {
        if (vault.mode() == OperationalSafetyVault.Mode.Halted) return;

        vm.prank(guardian);
        vault.halt(reason);
        _recordMode();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _recordMode() internal {
        uint256 currentMode = uint256(vault.mode());

        if (currentMode > highestMode) highestMode = currentMode;

        if (!degradedObserved && currentMode != uint256(OperationalSafetyVault.Mode.Active)) {
            degradedObserved = true;
            liabilityCeilingAfterDegrade = vault.totalLiabilities();
        }

        if (!haltedObserved && currentMode == uint256(OperationalSafetyVault.Mode.Halted)) {
            haltedObserved = true;
            haltedAssets = vault.assets();
            haltedLiabilities = vault.totalLiabilities();
        }
    }
}
