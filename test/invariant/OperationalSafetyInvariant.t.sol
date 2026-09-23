// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {OperationalSafetyVault} from "../../src/OperationalSafetyVault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {OperationalSafetyHandler} from "./OperationalSafetyHandler.sol";

contract OperationalSafetyInvariantTest is StdInvariant, Test {
    MockERC20 internal token;
    OperationalSafetyVault internal vault;
    OperationalSafetyHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal sequencer = makeAddr("sequencer");
    address internal guardian = makeAddr("guardian");
    address internal monitor = makeAddr("monitor");

    address[] internal actors;

    function setUp() public {
        vm.warp(1_000_000);

        token = new MockERC20("Settlement Token", "SET");
        vault = new OperationalSafetyVault(
            address(token),
            owner,
            sequencer,
            guardian,
            monitor,
            1 days,
            1 hours
        );

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        address[] memory handlerActors = new address[](actors.length);
        for (uint256 i; i < actors.length; ++i) {
            handlerActors[i] = actors[i];
        }

        handler = new OperationalSafetyHandler(
            vault,
            token,
            sequencer,
            guardian,
            monitor,
            handlerActors
        );

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = OperationalSafetyHandler.deposit.selector;
        selectors[1] = OperationalSafetyHandler.withdraw.selector;
        selectors[2] = OperationalSafetyHandler.backedCredit.selector;
        selectors[3] = OperationalSafetyHandler.redistribute.selector;
        selectors[4] = OperationalSafetyHandler.heartbeat.selector;
        selectors[5] = OperationalSafetyHandler.advanceTime.selector;
        selectors[6] = OperationalSafetyHandler.tripInactive.selector;
        selectors[7] = OperationalSafetyHandler.monitorExitOnly.selector;
        selectors[8] = OperationalSafetyHandler.guardianHalt.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_assetsAlwaysCoverLiabilities() public view {
        assertGe(vault.assets(), vault.totalLiabilities(), "operational vault became insolvent");
    }

    function invariant_userClaimsEqualTotalLiabilities() public view {
        uint256 claims;
        for (uint256 i; i < actors.length; ++i) {
            claims += vault.balanceOf(actors[i]);
        }

        assertEq(claims, vault.totalLiabilities(), "user claims diverged from liabilities");
    }

    function invariant_allMintedAssetsRemainAccountedFor() public view {
        uint256 accounted = vault.assets();

        for (uint256 i; i < actors.length; ++i) {
            accounted += token.balanceOf(actors[i]);
        }

        assertEq(accounted, handler.totalMinted(), "settlement assets disappeared");
        assertEq(token.totalSupply(), handler.totalMinted(), "unexpected mint or burn occurred");
    }

    function invariant_degradedModeNeverIncreasesLiabilities() public view {
        if (!handler.degradedObserved()) return;

        assertLe(
            vault.totalLiabilities(),
            handler.liabilityCeilingAfterDegrade(),
            "degraded mode created new liabilities"
        );
    }

    function invariant_haltedModeFreezesFinancialState() public view {
        if (!handler.haltedObserved()) return;

        assertEq(vault.assets(), handler.haltedAssets(), "halted mode moved assets");
        assertEq(
            vault.totalLiabilities(),
            handler.haltedLiabilities(),
            "halted mode changed liabilities"
        );
    }

    function invariant_modeNeverDeescalatesInHarness() public view {
        assertEq(
            uint256(vault.mode()),
            handler.highestMode(),
            "incident mode de-escalated without recovery flow"
        );
    }
}
