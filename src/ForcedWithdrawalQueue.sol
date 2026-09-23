// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";

/// @title ForcedWithdrawalQueue
/// @notice FIFO forced-withdrawal queue with failure isolation and retryable failed entries.
/// @dev Processing a failing head request advances global progress while preserving the user's Pool claim.
contract ForcedWithdrawalQueue {
    enum Status {
        Pending,
        Processing,
        Processed,
        Failed
    }

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
    error NotFailed(uint256 requestId, Status status);
    error ReentrantCall();

    event Requested(
        uint256 indexed requestId,
        address indexed user,
        address indexed token,
        address recipient,
        uint256 amount
    );
    event Processed(uint256 indexed requestId);
    event Failed(uint256 indexed requestId);
    event Retried(uint256 indexed requestId, bool success);

    Pool public immutable pool;
    Request[] public requests;
    mapping(uint256 requestId => Status status) public statusOf;
    uint256 public nextToProcess;

    bool private locked;

    modifier nonReentrant() {
        if (locked) revert ReentrantCall();
        locked = true;
        _;
        locked = false;
    }

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

    /// @notice Attempts the current FIFO head exactly once and always advances the global cursor.
    /// @return requestId The queue entry attempted.
    /// @return success Whether Pool execution succeeded.
    function processNext() external nonReentrant returns (uint256 requestId, bool success) {
        requestId = nextToProcess;
        if (requestId >= requests.length) revert EmptyQueue();

        statusOf[requestId] = Status.Processing;

        // Advance before the external call. If the call fails we intentionally keep
        // global progress, while the failed Pool transaction preserves the user's claim.
        nextToProcess = requestId + 1;

        Request memory queued = requests[requestId];

        try pool.withdrawFor(queued.user, queued.token, queued.recipient, queued.amount) {
            statusOf[requestId] = Status.Processed;
            emit Processed(requestId);
            return (requestId, true);
        } catch {
            statusOf[requestId] = Status.Failed;
            emit Failed(requestId);
            return (requestId, false);
        }
    }

    /// @notice Retries an isolated failed request without moving the FIFO cursor.
    function retryFailed(uint256 requestId) external nonReentrant returns (bool success) {
        Status current = statusOf[requestId];
        if (current != Status.Failed) revert NotFailed(requestId, current);

        Request memory queued = requests[requestId];
        statusOf[requestId] = Status.Processing;

        try pool.withdrawFor(queued.user, queued.token, queued.recipient, queued.amount) {
            statusOf[requestId] = Status.Processed;
            emit Retried(requestId, true);
            return true;
        } catch {
            statusOf[requestId] = Status.Failed;
            emit Retried(requestId, false);
            return false;
        }
    }
}
