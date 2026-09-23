// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FundingMarket} from "../../src/FundingMarket.sol";
import {FundingHandler} from "./FundingHandler.sol";

contract FundingInvariantTest is StdInvariant, Test {
    FundingMarket internal market;
    FundingHandler internal handler;

    address internal longAccount = makeAddr("long-account");
    address internal shortAccount = makeAddr("short-account");

    function setUp() public {
        vm.warp(1_000_000);

        market = new FundingMarket();

        vm.prank(longAccount);
        market.openPosition(true, 10_000 ether);

        vm.prank(shortAccount);
        market.openPosition(false, 10_000 ether);

        handler = new FundingHandler(market, longAccount, shortAccount);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = FundingHandler.setRate.selector;
        selectors[1] = FundingHandler.advanceTime.selector;
        selectors[2] = FundingHandler.accrue.selector;
        selectors[3] = FundingHandler.settleLong.selector;
        selectors[4] = FundingHandler.settleShort.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_marketLevelFundingPaidEqualsReceived() public view {
        assertEq(
            market.totalAccruedFundingPaid(),
            market.totalAccruedFundingReceived(),
            "market funding created or destroyed value"
        );
    }

    function invariant_equalOpenInterestFundingNetsToZero() public view {
        (,,, int256 longSettled,) = market.positions(longAccount);
        (,,, int256 shortSettled,) = market.positions(shortAccount);

        int256 longTotal = longSettled + market.pendingFunding(longAccount);
        int256 shortTotal = shortSettled + market.pendingFunding(shortAccount);

        assertEq(longTotal + shortTotal, 0, "equal-OI funding failed to net to zero");
    }

    function invariant_openInterestRemainsBalanced() public view {
        assertEq(
            market.totalLongOpenInterest(),
            market.totalShortOpenInterest(),
            "test market OI balance drifted"
        );
    }
}
