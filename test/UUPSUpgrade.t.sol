// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeVaultV1} from "../src/upgrade/UpgradeVaultV1.sol";
import {UpgradeVaultV2} from "../src/upgrade/UpgradeVaultV2.sol";
import {BadUpgradeVaultV2} from "../src/upgrade/BadUpgradeVaultV2.sol";
import {NonUUPSImplementation} from "../src/upgrade/NonUUPSImplementation.sol";

contract UUPSUpgradeTest is Test {
    UpgradeVaultV1 internal implementationV1;
    UpgradeVaultV2 internal implementationV2;
    BadUpgradeVaultV2 internal badImplementationV2;
    NonUUPSImplementation internal nonUups;

    address internal owner = makeAddr("owner");
    address internal attacker = makeAddr("attacker");
    address internal alice = makeAddr("alice");
    address internal guardian = makeAddr("guardian");

    function setUp() public {
        implementationV1 = new UpgradeVaultV1();
        implementationV2 = new UpgradeVaultV2();
        badImplementationV2 = new BadUpgradeVaultV2();
        nonUups = new NonUUPSImplementation();
    }

    function test_proxyInitializationAndV1State() public {
        UpgradeVaultV1 vault = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vault.credit(alice, 777 ether);

        assertEq(vault.owner(), owner);
        assertEq(vault.collateralFactorBps(), 1_500);
        assertEq(vault.totalLiabilities(), 777 ether);
        assertEq(vault.balanceOf(alice), 777 ether);
        assertEq(vault.version(), 1);
    }

    function test_implementationInstanceCannotBeInitializedDirectly() public {
        vm.expectRevert(UpgradeVaultV1.AlreadyInitialized.selector);
        implementationV1.initialize(owner, 1_500);

        vm.expectRevert(UpgradeVaultV1.AlreadyInitialized.selector);
        implementationV2.initialize(owner, 1_500);
    }

    function test_unauthorizedAccountCannotUpgradeProxy() public {
        UpgradeVaultV1 vault = _deployV1Proxy(owner, 1_500);

        vm.prank(attacker);
        vm.expectRevert(UpgradeVaultV1.Unauthorized.selector);
        vault.upgradeToAndCall(address(implementationV2), bytes(""));

        assertEq(vault.version(), 1);
    }

    function test_safeUpgradePreservesStateAndAppendsNewFields() public {
        UpgradeVaultV1 vaultV1 = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vaultV1.credit(alice, 777 ether);

        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2), bytes(""));

        UpgradeVaultV2 vaultV2 = UpgradeVaultV2(address(vaultV1));

        assertEq(vaultV2.version(), 2);
        assertEq(vaultV2.owner(), owner);
        assertEq(vaultV2.collateralFactorBps(), 1_500);
        assertEq(vaultV2.totalLiabilities(), 777 ether);
        assertEq(vaultV2.balanceOf(alice), 777 ether);
        assertEq(vaultV2.guardian(), address(0));
        assertFalse(vaultV2.paused());

        vm.prank(owner);
        vaultV2.initializeV2(guardian);

        assertEq(vaultV2.guardian(), guardian);

        vm.prank(guardian);
        vaultV2.setPaused(true);

        assertTrue(vaultV2.paused());
    }

    function test_v2InitializerCannotRunTwice() public {
        UpgradeVaultV1 vaultV1 = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2), bytes(""));

        UpgradeVaultV2 vaultV2 = UpgradeVaultV2(address(vaultV1));

        vm.prank(owner);
        vaultV2.initializeV2(guardian);

        vm.prank(owner);
        vm.expectRevert(UpgradeVaultV2.V2AlreadyInitialized.selector);
        vaultV2.initializeV2(makeAddr("second-guardian"));
    }

    function test_nonUUPSImplementationIsRejected() public {
        UpgradeVaultV1 vault = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vm.expectRevert();
        vault.upgradeToAndCall(address(nonUups), bytes(""));

        assertEq(vault.version(), 1);
        assertEq(vault.owner(), owner);
    }

    function test_badStorageUpgradeCorruptsEveryShiftedField() public {
        UpgradeVaultV1 vaultV1 = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vaultV1.credit(alice, 777 ether);

        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(badImplementationV2), bytes(""));

        BadUpgradeVaultV2 bad = BadUpgradeVaultV2(address(vaultV1));

        // slot 0 used to contain owner.
        assertEq(bad.emergencyThreshold(), uint256(uint160(owner)));

        // slot 1 used to contain collateralFactorBps.
        assertEq(bad.owner(), address(uint160(1_500)));

        // slot 2 used to contain totalLiabilities.
        assertEq(bad.collateralFactorBps(), 777 ether);

        // slot 3 used to be the mapping's base slot, whose direct slot value is zero.
        assertEq(bad.totalLiabilities(), 0);

        // The mapping moved from slot 3 to slot 4, so the old entry is now unreachable.
        assertEq(bad.balanceOf(alice), 0);
    }

    function test_badStorageUpgradeCanLockOriginalAdminOutOfRecovery() public {
        UpgradeVaultV1 vaultV1 = _deployV1Proxy(owner, 1_500);

        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(badImplementationV2), bytes(""));

        BadUpgradeVaultV2 bad = BadUpgradeVaultV2(address(vaultV1));

        assertTrue(bad.owner() != owner);

        vm.prank(owner);
        vm.expectRevert(BadUpgradeVaultV2.Unauthorized.selector);
        bad.upgradeToAndCall(address(implementationV2), bytes(""));
    }

    function test_upgradeFunctionCannotBeCalledOnImplementationDirectly() public {
        vm.prank(owner);
        vm.expectRevert();
        implementationV1.upgradeToAndCall(address(implementationV2), bytes(""));
    }

    function _deployV1Proxy(address owner_, uint256 collateralFactorBps_)
        internal
        returns (UpgradeVaultV1 vault)
    {
        bytes memory initData =
            abi.encodeCall(UpgradeVaultV1.initialize, (owner_, collateralFactorBps_));

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        vault = UpgradeVaultV1(address(proxy));
    }
}
