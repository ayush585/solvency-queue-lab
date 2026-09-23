// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OracleGuard} from "./OracleGuard.sol";
import {PerpRisk} from "./lib/PerpRisk.sol";

/// @title OracleMarginBook
/// @notice Isolated-margin risk engine whose entry and liquidation prices must pass OracleGuard.
contract OracleMarginBook {
    struct Position {
        int256 sizeUsd;
        uint256 entryPrice;
        uint256 collateralUsd;
        bool open;
    }

    error ZeroAddress();
    error InvalidMarginConfiguration();
    error InvalidPosition();
    error PositionAlreadyOpen();
    error PositionNotOpen();
    error InitialMarginTooLow(uint256 required, uint256 provided);
    error NotLiquidatable(int256 equity, uint256 maintenanceMargin);

    OracleGuard public immutable oracle;
    uint256 public immutable initialMarginBps;
    uint256 public immutable maintenanceMarginBps;

    mapping(address account => Position position) public positions;

    constructor(OracleGuard oracle_, uint256 initialMarginBps_, uint256 maintenanceMarginBps_) {
        if (address(oracle_) == address(0)) revert ZeroAddress();
        if (
            initialMarginBps_ == 0 || initialMarginBps_ > 10_000 || maintenanceMarginBps_ == 0
                || maintenanceMarginBps_ >= initialMarginBps_
        ) revert InvalidMarginConfiguration();

        oracle = oracle_;
        initialMarginBps = initialMarginBps_;
        maintenanceMarginBps = maintenanceMarginBps_;
    }

    function openPosition(int256 sizeUsd, uint256 collateralUsd) external {
        if (positions[msg.sender].open) revert PositionAlreadyOpen();
        if (sizeUsd == 0 || collateralUsd == 0) revert InvalidPosition();

        uint256 entryPrice = oracle.validatedPrice();
        uint256 required = PerpRisk.marginRequirement(sizeUsd, initialMarginBps);
        if (collateralUsd < required) revert InitialMarginTooLow(required, collateralUsd);

        positions[msg.sender] = Position({
            sizeUsd: sizeUsd, entryPrice: entryPrice, collateralUsd: collateralUsd, open: true
        });
    }

    function equity(address account) public view returns (int256) {
        Position memory position = _openPosition(account);
        uint256 markPrice = oracle.validatedPrice();

        return PerpRisk.equity(
            position.collateralUsd,
            PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice)
        );
    }

    function isLiquidatable(address account) public view returns (bool) {
        Position memory position = _openPosition(account);
        uint256 markPrice = oracle.validatedPrice();

        return PerpRisk.isLiquidatable(
            position.sizeUsd,
            position.collateralUsd,
            position.entryPrice,
            markPrice,
            maintenanceMarginBps
        );
    }

    function liquidate(address account)
        external
        returns (int256 accountEquity, uint256 maintenanceMargin)
    {
        Position storage position = positions[account];
        if (!position.open) revert PositionNotOpen();

        uint256 markPrice = oracle.validatedPrice();
        accountEquity = PerpRisk.equity(
            position.collateralUsd,
            PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice)
        );
        maintenanceMargin = PerpRisk.marginRequirement(position.sizeUsd, maintenanceMarginBps);

        if (accountEquity > int256(maintenanceMargin)) {
            revert NotLiquidatable(accountEquity, maintenanceMargin);
        }

        position.open = false;
    }

    function _openPosition(address account) internal view returns (Position memory position) {
        position = positions[account];
        if (!position.open) revert PositionNotOpen();
    }
}
