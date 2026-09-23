// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DepositInbox} from "../../src/DepositInbox.sol";
import {Pool} from "../../src/Pool.sol";
import {SettlementVerifier} from "../../src/SettlementVerifier.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {SettlementHandler} from "./SettlementHandler.sol";

contract SettlementInvariantTest is StdInvariant, Test {
    Pool internal pool;
    MockERC20 internal token;
    DepositInbox internal inbox;
    SettlementVerifier internal verifier;
    SettlementHandler internal handler;

    address internal sequencer = makeAddr("sequencer");
    address[] internal actors;

    function setUp() public {
        pool = new Pool();
        token = new MockERC20("Settlement Token", "SET");
        inbox = new DepositInbox(pool, address(token));
        verifier = new SettlementVerifier(pool, address(token), sequencer, inbox);

        inbox.setConsumer(address(verifier));
        pool.setSettlementOperator(address(verifier), true);

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        address[] memory handlerActors = new address[](actors.length);
        for (uint256 i; i < actors.length; ++i) {
            handlerActors[i] = actors[i];
        }

        handler = new SettlementHandler(pool, token, inbox, verifier, sequencer, handlerActors);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SettlementHandler.lockAndCredit.selector;
        selectors[1] = SettlementHandler.applyZeroSumPnL.selector;
        selectors[2] = SettlementHandler.withdraw.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_poolLiabilitiesEqualBackingAssets() public view {
        assertEq(
            pool.totalLiabilities(address(token)),
            token.balanceOf(address(pool)),
            "settlement created unbacked liabilities"
        );
    }

    function invariant_knownUserClaimsEqualTotalLiabilities() public view {
        uint256 claims;
        for (uint256 i; i < actors.length; ++i) {
            claims += pool.balanceOf(address(token), actors[i]);
        }

        assertEq(
            claims,
            pool.totalLiabilities(address(token)),
            "ledger liabilities escaped known settlement users"
        );
    }

    function invariant_batchNonceEqualsSuccessfulBatchCount() public view {
        assertEq(
            verifier.nextBatchNonce(),
            handler.successfulBatches(),
            "batch nonce diverged from successful settlement history"
        );
    }
}
