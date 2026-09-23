// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FundingMarket} from "../../src/FundingMarket.sol";

contract FundingHandler is Test {
    FundingMarket public immutable market;
    address public immutable longAccount;
    address public immutable shortAccount;
    address public immutable marketOwner;

    constructor(FundingMarket market_, address longAccount_, address shortAccount_) {
        market = market_;
        longAccount = longAccount_;
        shortAccount = shortAccount_;
        marketOwner = market_.owner();
    }

    function setRate(int64 rawRate) external {
        int256 rate = int256(rawRate);
        rate = bound(rate, -market.MAX_ABS_RATE_PER_SECOND(), market.MAX_ABS_RATE_PER_SECOND());

        vm.prank(marketOwner);
        market.setFundingRate(rate);
    }

    function advanceTime(uint32 rawSeconds) external {
        uint256 secondsForward = bound(uint256(rawSeconds), 1, 1 days);
        vm.warp(block.timestamp + secondsForward);
    }

    function accrue() external {
        market.accrueFunding();
    }

    function settleLong() external {
        market.settleFunding(longAccount);
    }

    function settleShort() external {
        market.settleFunding(shortAccount);
    }
}
