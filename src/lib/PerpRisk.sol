// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PerpRisk
/// @notice Linear-perpetual risk math using 18-decimal USD units.
library PerpRisk {
    uint256 internal constant BPS = 10_000;

    error ZeroEntryPrice();
    error ValueTooLarge();

    function notional(int256 sizeUsd) internal pure returns (uint256) {
        if (sizeUsd == type(int256).min) revert ValueTooLarge();
        return uint256(sizeUsd < 0 ? -sizeUsd : sizeUsd);
    }

    /// @notice Price-move PnL for a linear perpetual.
    /// @dev Positive size is long; negative size is short.
    function unrealizedPnl(int256 sizeUsd, uint256 entryPrice, uint256 markPrice)
        internal
        pure
        returns (int256)
    {
        if (entryPrice == 0) revert ZeroEntryPrice();
        if (entryPrice > uint256(type(int256).max) || markPrice > uint256(type(int256).max)) {
            revert ValueTooLarge();
        }

        int256 priceDelta = int256(markPrice) - int256(entryPrice);
        return (sizeUsd * priceDelta) / int256(entryPrice);
    }

    function equity(uint256 collateralUsd, int256 pnl) internal pure returns (int256) {
        if (collateralUsd > uint256(type(int256).max)) revert ValueTooLarge();
        return int256(collateralUsd) + pnl;
    }

    function marginRequirement(int256 sizeUsd, uint256 marginBps)
        internal
        pure
        returns (uint256)
    {
        return (notional(sizeUsd) * marginBps) / BPS;
    }

    function isLiquidatable(
        int256 sizeUsd,
        uint256 collateralUsd,
        uint256 entryPrice,
        uint256 markPrice,
        uint256 maintenanceMarginBps
    ) internal pure returns (bool) {
        int256 accountEquity = equity(collateralUsd, unrealizedPnl(sizeUsd, entryPrice, markPrice));
        uint256 maintenance = marginRequirement(sizeUsd, maintenanceMarginBps);

        return accountEquity <= int256(maintenance);
    }
}
