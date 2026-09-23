// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PerpClearingHouse} from "../../src/PerpClearingHouse.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {ClearingHouseHandler} from "./ClearingHouseHandler.sol";

contract ClearingHouseInvariantTest is StdInvariant, Test {
    MockERC20 internal token;
    PerpClearingHouse internal engine;
    ClearingHouseHandler internal handler;

    address internal counterparty = makeAddr("counterparty");
    address[] internal actors;

    function setUp() public {
        token = new MockERC20("Settlement Token", "SET");
        engine = new PerpClearingHouse(
            address(token),
            counterparty,
            1_000,
            500,
            100
        );

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        address[] memory handlerActors = new address[](actors.length);
        for (uint256 i; i < actors.length; ++i) {
            handlerActors[i] = actors[i];
        }

        handler = new ClearingHouseHandler(token, engine, counterparty, handlerActors);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ClearingHouseHandler.fundInsurance.selector;
        selectors[1] = ClearingHouseHandler.openPosition.selector;
        selectors[2] = ClearingHouseHandler.liquidate.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_engineAssetsMatchOpenCollateralPlusInsurance() public view {
        assertEq(
            token.balanceOf(address(engine)),
            engine.totalOpenCollateral() + engine.insuranceBalance(),
            "engine token balance escaped accounted asset buckets"
        );
    }

    function invariant_allMintedTokensRemainAccountedFor() public view {
        uint256 accounted =
            token.balanceOf(address(engine)) + token.balanceOf(counterparty)
                + token.balanceOf(address(handler));

        for (uint256 i; i < actors.length; ++i) {
            accounted += token.balanceOf(actors[i]);
        }

        assertEq(accounted, handler.totalMinted(), "minted settlement assets disappeared");
        assertEq(token.totalSupply(), handler.totalMinted(), "unexpected token mint/burn occurred");
    }

    function invariant_uncoveredBadDebtNeverDecreases() public view {
        assertFalse(handler.badDebtDecreased(), "uncovered bad debt decreased without resolution");
    }

    function invariant_openCollateralEqualsSumOfOpenPositions() public view {
        uint256 collateral;
        for (uint256 i; i < actors.length; ++i) {
            (,, uint256 positionCollateral, bool open) = engine.positions(actors[i]);
            if (open) collateral += positionCollateral;
        }

        assertEq(
            collateral,
            engine.totalOpenCollateral(),
            "aggregate open collateral diverged from position state"
        );
    }
}
