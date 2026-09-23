// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @notice Intentionally vulnerable accounting model used only for exploit demonstration.
/// @dev It credits the caller-supplied amount instead of the amount actually received.
contract VulnerablePool {
    using SafeTransferLib for address;

    error InsufficientBalance();

    mapping(address token => mapping(address user => uint256 amount)) public balanceOf;
    mapping(address token => uint256 amount) public totalLiabilities;

    function deposit(address token, uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);

        // BUG: assumes requested transfer amount == amount actually received.
        balanceOf[token][msg.sender] += amount;
        totalLiabilities[token] += amount;
    }

    function withdraw(address token, uint256 amount) external {
        uint256 claim = balanceOf[token][msg.sender];
        if (claim < amount) revert InsufficientBalance();

        balanceOf[token][msg.sender] = claim - amount;
        totalLiabilities[token] -= amount;
        token.safeTransfer(msg.sender, amount);
    }
}
