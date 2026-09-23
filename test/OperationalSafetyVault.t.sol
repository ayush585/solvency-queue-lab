// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OperationalSafetyVault} from "../src/OperationalSafetyVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract OperationalSafetyVaultTest is Test {
    uint256 internal constant INACTIVITY = 1 days;
    uint256 internal constant RECOVERY_DELAY = 1 hours;

    MockERC20 internal token;
    OperationalSafetyVault internal vault;

    address internal owner = makeAddr("owner");
    address internal sequencer = makeAddr("sequencer");
    address internal guardian = makeAddr("guardian");
    address internal monitor = makeAddr("monitor");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_000_000);

        token = new MockERC20("Settlement Token", "SET");
        vault = new OperationalSafetyVault(
            address(token), owner, sequencer, guardian, monitor, INACTIVITY, RECOVERY_DELAY
        );
    }

    function test_exitOnlyBlocksNewRiskButPreservesUserWithdrawals() public {
        _deposit(alice, 100 ether);

        vm.prank(monitor);
        vault.enterExitOnly(keccak256("ANOMALY"));

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.ExitOnly));

        vm.startPrank(alice);
        token.approve(address(vault), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.ModeNotActive.selector, OperationalSafetyVault.Mode.ExitOnly
            )
        );
        vault.deposit(1 ether);
        vm.stopPrank();

        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.ModeNotActive.selector, OperationalSafetyVault.Mode.ExitOnly
            )
        );
        vault.applyStateChange(bob, 1 ether);

        vm.prank(alice);
        vault.withdraw(40 ether);

        assertEq(vault.balanceOf(alice), 60 ether);
        assertEq(vault.totalLiabilities(), 60 ether);
        assertEq(vault.assets(), 60 ether);
    }

    function test_unauthorizedAccountCannotEnterExitOnly() public {
        vm.prank(stranger);
        vm.expectRevert(OperationalSafetyVault.Unauthorized.selector);
        vault.enterExitOnly(keccak256("FAKE_ALERT"));
    }

    function test_inactivityTripActivatesExactlyAtThreshold() public {
        vm.warp(block.timestamp + INACTIVITY - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.SequencerStillFresh.selector, INACTIVITY - 1, INACTIVITY
            )
        );
        vault.enterExitOnlyIfSequencerInactive();

        vm.warp(block.timestamp + 1);
        vault.enterExitOnlyIfSequencerInactive();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.ExitOnly));
    }

    function test_heartbeatResetsInactivityClock() public {
        vm.warp(block.timestamp + INACTIVITY - 1);

        vm.prank(sequencer);
        vault.heartbeat();

        vm.warp(block.timestamp + INACTIVITY - 1);

        vm.expectRevert();
        vault.enterExitOnlyIfSequencerInactive();

        vm.warp(block.timestamp + 1);
        vault.enterExitOnlyIfSequencerInactive();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.ExitOnly));
    }

    function test_guardianHaltBlocksWithdrawals() public {
        _deposit(alice, 100 ether);

        vm.prank(guardian);
        vault.halt(keccak256("EXPLOIT"));

        vm.prank(alice);
        vm.expectRevert(OperationalSafetyVault.WithdrawalsHalted.selector);
        vault.withdraw(1 ether);

        assertEq(vault.balanceOf(alice), 100 ether);
        assertEq(vault.assets(), 100 ether);
    }

    function test_anyoneCanHaltWhenBackingFallsBelowLiabilities() public {
        _deposit(alice, 100 ether);

        deal(address(token), address(vault), 80 ether, true);

        vm.prank(stranger);
        vault.haltIfInsolvent();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.Halted));
        assertEq(vault.assets(), 80 ether);
        assertEq(vault.totalLiabilities(), 100 ether);
    }

    function test_solventVaultCannotBePermissionlesslyHalted() public {
        _deposit(alice, 100 ether);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.SolventState.selector, 100 ether, 100 ether
            )
        );
        vault.haltIfInsolvent();
    }

    function test_recoveryRequiresDelay() public {
        vm.prank(monitor);
        vault.enterExitOnly(keccak256("ANOMALY"));

        vm.prank(owner);
        vault.scheduleRecovery();

        uint256 readyAt = block.timestamp + RECOVERY_DELAY;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.RecoveryNotReady.selector, readyAt, block.timestamp
            )
        );
        vault.executeRecovery();

        vm.warp(readyAt);

        vm.prank(owner);
        vault.executeRecovery();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.Active));
    }

    function test_staleSequencerBlocksRecoveryUntilFreshHeartbeat() public {
        vm.warp(block.timestamp + INACTIVITY);
        vault.enterExitOnlyIfSequencerInactive();

        vm.prank(owner);
        vault.scheduleRecovery();

        vm.warp(block.timestamp + RECOVERY_DELAY);

        uint256 age = block.timestamp - vault.lastSequencerUpdate();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(OperationalSafetyVault.SequencerStale.selector, age, INACTIVITY)
        );
        vault.executeRecovery();

        vm.prank(sequencer);
        vault.heartbeat();

        vm.prank(owner);
        vault.executeRecovery();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.Active));
    }

    function test_insolvencyBlocksRecoveryUntilBackingIsRestored() public {
        _deposit(alice, 100 ether);
        deal(address(token), address(vault), 80 ether, true);

        vault.haltIfInsolvent();

        vm.prank(owner);
        vault.scheduleRecovery();

        vm.prank(sequencer);
        vault.heartbeat();

        vm.warp(block.timestamp + RECOVERY_DELAY);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(OperationalSafetyVault.Insolvent.selector, 80 ether, 100 ether)
        );
        vault.executeRecovery();

        token.mint(address(vault), 20 ether);

        vm.prank(owner);
        vault.executeRecovery();

        assertEq(uint256(vault.mode()), uint256(OperationalSafetyVault.Mode.Active));
        assertEq(vault.assets(), 100 ether);
    }

    function test_sequencerCannotCreateUnbackedLiabilities() public {
        _deposit(alice, 100 ether);

        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationalSafetyVault.UnbackedLiability.selector, 100 ether, 101 ether
            )
        );
        vault.applyStateChange(bob, 1 ether);
    }

    function test_sequencerCanRedistributeClaimsWithinExistingBacking() public {
        _deposit(alice, 100 ether);

        vm.prank(sequencer);
        vault.applyStateChange(alice, -40 ether);

        vm.prank(sequencer);
        vault.applyStateChange(bob, 40 ether);

        assertEq(vault.balanceOf(alice), 60 ether);
        assertEq(vault.balanceOf(bob), 40 ether);
        assertEq(vault.totalLiabilities(), 100 ether);
        assertEq(vault.assets(), 100 ether);
    }

    function _deposit(address user, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amount);
        vm.stopPrank();
    }
}
