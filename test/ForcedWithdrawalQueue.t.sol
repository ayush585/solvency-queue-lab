// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ForcedWithdrawalQueue} from "../src/ForcedWithdrawalQueue.sol";
import {Pool} from "../src/Pool.sol";
import {BlacklistToken} from "../src/mocks/BlacklistToken.sol";

contract ForcedWithdrawalQueueTest is Test {
    Pool internal pool;
    BlacklistToken internal token;
    ForcedWithdrawalQueue internal queue;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        pool = new Pool();
        token = new BlacklistToken();
        queue = new ForcedWithdrawalQueue(pool);

        pool.setWithdrawalOperator(address(queue), true);

        _deposit(alice, 100 ether);
        _deposit(bob, 100 ether);

        vm.prank(alice);
        queue.request(address(token), alice, 100 ether);

        vm.prank(bob);
        queue.request(address(token), bob, 100 ether);
    }

    function test_failedHeadIsIsolatedAndLaterRequestStillProcesses() public {
        token.setBlacklisted(alice, true);

        (uint256 aliceId, bool aliceSuccess) = queue.processNext();

        assertEq(aliceId, 0);
        assertFalse(aliceSuccess);
        assertEq(queue.nextToProcess(), 1);
        assertEq(
            uint256(queue.statusOf(0)),
            uint256(ForcedWithdrawalQueue.Status.Failed)
        );

        // The failed external Pool call reverted atomically, preserving Alice's claim.
        assertEq(pool.balanceOf(address(token), alice), 100 ether);
        assertEq(token.balanceOf(alice), 0);

        (uint256 bobId, bool bobSuccess) = queue.processNext();

        assertEq(bobId, 1);
        assertTrue(bobSuccess);
        assertEq(queue.nextToProcess(), 2);
        assertEq(
            uint256(queue.statusOf(1)),
            uint256(ForcedWithdrawalQueue.Status.Processed)
        );
        assertEq(pool.balanceOf(address(token), bob), 0);
        assertEq(token.balanceOf(bob), 100 ether);

        // Alice can recover later without rewinding or blocking the global queue.
        token.setBlacklisted(alice, false);
        bool retrySuccess = queue.retryFailed(0);

        assertTrue(retrySuccess);
        assertEq(
            uint256(queue.statusOf(0)),
            uint256(ForcedWithdrawalQueue.Status.Processed)
        );
        assertEq(pool.balanceOf(address(token), alice), 0);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_failedRetryStaysRetryableAndPreservesClaim() public {
        token.setBlacklisted(alice, true);

        (, bool firstSuccess) = queue.processNext();
        assertFalse(firstSuccess);

        bool retrySuccess = queue.retryFailed(0);
        assertFalse(retrySuccess);

        assertEq(
            uint256(queue.statusOf(0)),
            uint256(ForcedWithdrawalQueue.Status.Failed)
        );
        assertEq(pool.balanceOf(address(token), alice), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(queue.nextToProcess(), 1);
    }

    function test_processedRequestCannotBeRetried() public {
        queue.processNext();

        vm.expectRevert(
            abi.encodeWithSelector(
                ForcedWithdrawalQueue.NotFailed.selector,
                0,
                ForcedWithdrawalQueue.Status.Processed
            )
        );
        queue.retryFailed(0);
    }

    function test_emptyQueueHeadRevertsAfterAllEntriesAttempted() public {
        queue.processNext();
        queue.processNext();

        vm.expectRevert(ForcedWithdrawalQueue.EmptyQueue.selector);
        queue.processNext();
    }

    function _deposit(address user, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(pool), amount);
        pool.deposit(address(token), amount);
        vm.stopPrank();
    }
}
