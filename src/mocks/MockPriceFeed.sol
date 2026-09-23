// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    uint256 public price;
    uint256 public updatedAt;

    function setPrice(uint256 price_, uint256 updatedAt_) external {
        price = price_;
        updatedAt = updatedAt_;
    }

    function latestPrice() external view returns (uint256, uint256) {
        return (price, updatedAt);
    }
}
