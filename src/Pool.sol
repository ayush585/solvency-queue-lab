// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @title Pool
/// @notice Minimal solvency-focused asset pool for invariant-testing practice.
/// @dev The contract intentionally supports only transfer semantics it can account for exactly.
contract Pool {
    using SafeTransferLib for address;

    error ZeroAmount();
    error ZeroReceived();
    error InsufficientBalance();
    error UnexpectedTransferBehavior(uint256 expected, uint256 poolSpent, uint256 userReceived);

    event Deposited(
        address indexed user,
        address indexed token,
        uint256 requestedAmount,
        uint256 creditedAmount
    );
    event Withdrawn(address indexed user, address indexed token, uint256 amount);

    mapping(address token => mapping(address user => uint256 amount)) public balanceOf;
    mapping(address token => uint256 amount) public totalLiabilities;

    function deposit(address token, uint256 requestedAmount) external returns (uint256 creditedAmount) {
        if (requestedAmount == 0) revert ZeroAmount();

        uint256 assetsBefore = IERC20Minimal(token).balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), requestedAmount);
        uint256 assetsAfter = IERC20Minimal(token).balanceOf(address(this));

        creditedAmount = assetsAfter - assetsBefore;
        if (creditedAmount == 0) revert ZeroReceived();

        balanceOf[token][msg.sender] += creditedAmount;
        totalLiabilities[token] += creditedAmount;

        emit Deposited(msg.sender, token, requestedAmount, creditedAmount);
    }

    function withdraw(address token, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        uint256 claim = balanceOf[token][msg.sender];
        if (claim < amount) revert InsufficientBalance();

        uint256 poolAssetsBefore = IERC20Minimal(token).balanceOf(address(this));
        uint256 userAssetsBefore = IERC20Minimal(token).balanceOf(msg.sender);

        // Effects happen before interaction; any transfer mismatch below reverts atomically.
        balanceOf[token][msg.sender] = claim - amount;
        totalLiabilities[token] -= amount;

        token.safeTransfer(msg.sender, amount);

        uint256 poolAssetsAfter = IERC20Minimal(token).balanceOf(address(this));
        uint256 userAssetsAfter = IERC20Minimal(token).balanceOf(msg.sender);

        uint256 poolSpent = poolAssetsBefore - poolAssetsAfter;
        uint256 userReceived = userAssetsAfter - userAssetsBefore;

        if (poolSpent != amount || userReceived != amount) {
            revert UnexpectedTransferBehavior(amount, poolSpent, userReceived);
        }

        emit Withdrawn(msg.sender, token, amount);
    }
}
