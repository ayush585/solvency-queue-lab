// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";

contract VulnerableSettlementVerifier {
    struct PnLUpdate {
        address user;
        int256 delta;
    }

    struct CrossChainCredit {
        address user;
        uint256 amount;
    }

    error UnauthorizedSequencer();
    error ZeroAddress();
    error InvalidBatchNonce(uint256 expected, uint256 actual);

    Pool public immutable pool;
    address public immutable token;
    address public immutable sequencer;
    uint256 public nextBatchNonce;

    constructor(Pool pool_, address token_, address sequencer_) {
        if (address(pool_) == address(0) || token_ == address(0) || sequencer_ == address(0)) {
            revert ZeroAddress();
        }

        pool = pool_;
        token = token_;
        sequencer = sequencer_;
    }

    function submitBatch(
        uint256 batchNonce,
        PnLUpdate[] calldata pnlUpdates,
        CrossChainCredit[] calldata credits
    ) external {
        if (msg.sender != sequencer) {
            revert UnauthorizedSequencer();
        }

        uint256 expected = nextBatchNonce;
        if (batchNonce != expected) revert InvalidBatchNonce(expected, batchNonce);
        nextBatchNonce = expected + 1;

        for (uint256 i; i < pnlUpdates.length; ++i) {
            pool.applyStateChange(pnlUpdates[i].user, token, pnlUpdates[i].delta);
        }

        for (uint256 i; i < credits.length; ++i) {
            pool.creditCrossChainDeposit(credits[i].user, token, credits[i].amount);
        }
    }
}
