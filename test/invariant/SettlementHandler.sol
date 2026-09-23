// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DepositInbox} from "../../src/DepositInbox.sol";
import {Pool} from "../../src/Pool.sol";
import {SettlementVerifier} from "../../src/SettlementVerifier.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract SettlementHandler is Test {
    Pool public immutable pool;
    MockERC20 public immutable token;
    DepositInbox public immutable inbox;
    SettlementVerifier public immutable verifier;
    address public immutable sequencer;

    address[] public actors;

    uint256 public successfulBatches;
    uint256 public depositCounter;

    constructor(
        Pool pool_,
        MockERC20 token_,
        DepositInbox inbox_,
        SettlementVerifier verifier_,
        address sequencer_,
        address[] memory actors_
    ) {
        pool = pool_;
        token = token_;
        inbox = inbox_;
        verifier = verifier_;
        sequencer = sequencer_;
        actors = actors_;
    }

    function lockAndCredit(uint256 actorSeed, uint96 rawAmount) external {
        if (depositCounter >= 64) return;

        address actor = _actor(actorSeed);
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);

        bytes32 depositId =
            keccak256(abi.encode("invariant-deposit", depositCounter++, actor, amount));

        token.mint(address(this), amount);
        token.approve(address(inbox), amount);
        inbox.lockDeposit(depositId, actor, amount);

        SettlementVerifier.PnLUpdate[] memory pnl = new SettlementVerifier.PnLUpdate[](0);
        bytes32[] memory deposits = new bytes32[](1);
        deposits[0] = depositId;

        uint256 nonce = verifier.nextBatchNonce();
        vm.prank(sequencer);
        verifier.submitBatch(nonce, pnl, deposits);
        ++successfulBatches;
    }

    function applyZeroSumPnL(uint256 fromSeed, uint256 toSeed, uint96 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == to) return;

        uint256 claim = pool.balanceOf(address(token), from);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);

        SettlementVerifier.PnLUpdate[] memory pnl = new SettlementVerifier.PnLUpdate[](2);
        pnl[0] = SettlementVerifier.PnLUpdate({user: from, delta: -int256(amount)});
        pnl[1] = SettlementVerifier.PnLUpdate({user: to, delta: int256(amount)});

        bytes32[] memory deposits = new bytes32[](0);

        uint256 nonce = verifier.nextBatchNonce();
        vm.prank(sequencer);
        verifier.submitBatch(nonce, pnl, deposits);
        ++successfulBatches;
    }

    function withdraw(uint256 actorSeed, uint96 rawAmount) external {
        address actor = _actor(actorSeed);
        uint256 claim = pool.balanceOf(address(token), actor);
        if (claim == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, claim);

        vm.prank(actor);
        pool.withdraw(address(token), amount);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
}
