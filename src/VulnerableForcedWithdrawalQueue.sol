// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";

/// @notice Intentionally vulnerable strict-FIFO withdrawal queue.
/// @dev A recipient-specific token revert at the head prevents the cursor from advancing.
contract VulnerableForcedWithdrawalQueue {
    struct Request {
        address user;
        address token;
        address recipient;
        uint256 amount;
    }

    error ZeroAddress();
    error ZeroAmount();
    error EmptyQueue();
    error InsufficientClaim(uint256 claim, uint256 requested);

    event Requested(
        uint256 indexed requestId,
        address indexed user,
        address indexed token,
        address recipient,
        uint256 amount
    );
    event Processed(uint256 indexed requestId);

    Pool public immutable pool;
    Request[] public requests;
    uint256 public nextToProcess;

    constructor(Pool pool_) {
        if (address(pool_) == address(0)) revert ZeroAddress();
        pool = pool_;
    }

    function request(address token, address recipient, uint256 amount)
        external
        returns (uint256 requestId)
    {
        if (token == address(0) || recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 claim = pool.balanceOf(token, msg.sender);
        if (claim < amount) revert InsufficientClaim(claim, amount);

        requestId = requests.length;
        requests.push(
            Request({user: msg.sender, token: token, recipient: recipient, amount: amount})
        );

        emit Requested(requestId, msg.sender, token, recipient, amount);
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    function processNext() external {
        uint256 requestId = nextToProcess;
        if (requestId >= requests.length) revert EmptyQueue();

        Request memory queued = requests[requestId];

        // BUG: if this external call reverts, nextToProcess is never incremented.
        // Every later request remains permanently stuck behind the failing head entry.
        pool.withdrawFor(queued.user, queued.token, queued.recipient, queued.amount);

        nextToProcess = requestId + 1;
        emit Processed(requestId);
    }
}
