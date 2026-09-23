// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DepositInbox} from "../src/DepositInbox.sol";
import {Pool} from "../src/Pool.sol";
import {SettlementVerifier} from "../src/SettlementVerifier.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SettlementVerifierTest is Test {
    Pool internal pool;
    MockERC20 internal token;
    DepositInbox internal inbox;
    SettlementVerifier internal verifier;

    address internal sequencer = makeAddr("sequencer");
    address internal bridge = makeAddr("bridge");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        pool = new Pool();
        token = new MockERC20("Settlement Token", "SET");
        inbox = new DepositInbox(pool, address(token));
        verifier = new SettlementVerifier(pool, address(token), sequencer, inbox);

        inbox.setConsumer(address(verifier));
        pool.setSettlementOperator(address(verifier), true);
    }

    function test_backedDepositCreditPreservesSolvency() public {
        bytes32 depositId = keccak256("deposit-1");
        _lockDeposit(depositId, alice, 250 ether);

        assertEq(token.balanceOf(address(pool)), 250 ether);
        assertEq(pool.totalLiabilities(address(token)), 0);

        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](0);
        bytes32[] memory deposits = new bytes32[](1);
        deposits[0] = depositId;

        vm.prank(sequencer);
        verifier.submitBatch(0, pnl, deposits);

        assertEq(verifier.nextBatchNonce(), 1);
        assertEq(pool.balanceOf(address(token), alice), 250 ether);
        assertEq(pool.totalLiabilities(address(token)), 250 ether);
        assertEq(token.balanceOf(address(pool)), 250 ether);
    }

    function test_nonZeroSumPnLIsRejectedWithoutConsumingNonce() public {
        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](1);
        pnl[0] = SettlementVerifier.PnLUpdate({user: alice, delta: 100 ether});

        bytes32[] memory deposits = new bytes32[](0);

        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(SettlementVerifier.NetPnLNotZero.selector, int256(100 ether))
        );
        verifier.submitBatch(0, pnl, deposits);

        assertEq(verifier.nextBatchNonce(), 0);
        assertEq(pool.totalLiabilities(address(token)), 0);
    }

    function test_zeroSumPnLRedistributesClaimsWithoutCreatingLiabilities() public {
        _directDeposit(alice, 100 ether);

        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](2);
        pnl[0] = SettlementVerifier.PnLUpdate({user: alice, delta: -40 ether});
        pnl[1] = SettlementVerifier.PnLUpdate({user: bob, delta: 40 ether});

        bytes32[] memory deposits = new bytes32[](0);

        vm.prank(sequencer);
        verifier.submitBatch(0, pnl, deposits);

        assertEq(pool.balanceOf(address(token), alice), 60 ether);
        assertEq(pool.balanceOf(address(token), bob), 40 ether);
        assertEq(pool.totalLiabilities(address(token)), 100 ether);
        assertEq(token.balanceOf(address(pool)), 100 ether);
    }

    function test_consumedDepositCannotBeCreditedTwiceAndNonceRollsBack() public {
        bytes32 depositId = keccak256("deposit-replay");
        _lockDeposit(depositId, alice, 100 ether);

        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](0);
        bytes32[] memory deposits = new bytes32[](1);
        deposits[0] = depositId;

        vm.prank(sequencer);
        verifier.submitBatch(0, pnl, deposits);

        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(DepositInbox.DepositAlreadyConsumed.selector, depositId)
        );
        verifier.submitBatch(1, pnl, deposits);

        assertEq(verifier.nextBatchNonce(), 1);
        assertEq(pool.balanceOf(address(token), alice), 100 ether);
        assertEq(token.balanceOf(address(pool)), 100 ether);
    }

    function test_outOfOrderBatchIsRejected() public {
        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](0);
        bytes32[] memory deposits = new bytes32[](0);

        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(SettlementVerifier.InvalidBatchNonce.selector, 0, 1)
        );
        verifier.submitBatch(1, pnl, deposits);

        assertEq(verifier.nextBatchNonce(), 0);
    }

    function test_onlySequencerCanSubmitBatch() public {
        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](0);
        bytes32[] memory deposits = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(SettlementVerifier.UnauthorizedSequencer.selector);
        verifier.submitBatch(0, pnl, deposits);
    }

    function test_failedPnLApplicationRollsBackDepositConsumptionAndNonce() public {
        bytes32 depositId = keccak256("atomic-batch");
        _lockDeposit(depositId, bob, 50 ether);

        SettlementVerifier.PnLUpdate[] memory pnl =
            new SettlementVerifier.PnLUpdate[](2);
        pnl[0] = SettlementVerifier.PnLUpdate({user: alice, delta: -100 ether});
        pnl[1] = SettlementVerifier.PnLUpdate({user: bob, delta: 100 ether});

        bytes32[] memory deposits = new bytes32[](1);
        deposits[0] = depositId;

        vm.prank(sequencer);
        vm.expectRevert(Pool.InsufficientBalance.selector);
        verifier.submitBatch(0, pnl, deposits);

        assertEq(verifier.nextBatchNonce(), 0);

        (address user, uint256 amount, bool consumed, bool exists) = inbox.receipts(depositId);
        assertEq(user, bob);
        assertEq(amount, 50 ether);
        assertFalse(consumed);
        assertTrue(exists);

        assertEq(pool.balanceOf(address(token), bob), 0);
        assertEq(pool.totalLiabilities(address(token)), 0);
        assertEq(token.balanceOf(address(pool)), 50 ether);
    }

    function _lockDeposit(bytes32 depositId, address user, uint256 amount) internal {
        token.mint(bridge, amount);

        vm.startPrank(bridge);
        token.approve(address(inbox), amount);
        inbox.lockDeposit(depositId, user, amount);
        vm.stopPrank();
    }

    function _directDeposit(address user, uint256 amount) internal {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(pool), amount);
        pool.deposit(address(token), amount);
        vm.stopPrank();
    }
}
