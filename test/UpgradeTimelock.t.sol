// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeVaultV1} from "../src/upgrade/UpgradeVaultV1.sol";
import {UpgradeVaultV2} from "../src/upgrade/UpgradeVaultV2.sol";
import {BadUpgradeVaultV2} from "../src/upgrade/BadUpgradeVaultV2.sol";

contract UpgradeTimelockTest is Test {
    uint256 internal constant DELAY = 2 days;

    UpgradeVaultV1 internal implementationV1;
    UpgradeVaultV2 internal implementationV2;
    BadUpgradeVaultV2 internal badImplementationV2;
    TimelockController internal timelock;
    UpgradeVaultV1 internal vault;

    address internal proposer = makeAddr("proposer");
    address internal executor = makeAddr("executor");
    address internal admin = makeAddr("admin");
    address internal attacker = makeAddr("attacker");
    address internal alice = makeAddr("alice");
    address internal guardian = makeAddr("guardian");

    function setUp() public {
        implementationV1 = new UpgradeVaultV1();
        implementationV2 = new UpgradeVaultV2();
        badImplementationV2 = new BadUpgradeVaultV2();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new TimelockController(DELAY, proposers, executors, admin);

        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        vm.prank(admin);
        timelock.grantRole(cancellerRole, proposer);

        bytes memory initData =
            abi.encodeCall(UpgradeVaultV1.initialize, (address(timelock), 1_500));

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        vault = UpgradeVaultV1(address(proxy));
    }

    function test_directEOACannotBypassTimelockUpgradeAuthority() public {
        vm.prank(attacker);
        vm.expectRevert(UpgradeVaultV1.Unauthorized.selector);
        vault.upgradeToAndCall(address(implementationV2), bytes(""));

        assertEq(vault.version(), 1);
        assertEq(vault.owner(), address(timelock));
    }

    function test_onlyProposerCanScheduleUpgrade() public {
        bytes memory data = _safeUpgradeData();

        vm.prank(attacker);
        vm.expectRevert();
        timelock.schedule(
            address(vault), 0, data, bytes32(0), keccak256("unauthorized-upgrade"), DELAY
        );
    }

    function test_upgradeCannotExecuteBeforeDelay() public {
        bytes32 salt = keccak256("safe-upgrade");
        bytes memory data = _safeUpgradeData();

        _schedule(data, salt);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), salt);

        assertEq(vault.version(), 1);
    }

    function test_timelockedUpgradePreservesStateAndInitializesV2Atomically() public {
        vm.prank(address(timelock));
        vault.credit(alice, 777 ether);

        bytes32 salt = keccak256("safe-upgrade");
        bytes memory data = _safeUpgradeData();

        _schedule(data, salt);
        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(vault), 0, data, bytes32(0), salt);

        UpgradeVaultV2 upgraded = UpgradeVaultV2(address(vault));

        assertEq(upgraded.version(), 2);
        assertEq(upgraded.owner(), address(timelock));
        assertEq(upgraded.collateralFactorBps(), 1_500);
        assertEq(upgraded.totalLiabilities(), 777 ether);
        assertEq(upgraded.balanceOf(alice), 777 ether);
        assertEq(upgraded.guardian(), guardian);
    }

    function test_cancelledUpgradeCannotExecute() public {
        bytes32 salt = keccak256("cancelled-upgrade");
        bytes memory data = _safeUpgradeData();

        _schedule(data, salt);

        bytes32 operationId =
            timelock.hashOperation(address(vault), 0, data, bytes32(0), salt);

        vm.prank(proposer);
        timelock.cancel(operationId);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), salt);

        assertEq(vault.version(), 1);
    }

    function test_timelockDoesNotMakeStorageIncompatibleUpgradeSafe() public {
        vm.prank(address(timelock));
        vault.credit(alice, 777 ether);

        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", address(badImplementationV2), bytes("")
        );
        bytes32 salt = keccak256("bad-storage-upgrade");

        _schedule(data, salt);
        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(vault), 0, data, bytes32(0), salt);

        BadUpgradeVaultV2 bad = BadUpgradeVaultV2(address(vault));

        assertEq(bad.emergencyThreshold(), uint256(uint160(address(timelock))));
        assertEq(bad.owner(), address(uint160(1_500)));
        assertEq(bad.collateralFactorBps(), 777 ether);
        assertEq(bad.totalLiabilities(), 0);
        assertEq(bad.balanceOf(alice), 0);
    }

    function test_unscheduledOperationCannotExecuteEvenAfterTimePasses() public {
        bytes32 salt = keccak256("never-scheduled");
        bytes memory data = _safeUpgradeData();

        vm.warp(block.timestamp + 30 days);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(vault), 0, data, bytes32(0), salt);

        assertEq(vault.version(), 1);
    }

    function _schedule(bytes memory data, bytes32 salt) internal {
        vm.prank(proposer);
        timelock.schedule(address(vault), 0, data, bytes32(0), salt, DELAY);
    }

    function _safeUpgradeData() internal view returns (bytes memory) {
        bytes memory initializeV2Data = abi.encodeCall(UpgradeVaultV2.initializeV2, (guardian));

        return abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", address(implementationV2), initializeV2Data
        );
    }
}
