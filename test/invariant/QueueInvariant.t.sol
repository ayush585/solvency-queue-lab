// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ForcedWithdrawalQueue} from "../../src/ForcedWithdrawalQueue.sol";
import {Pool} from "../../src/Pool.sol";
import {BlacklistToken} from "../../src/mocks/BlacklistToken.sol";
import {QueueHandler} from "./QueueHandler.sol";

contract QueueInvariantTest is StdInvariant, Test {
    ForcedWithdrawalQueue internal queue;
    Pool internal pool;
    BlacklistToken internal token;
    QueueHandler internal handler;

    address[] internal actors;

    function setUp() public {
        pool = new Pool();
        token = new BlacklistToken();
        queue = new ForcedWithdrawalQueue(pool);

        pool.setWithdrawalOperator(address(queue), true);

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        address[] memory handlerActors = new address[](actors.length);
        for (uint256 i; i < actors.length; ++i) {
            handlerActors[i] = actors[i];
        }

        handler = new QueueHandler(queue, pool, token, handlerActors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = QueueHandler.enqueue.selector;
        selectors[1] = QueueHandler.setBlacklist.selector;
        selectors[2] = QueueHandler.processNext.selector;
        selectors[3] = QueueHandler.retryFailed.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_cursorNeverDecreasesAndNeverExceedsRequestCount() public view {
        assertFalse(handler.cursorDecreased(), "queue cursor decreased");
        assertLe(queue.nextToProcess(), queue.requestCount(), "cursor exceeded request count");
    }

    function invariant_everyAttemptedEntryHasTerminalStatus() public view {
        uint256 cursor = queue.nextToProcess();

        for (uint256 i; i < cursor; ++i) {
            ForcedWithdrawalQueue.Status status = queue.statusOf(i);
            assertTrue(
                status == ForcedWithdrawalQueue.Status.Processed
                    || status == ForcedWithdrawalQueue.Status.Failed,
                "attempted entry is not terminal"
            );
        }
    }

    function invariant_unattemptedEntriesRemainPending() public view {
        uint256 cursor = queue.nextToProcess();
        uint256 count = queue.requestCount();

        for (uint256 i = cursor; i < count; ++i) {
            assertEq(
                uint256(queue.statusOf(i)),
                uint256(ForcedWithdrawalQueue.Status.Pending),
                "future queue entry mutated early"
            );
        }
    }

    function invariant_claimsAndPayoutsConserveDeposits() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 deposited = handler.totalDeposited(actor);
            uint256 paid = handler.totalPaid(actor);

            assertLe(paid, deposited, "paid more than deposited");
            assertEq(
                pool.balanceOf(address(token), actor),
                deposited - paid,
                "internal claim drifted from successful payout history"
            );
            assertEq(
                token.balanceOf(actor),
                paid,
                "external payout balance drifted from successful payout history"
            );
        }
    }

    function invariant_poolBackingMatchesOutstandingClaims() public view {
        assertEq(
            pool.totalLiabilities(address(token)),
            token.balanceOf(address(pool)),
            "pool liabilities/backing diverged"
        );
    }
}
