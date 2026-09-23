// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

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
    event SettlementOperatorUpdated(address indexed operator, bool allowed);
    event StateChangeApplied(address indexed user, address indexed token, int256 delta);
    event CrossChainDepositCredited(address indexed user, address indexed token, uint256 amount);

    address public immutable owner;

    mapping(address token => mapping(address user => uint256 amount)) public balanceOf;
    mapping(address token => uint256 amount) public totalLiabilities;
    mapping(address operator => bool allowed) public withdrawalOperator;
    mapping(address operator => bool allowed) public settlementOperator;

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyWithdrawalOperator() {
        if (!withdrawalOperator[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlySettlementOperator() {
        if (!settlementOperator[msg.sender]) revert Unauthorized();
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

    function setSettlementOperator(address operator, bool allowed) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        settlementOperator[operator] = allowed;
        emit SettlementOperatorUpdated(operator, allowed);
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

    function withdrawFor(address user, address token, address recipient, uint256 amount)
        external
        onlyWithdrawalOperator
    {
        _withdraw(user, token, recipient, amount);
    }

    function applyStateChange(address user, address token, int256 delta)
        external
        onlySettlementOperator
    {
        if (user == address(0) || token == address(0)) revert ZeroAddress();
        if (delta == 0) return;

        if (delta > 0) {
            uint256 amount = uint256(delta);
            balanceOf[token][user] += amount;
            totalLiabilities[token] += amount;
        } else {
            uint256 amount = uint256(-delta);
            uint256 claim = balanceOf[token][user];
            if (claim < amount) revert InsufficientBalance();

            balanceOf[token][user] = claim - amount;
            totalLiabilities[token] -= amount;
        }

        emit StateChangeApplied(user, token, delta);
    }

    function creditCrossChainDeposit(address user, address token, uint256 amount)
        external
        onlySettlementOperator
    {
        if (user == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        balanceOf[token][user] += amount;
        totalLiabilities[token] += amount;

        emit CrossChainDepositCredited(user, token, amount);
    }

    function _withdraw(address user, address token, address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 claim = balanceOf[token][user];
        if (claim < amount) revert InsufficientBalance();

        uint256 poolAssetsBefore = IERC20Minimal(token).balanceOf(address(this));
        uint256 recipientAssetsBefore = IERC20Minimal(token).balanceOf(recipient);

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
