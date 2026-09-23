// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeOnTransferToken} from "../src/mocks/FeeOnTransferToken.sol";

contract PoolTest is Test {
    Pool internal pool;
    MockERC20 internal standard;
    FeeOnTransferToken internal feeToken;
    address internal alice = makeAddr("alice");

    function setUp() public {
        pool = new Pool();
        standard = new MockERC20("Standard", "STD");
        feeToken = new FeeOnTransferToken(1_000); // 10%

        standard.mint(alice, 2_000 ether);
        feeToken.mint(alice, 2_000 ether);

        vm.startPrank(alice);
        standard.approve(address(pool), type(uint256).max);
        feeToken.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_standardDepositCreditsExactAmount() public {
        vm.prank(alice);
        uint256 credited = pool.deposit(address(standard), 1_000 ether);

        assertEq(credited, 1_000 ether);
        assertEq(pool.balanceOf(address(standard), alice), 1_000 ether);
        assertEq(pool.totalLiabilities(address(standard)), 1_000 ether);
        assertEq(standard.balanceOf(address(pool)), 1_000 ether);
    }

    function test_feeOnTransferDepositCreditsOnlyAssetsReceived() public {
        vm.prank(alice);
        uint256 credited = pool.deposit(address(feeToken), 1_000 ether);

        assertEq(credited, 900 ether);
        assertEq(pool.balanceOf(address(feeToken), alice), 900 ether);
        assertEq(pool.totalLiabilities(address(feeToken)), 900 ether);
        assertEq(feeToken.balanceOf(address(pool)), 900 ether);
    }

    function test_standardWithdrawalPreservesSolvency() public {
        vm.startPrank(alice);
        pool.deposit(address(standard), 1_000 ether);
        pool.withdraw(address(standard), 400 ether);
        vm.stopPrank();

        assertEq(pool.balanceOf(address(standard), alice), 600 ether);
        assertEq(pool.totalLiabilities(address(standard)), 600 ether);
        assertEq(standard.balanceOf(address(pool)), 600 ether);
    }

    function test_feeOnTransferWithdrawalRevertsWithoutDestroyingClaim() public {
        vm.prank(alice);
        pool.deposit(address(feeToken), 1_000 ether);

        uint256 claimBefore = pool.balanceOf(address(feeToken), alice);
        uint256 poolAssetsBefore = feeToken.balanceOf(address(pool));
        uint256 aliceAssetsBefore = feeToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(Pool.UnexpectedTransferBehavior.selector);
        pool.withdraw(address(feeToken), claimBefore);

        assertEq(pool.balanceOf(address(feeToken), alice), claimBefore);
        assertEq(pool.totalLiabilities(address(feeToken)), claimBefore);
        assertEq(feeToken.balanceOf(address(pool)), poolAssetsBefore);
        assertEq(feeToken.balanceOf(alice), aliceAssetsBefore);
    }

    function testFuzz_standardDepositWithdrawalConservesClaims(
        uint96 rawDeposit,
        uint96 rawWithdraw
    ) public {
        uint256 amount = bound(uint256(rawDeposit), 1, 1_000 ether);
        uint256 withdrawal = bound(uint256(rawWithdraw), 1, amount);

        vm.startPrank(alice);
        pool.deposit(address(standard), amount);
        pool.withdraw(address(standard), withdrawal);
        vm.stopPrank();

        assertEq(pool.balanceOf(address(standard), alice), amount - withdrawal);
        assertEq(pool.totalLiabilities(address(standard)), standard.balanceOf(address(pool)));
    }
}
