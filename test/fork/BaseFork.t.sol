// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/Pool.sol";

interface IBaseUSDC {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title BaseForkTest
/// @notice Integration tests against canonical native USDC on a live Base Mainnet fork.
contract BaseForkTest is Test {
    address internal constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 internal constant BASE_CHAIN_ID = 8453;

    Pool internal pool;
    address internal alice = makeAddr("alice");

    function setUp() public {
        string memory rpcUrl =
            vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));

        vm.createSelectFork(rpcUrl);
        pool = new Pool();
    }

    function test_forkIsBaseMainnetAndCanonicalUSDCIsLive() public view {
        assertEq(block.chainid, BASE_CHAIN_ID);
        assertGt(BASE_USDC.code.length, 0, "canonical Base USDC has no deployed code");
        assertEq(IBaseUSDC(BASE_USDC).symbol(), "USDC");
        assertEq(IBaseUSDC(BASE_USDC).decimals(), 6);
    }

    function test_realBaseUSDCDepositAndWithdrawalConserveAssets() public {
        uint256 startingBalance = 1_000e6;
        uint256 depositAmount = 250e6;
        uint256 withdrawalAmount = 75e6;

        // Mutate only fork-local state while exercising the real deployed USDC implementation.
        deal(BASE_USDC, alice, startingBalance, true);

        vm.startPrank(alice);
        IBaseUSDC(BASE_USDC).approve(address(pool), type(uint256).max);

        uint256 credited = pool.deposit(BASE_USDC, depositAmount);

        assertEq(credited, depositAmount);
        assertEq(pool.balanceOf(BASE_USDC, alice), depositAmount);
        assertEq(pool.totalLiabilities(BASE_USDC), depositAmount);
        assertEq(IBaseUSDC(BASE_USDC).balanceOf(address(pool)), depositAmount);

        pool.withdraw(BASE_USDC, withdrawalAmount);
        vm.stopPrank();

        uint256 remainingClaim = depositAmount - withdrawalAmount;

        assertEq(pool.balanceOf(BASE_USDC, alice), remainingClaim);
        assertEq(pool.totalLiabilities(BASE_USDC), remainingClaim);
        assertEq(IBaseUSDC(BASE_USDC).balanceOf(address(pool)), remainingClaim);
        assertEq(
            IBaseUSDC(BASE_USDC).balanceOf(alice),
            startingBalance - depositAmount + withdrawalAmount
        );
    }

    function test_realBaseUSDCRequestedDepositEqualsObservedBalanceDelta() public {
        uint256 amount = 123_456_789;

        deal(BASE_USDC, alice, amount, true);

        vm.startPrank(alice);
        IBaseUSDC(BASE_USDC).approve(address(pool), amount);
        uint256 credited = pool.deposit(BASE_USDC, amount);
        vm.stopPrank();

        assertEq(credited, amount);
        assertEq(IBaseUSDC(BASE_USDC).balanceOf(address(pool)), amount);
        assertEq(pool.totalLiabilities(BASE_USDC), amount);
    }
}
