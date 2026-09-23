// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FundingMarket} from "../src/FundingMarket.sol";

contract FundingMarketTest is Test {
    FundingMarket internal market;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vm.warp(1_000_000);
        market = new FundingMarket();
    }

    function test_equalOpenInterestTransfersFundingZeroSum() public {
        _open(alice, true, 10_000 ether);
        _open(bob, false, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);

        assertEq(market.pendingFunding(alice), -100 ether);
        assertEq(market.pendingFunding(bob), 100 ether);

        market.accrueFunding();

        assertEq(market.totalAccruedFundingPaid(), 100 ether);
        assertEq(market.totalAccruedFundingReceived(), 100 ether);
    }

    function test_receivingSideScalesWhenOpenInterestIsUnequal() public {
        _open(alice, true, 20_000 ether);
        _open(bob, false, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);

        assertEq(market.pendingFunding(alice), -200 ether);
        assertEq(market.pendingFunding(bob), 200 ether);
    }

    function test_checkpointPreventsDoubleCharging() public {
        _open(alice, true, 10_000 ether);
        _open(bob, false, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);

        assertEq(market.settleFunding(alice), -100 ether);
        assertEq(market.settleFunding(bob), 100 ether);

        assertEq(market.settleFunding(alice), 0);
        assertEq(market.settleFunding(bob), 0);

        vm.warp(block.timestamp + 100);

        assertEq(market.settleFunding(alice), -100 ether);
        assertEq(market.settleFunding(bob), 100 ether);
    }

    function test_newPositionDoesNotInheritHistoricalFunding() public {
        _open(alice, true, 10_000 ether);
        _open(bob, false, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);
        market.accrueFunding();

        _open(carol, false, 10_000 ether);

        assertEq(market.pendingFunding(carol), 0);
        assertEq(market.pendingFunding(alice), -100 ether);
        assertEq(market.pendingFunding(bob), 100 ether);
    }

    function test_rateReversalCanNetFundingBackTowardZero() public {
        _open(alice, true, 10_000 ether);
        _open(bob, false, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);
        market.setFundingRate(-1e14);

        vm.warp(block.timestamp + 100);

        assertEq(market.pendingFunding(alice), 0);
        assertEq(market.pendingFunding(bob), 0);
        assertEq(market.totalAccruedFundingPaid(), 100 ether);
        assertEq(market.totalAccruedFundingReceived(), 100 ether);

        market.accrueFunding();

        assertEq(market.totalAccruedFundingPaid(), 200 ether);
        assertEq(market.totalAccruedFundingReceived(), 200 ether);
    }

    function test_noFundingAccruesUntilBothSidesHaveOpenInterest() public {
        _open(alice, true, 10_000 ether);

        market.setFundingRate(1e14);
        vm.warp(block.timestamp + 100);

        assertEq(market.pendingFunding(alice), 0);

        _open(bob, false, 10_000 ether);
        vm.warp(block.timestamp + 100);

        assertEq(market.pendingFunding(alice), -100 ether);
        assertEq(market.pendingFunding(bob), 100 ether);
    }

    function test_rateBoundIsEnforced() public {
        vm.expectRevert(FundingMarket.RateTooLarge.selector);
        market.setFundingRate(1e15 + 1);
    }

    function testFuzz_unequalOpenInterestConservesFundingWithinRoundingDust(
        uint96 rawLongSize,
        uint96 rawShortSize,
        uint64 rawRate,
        uint32 rawDuration
    ) public {
        uint256 longSize = bound(uint256(rawLongSize), 1_000 ether, 1e27);
        uint256 shortSize = bound(uint256(rawShortSize), 1_000 ether, 1e27);
        int256 rate = int256(bound(uint256(rawRate), 1e8, 1e14));
        uint256 duration = bound(uint256(rawDuration), 1, 1_000_000);

        _open(alice, true, longSize);
        _open(bob, false, shortSize);

        market.setFundingRate(rate);
        vm.warp(block.timestamp + duration);

        int256 net = market.pendingFunding(alice) + market.pendingFunding(bob);
        uint256 dustBound = (longSize / 1e18) + (shortSize / 1e18) + 2;

        assertLe(_abs(net), dustBound);
    }

    function _open(address account, bool isLong, uint256 sizeUsd) internal {
        vm.prank(account);
        market.openPosition(isLong, sizeUsd);
    }

    function _abs(int256 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -value : value);
    }
}
