// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

contract DepositInbox {
    using SafeTransferLib for address;

    struct Receipt {
        address user;
        uint256 amount;
        bool consumed;
        bool exists;
    }

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error DuplicateDeposit(bytes32 depositId);
    error UnknownDeposit(bytes32 depositId);
    error DepositAlreadyConsumed(bytes32 depositId);
    error ConsumerAlreadySet();
    error UnexpectedReceived(uint256 expected, uint256 actual);

    Pool public immutable pool;
    address public immutable token;
    address public immutable owner;
    address public consumer;

    mapping(bytes32 depositId => Receipt receipt) public receipts;

    constructor(Pool pool_, address token_) {
        if (address(pool_) == address(0) || token_ == address(0)) revert ZeroAddress();
        pool = pool_;
        token = token_;
        owner = msg.sender;
    }

    function setConsumer(address consumer_) external {
        if (msg.sender != owner) revert Unauthorized();
        if (consumer != address(0)) revert ConsumerAlreadySet();
        if (consumer_ == address(0)) revert ZeroAddress();
        consumer = consumer_;
    }

    function lockDeposit(bytes32 depositId, address user, uint256 amount) external {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (receipts[depositId].exists) revert DuplicateDeposit(depositId);

        uint256 beforeAssets = IERC20Minimal(token).balanceOf(address(pool));
        token.safeTransferFrom(msg.sender, address(pool), amount);
        uint256 received = IERC20Minimal(token).balanceOf(address(pool)) - beforeAssets;
        if (received != amount) revert UnexpectedReceived(amount, received);

        receipts[depositId] = Receipt(user, amount, false, true);
    }

    function consume(bytes32 depositId) external returns (address user, uint256 amount) {
        if (msg.sender != consumer) revert Unauthorized();

        Receipt storage receipt = receipts[depositId];
        if (!receipt.exists) revert UnknownDeposit(depositId);
        if (receipt.consumed) revert DepositAlreadyConsumed(depositId);

        receipt.consumed = true;
        return (receipt.user, receipt.amount);
    }
}
