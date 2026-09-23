// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "./interfaces/IPriceFeed.sol";

/// @title OracleGuard
/// @notice Validates price freshness and timestamp sanity before risk decisions.
contract OracleGuard {
    error ZeroAddress();
    error InvalidMaxAge();
    error InvalidPrice();
    error MissingTimestamp();
    error FutureTimestamp(uint256 updatedAt, uint256 currentTime);
    error StalePrice(uint256 updatedAt, uint256 currentTime, uint256 maxAge);

    IPriceFeed public immutable feed;
    uint256 public immutable maxAge;

    constructor(IPriceFeed feed_, uint256 maxAge_) {
        if (address(feed_) == address(0)) revert ZeroAddress();
        if (maxAge_ == 0) revert InvalidMaxAge();

        feed = feed_;
        maxAge = maxAge_;
    }

    function validatedPrice() public view returns (uint256 price) {
        uint256 updatedAt;
        (price, updatedAt) = feed.latestPrice();

        if (price == 0) revert InvalidPrice();
        if (updatedAt == 0) revert MissingTimestamp();
        if (updatedAt > block.timestamp) {
            revert FutureTimestamp(updatedAt, block.timestamp);
        }
        if (block.timestamp - updatedAt > maxAge) {
            revert StalePrice(updatedAt, block.timestamp, maxAge);
        }
    }
}
