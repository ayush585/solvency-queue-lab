// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ForcedWithdrawalQueue} from "../../src/ForcedWithdrawalQueue.sol";
import {Pool} from "../../src/Pool.sol";
import {BlacklistToken} from "../../src/mocks/BlacklistToken.sol";

contract QueueHandler is Test {
    ForcedWithdrawalQueue public immutable queue;
    Pool public immutable pool;
    BlacklistToken public immutable token;

    address[] public actors;

    mapping(address actor => uint256 amount) public totalDeposited;
    mapping(address actor => uint256 amount) public totalPaid;

    bool public cursorDecreased;
    uint256 public lastObservedCursor;

    constructor(
        ForcedWithdrawalQueue queue_,
        Pool pool_,
        BlacklistToken token_,
        address[] memory actors_
    ) {
        queue = queue_;
        pool = pool_;
        token = token_;
        actors = actors_;
    }

    function enqueue(uint256 actorSeed, uint96 rawAmount) external {
        if (queue.requestCount() >= 32) return;

        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);

        token.mint(actor, amount);

        vm.startPrank(actor);
        token.approve(address(pool), amount);
        uint256 credited = pool.deposit(address(token), amount);
        queue.request(address(token), actor, credited);
        vm.stopPrank();

        totalDeposited[actor] += credited;
        _observeCursor();
    }

    function setBlacklist(uint256 actorSeed, bool blocked) external {
        address actor = _actor(actorSeed);

        vm.prank(token.owner());
        token.setBlacklisted(actor, blocked);

        _observeCursor();
    }

    function processNext() external {
        uint256 requestId = queue.nextToProcess();
        if (requestId >= queue.requestCount()) return;

        (, , address recipient, uint256 amount) = queue.requests(requestId);
        (, bool success) = queue.processNext();

        if (success) {
            totalPaid[recipient] += amount;
        }

        _observeCursor();
    }

    function retryFailed(uint256 requestSeed) external {
        uint256 count = queue.requestCount();
        if (count == 0) return;

        uint256 requestId = requestSeed % count;
        if (queue.statusOf(requestId) != ForcedWithdrawalQueue.Status.Failed) return;

        (, , address recipient, uint256 amount) = queue.requests(requestId);
        bool success = queue.retryFailed(requestId);

        if (success) {
            totalPaid[recipient] += amount;
        }

        _observeCursor();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _observeCursor() internal {
        uint256 current = queue.nextToProcess();
        if (current < lastObservedCursor) {
            cursorDecreased = true;
        }
        lastObservedCursor = current;
    }
}
