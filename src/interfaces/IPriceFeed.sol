// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceFeed {
    function latestPrice() external view returns (uint256 price, uint256 updatedAt);
}
