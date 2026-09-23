// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PerpClearingHouse} from "../../src/PerpClearingHouse.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract ClearingHouseHandler is Test {
    MockERC20 public immutable token;
    PerpClearingHouse public immutable engine;
    address public immutable counterparty;

    address[] public actors;

    uint256 public totalMinted;
    bool public badDebtDecreased;
    uint256 public lastBadDebt;

    constructor(
        MockERC20 token_,
        PerpClearingHouse engine_,
        address counterparty_,
        address[] memory actors_
    ) {
        token = token_;
        engine = engine_;
        counterparty = counterparty_;
        actors = actors_;
    }

    function fundInsurance(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 500 ether);

        token.mint(address(this), amount);
        token.approve(address(engine), amount);
        engine.fundInsurance(amount);

        totalMinted += amount;
        _observeBadDebt();
    }

    function openPosition(
        uint256 actorSeed,
        bool shortSide,
        uint96 rawNotional,
        uint16 rawExtraMarginBps
    ) external {
        address actor = _actor(actorSeed);
        (,,, bool open) = engine.positions(actor);
        if (open) return;

        uint256 notional = bound(uint256(rawNotional), 1_000 ether, 20_000 ether);
        uint256 initialMargin = (notional * engine.initialMarginBps()) / 10_000;
        uint256 extraBps = bound(uint256(rawExtraMarginBps), 0, 500);
        uint256 collateral = initialMargin + ((notional * extraBps) / 10_000);

        token.mint(actor, collateral);

        vm.startPrank(actor);
        token.approve(address(engine), collateral);
        engine.openPosition(
            shortSide ? -int256(notional) : int256(notional), 1_000 ether, collateral
        );
        vm.stopPrank();

        totalMinted += collateral;
        _observeBadDebt();
    }

    function liquidate(uint256 actorSeed, uint16 rawMoveBps) external {
        address actor = _actor(actorSeed);
        (int256 sizeUsd,,, bool open) = engine.positions(actor);
        if (!open) return;

        uint256 moveBps = bound(uint256(rawMoveBps), 500, 5_000);
        uint256 markPrice;

        if (sizeUsd > 0) {
            markPrice = (1_000 ether * (10_000 - moveBps)) / 10_000;
        } else {
            markPrice = (1_000 ether * (10_000 + moveBps)) / 10_000;
        }

        if (!engine.isLiquidatable(actor, markPrice)) return;

        engine.liquidate(actor, markPrice);
        _observeBadDebt();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _observeBadDebt() internal {
        uint256 current = engine.uncoveredBadDebt();
        if (current < lastBadDebt) badDebtDecreased = true;
        lastBadDebt = current;
    }
}
