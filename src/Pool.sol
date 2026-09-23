// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @title Pool
/// @notice Minimal solvency-focused asset pool for invariant-testing practice.
/// @dev The contract intentionally supports only transfer semantics it can account for exactly.
contract Pool {
    using SafeTransferLib for address;

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroReceived();
    error InsufficientBalance();
    error UnexpectedTransferBehavior(uint256 expected, uint256 poolSpent, uint256 userReceived);

    event Deposited(
        address indexed user, address indexed token, uint256 requestedAmount, uint256 creditedAmount
    );
    event Withdrawn(
        address indexed user, address indexed token, address indexed recipient, uint256 amount
    );
    event WithdrawalOperatorUpdated(address indexed operator, bool allowed);

    address public immutable owner;

    mapping(address token => mapping(address user => uint256 amount)) public balanceOf;
    mapping(address token => uint256 amount) public totalLiabilities;
    mapping(address operator => bool allowed) public withdrawalOperator;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyWithdrawalOperator() {
        if (!withdrawalOperator[msg.sender]) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setWithdrawalOperator(address operator, bool allowed) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        withdrawalOperator[operator] = allowed;
        emit WithdrawalOperatorUpdated(operator, allowed);
    }

    function deposit(address token, uint256 requestedAmount)
        external
        returns (uint256 creditedAmount)
    {
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
        _withdraw(msg.sender, token, msg.sender, amount);
    }

    /// @notice Allows an explicitly authorized withdrawal manager to execute a user's claim.
    /// @dev The operator is trusted only to choose an already-authorized user/recipient/amount tuple.
    /// Signature validation belongs in the operator contract, not in Pool.
    function withdrawFor(address user, address token, address recipient, uint256 amount)
        external
        onlyWithdrawalOperator
    {
        _withdraw(user, token, recipient, amount);
    }

    function _withdraw(address user, address token, address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 claim = balanceOf[token][user];
        if (claim < amount) revert InsufficientBalance();

        uint256 poolAssetsBefore = IERC20Minimal(token).balanceOf(address(this));
        uint256 recipientAssetsBefore = IERC20Minimal(token).balanceOf(recipient);

        // Effects happen before interaction; any transfer mismatch below reverts atomically.
        balanceOf[token][user] = claim - amount;
        totalLiabilities[token] -= amount;

        token.safeTransfer(recipient, amount);

        uint256 poolAssetsAfter = IERC20Minimal(token).balanceOf(address(this));
        uint256 recipientAssetsAfter = IERC20Minimal(token).balanceOf(recipient);

        uint256 poolSpent = poolAssetsBefore - poolAssetsAfter;
        uint256 recipientReceived = recipientAssetsAfter - recipientAssetsBefore;

        if (poolSpent != amount || recipientReceived != amount) {
            revert UnexpectedTransferBehavior(amount, poolSpent, recipientReceived);
        }

        emit Withdrawn(user, token, recipient, amount);
    }
}
