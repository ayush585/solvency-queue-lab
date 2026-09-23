// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DepositInbox} from "./DepositInbox.sol";
import {Pool} from "./Pool.sol";

contract SettlementVerifier {
    struct PnLUpdate {
        address user;
        int256 delta;
    }

    error UnauthorizedSequencer();
    error ZeroAddress();
    error InvalidBatchNonce(uint256 expected, uint256 actual);
    error NetPnLNotZero(int256 netDelta);

    Pool public immutable pool;
    address public immutable token;
    address public immutable sequencer;
    DepositInbox public immutable depositInbox;
    uint256 public nextBatchNonce;

    constructor(
        Pool pool_,
        address token_,
        address sequencer_,
        DepositInbox depositInbox_
    ) {
        if (
            address(pool_) == address(0) || token_ == address(0)
                || sequencer_ == address(0) || address(depositInbox_) == address(0)
        ) revert ZeroAddress();

        pool = pool_;
        token = token_;
        sequencer = sequencer_;
        depositInbox = depositInbox_;
    }

    function submitBatch(
        uint256 batchNonce,
        PnLUpdate[] calldata pnlUpdates,
        bytes32[] calldata depositIds
    ) external {
        if (msg.sender != sequencer) revert UnauthorizedSequencer();

        uint256 expected = nextBatchNonce;
        if (batchNonce != expected) revert InvalidBatchNonce(expected, batchNonce);

        int256 netDelta;
        for (uint256 i; i < pnlUpdates.length; ++i) {
            netDelta += pnlUpdates[i].delta;
        }
        if (netDelta != 0) revert NetPnLNotZero(netDelta);

        nextBatchNonce = expected + 1;

        for (uint256 i; i < depositIds.length; ++i) {
            (address user, uint256 amount) = depositInbox.consume(depositIds[i]);
            pool.creditCrossChainDeposit(user, token, amount);
        }

        for (uint256 i; i < pnlUpdates.length; ++i) {
            pool.applyStateChange(pnlUpdates[i].user, token, pnlUpdates[i].delta);
        }
    }
}
