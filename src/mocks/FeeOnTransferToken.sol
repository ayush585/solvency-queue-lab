// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockERC20} from "./MockERC20.sol";

/// @notice Burns a fee from every transfer to model non-standard ERC-20 accounting behavior.
contract FeeOnTransferToken is MockERC20 {
    uint256 public immutable feeBps;
    uint256 internal constant BPS = 10_000;

    constructor(uint256 feeBps_) MockERC20("Fee Token", "FEE") {
        require(feeBps_ < BPS, "BAD_FEE");
        feeBps = feeBps_;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(to != address(0), "ZERO_ADDRESS");
        require(balanceOf[from] >= amount, "BALANCE");

        uint256 fee = (amount * feeBps) / BPS;
        uint256 received = amount - fee;

        balanceOf[from] -= amount;
        balanceOf[to] += received;
        totalSupply -= fee;

        emit Transfer(from, to, received);
        if (fee != 0) emit Transfer(from, address(0), fee);
    }
}
