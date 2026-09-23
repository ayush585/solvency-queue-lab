// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VulnerablePool} from "../src/VulnerablePool.sol";
import {FeeOnTransferToken} from "../src/mocks/FeeOnTransferToken.sol";

contract VulnerablePoolTest is Test {
    VulnerablePool internal pool;
    FeeOnTransferToken internal token;
    address internal alice = makeAddr("alice");

    function setUp() public {
        pool = new VulnerablePool();
        token = new FeeOnTransferToken(1_000); // 10%
        token.mint(alice, 1_000 ether);

        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);
    }

    function test_feeOnTransferDepositCreatesInsolvency() public {
        vm.prank(alice);
        pool.deposit(address(token), 1_000 ether);

        uint256 assets = token.balanceOf(address(pool));
        uint256 liabilities = pool.totalLiabilities(address(token));

        assertEq(assets, 900 ether);
        assertEq(liabilities, 1_000 ether);
        assertGt(liabilities, assets, "vulnerable accounting should become insolvent");
    }

    function testFuzz_feeTokenBreaksSolvency(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 10_000, 1_000_000 ether);
        token.mint(alice, amount);

        vm.prank(alice);
        pool.deposit(address(token), amount);

        assertGt(pool.totalLiabilities(address(token)), token.balanceOf(address(pool)));
    }
}
