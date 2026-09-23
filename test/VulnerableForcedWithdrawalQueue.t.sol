// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {BlacklistToken} from "../src/mocks/BlacklistToken.sol";
import {VulnerableForcedWithdrawalQueue} from "../src/VulnerableForcedWithdrawalQueue.sol";

contract VulnerableForcedWithdrawalQueueTest is Test {
    Pool internal pool;
    BlacklistToken internal token;
    VulnerableForcedWithdrawalQueue internal queue;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        pool = new Pool();
        token = new BlacklistToken();
        queue = new VulnerableForcedWithdrawalQueue(pool);

        pool.setWithdrawalOperator(address(queue), true);

        _deposit(alice, 100 ether);
        _deposit(bob, 100 ether);

        vm.prank(alice);
        queue.request(address(token), alice, 100 ether);

        vm.prank(bob);
        queue.request(address(token), bob, 100 ether);
    }

    function test_blacklistedHeadPermanentlyBlocksLaterValidWithdrawal() public {
        token.setBlacklisted(alice, true);

        vm.expectRevert();
        queue.processNext();

        assertEq(queue.nextToProcess(), 0);
        assertEq(pool.balanceOf(address(token), alice), 100 ether);
        assertEq(pool.balanceOf(address(token), bob), 100 ether);

        // Bob is valid, but strict FIFO exposes no way to skip request 0.
        vm.expectRevert();
        queue.processNext();

        assertEq(queue.nextToProcess(), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(pool.balanceOf(address(token), bob), 100 ether);
    }

    function _deposit(address user, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(pool), amount);
        pool.deposit(address(token), amount);
        vm.stopPrank();
    }
}
