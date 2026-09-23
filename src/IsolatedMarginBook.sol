// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PerpRisk} from "./lib/PerpRisk.sol";

/// @title IsolatedMarginBook
/// @notice Risk-state machine for one isolated linear-perpetual position per account.
/// @dev This milestone intentionally models risk eligibility, not token settlement.
contract IsolatedMarginBook {
    using PerpRisk for int256;

    struct Position {
        int256 sizeUsd;
        uint256 entryPrice;
        uint256 collateralUsd;
        bool open;
    }

    uint256 public constant MAX_NOTIONAL_USD = 1e36;
    uint256 public constant MAX_PRICE = 1e30;

    error InvalidMarginConfiguration();
    error InvalidPosition();
    error RiskInputTooLarge();
    error PositionAlreadyOpen();
    error PositionNotOpen();
    error InitialMarginTooLow(uint256 required, uint256 provided);
    error CollateralRemovalUnsafe(int256 resultingEquity, uint256 requiredInitialMargin);
    error NotLiquidatable(int256 equity, uint256 maintenanceMargin);

    event PositionOpened(
        address indexed account, int256 sizeUsd, uint256 entryPrice, uint256 collateralUsd
    );
    event CollateralAdded(address indexed account, uint256 amount, uint256 newCollateral);
    event CollateralRemoved(address indexed account, uint256 amount, uint256 newCollateral);
    event Liquidated(
        address indexed account, uint256 markPrice, int256 equity, uint256 maintenanceMargin
    );

    uint256 public immutable initialMarginBps;
    uint256 public immutable maintenanceMarginBps;

    mapping(address account => Position position) public positions;

    constructor(uint256 initialMarginBps_, uint256 maintenanceMarginBps_) {
        if (
            initialMarginBps_ == 0 || initialMarginBps_ > 10_000 || maintenanceMarginBps_ == 0
                || maintenanceMarginBps_ >= initialMarginBps_
        ) revert InvalidMarginConfiguration();

        initialMarginBps = initialMarginBps_;
        maintenanceMarginBps = maintenanceMarginBps_;
    }

    function openPosition(int256 sizeUsd, uint256 entryPrice, uint256 collateralUsd) external {
        if (positions[msg.sender].open) revert PositionAlreadyOpen();
        if (sizeUsd == 0 || entryPrice == 0 || collateralUsd == 0) revert InvalidPosition();
        if (PerpRisk.notional(sizeUsd) > MAX_NOTIONAL_USD || entryPrice > MAX_PRICE) {
            revert RiskInputTooLarge();
        }

        uint256 required = PerpRisk.marginRequirement(sizeUsd, initialMarginBps);
        if (collateralUsd < required) revert InitialMarginTooLow(required, collateralUsd);

        positions[msg.sender] = Position({
            sizeUsd: sizeUsd, entryPrice: entryPrice, collateralUsd: collateralUsd, open: true
        });

        emit PositionOpened(msg.sender, sizeUsd, entryPrice, collateralUsd);
    }

    function addCollateral(uint256 amount) external {
        Position storage position = positions[msg.sender];
        if (!position.open) revert PositionNotOpen();
        if (amount == 0) revert InvalidPosition();

        position.collateralUsd += amount;
        emit CollateralAdded(msg.sender, amount, position.collateralUsd);
    }

    /// @notice Removes isolated margin only if resulting equity still meets initial margin.
    function removeCollateral(uint256 amount, uint256 markPrice) external {
        Position storage position = positions[msg.sender];
        if (!position.open) revert PositionNotOpen();
        if (amount == 0 || amount > position.collateralUsd) revert InvalidPosition();

        uint256 newCollateral = position.collateralUsd - amount;
        int256 pnl = PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice);
        int256 resultingEquity = PerpRisk.equity(newCollateral, pnl);
        uint256 required = PerpRisk.marginRequirement(position.sizeUsd, initialMarginBps);

        if (resultingEquity < int256(required)) {
            revert CollateralRemovalUnsafe(resultingEquity, required);
        }

        position.collateralUsd = newCollateral;
        emit CollateralRemoved(msg.sender, amount, newCollateral);
    }

    function unrealizedPnl(address account, uint256 markPrice) public view returns (int256) {
        Position memory position = _openPosition(account);
        return PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice);
    }

    function equity(address account, uint256 markPrice) public view returns (int256) {
        Position memory position = _openPosition(account);
        return PerpRisk.equity(
            position.collateralUsd,
            PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice)
        );
    }

    function initialMarginRequirement(address account) external view returns (uint256) {
        Position memory position = _openPosition(account);
        return PerpRisk.marginRequirement(position.sizeUsd, initialMarginBps);
    }

    function maintenanceMarginRequirement(address account) public view returns (uint256) {
        Position memory position = _openPosition(account);
        return PerpRisk.marginRequirement(position.sizeUsd, maintenanceMarginBps);
    }

    function isLiquidatable(address account, uint256 markPrice) public view returns (bool) {
        Position memory position = _openPosition(account);
        return PerpRisk.isLiquidatable(
            position.sizeUsd,
            position.collateralUsd,
            position.entryPrice,
            markPrice,
            maintenanceMarginBps
        );
    }

    /// @notice Marks a position closed once its equity reaches the maintenance threshold.
    /// @dev Asset transfers, liquidation fees, insurance, and bad debt are intentionally deferred.
    function liquidate(address account, uint256 markPrice)
        external
        returns (int256 accountEquity, uint256 maintenance)
    {
        Position storage position = positions[account];
        if (!position.open) revert PositionNotOpen();

        accountEquity = PerpRisk.equity(
            position.collateralUsd,
            PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice)
        );
        maintenance = PerpRisk.marginRequirement(position.sizeUsd, maintenanceMarginBps);

        if (accountEquity > int256(maintenance)) {
            revert NotLiquidatable(accountEquity, maintenance);
        }

        position.open = false;
        emit Liquidated(account, markPrice, accountEquity, maintenance);
    }

    function _openPosition(address account) internal view returns (Position memory position) {
        position = positions[account];
        if (!position.open) revert PositionNotOpen();
    }
}
