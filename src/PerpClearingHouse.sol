// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";
import {PerpRisk} from "./lib/PerpRisk.sol";

/// @title PerpClearingHouse
/// @notice Isolated-margin liquidation settlement with explicit insurance and bad-debt accounting.
/// @dev Uses one ERC-20 settlement asset and one explicit counterparty/system recipient.
contract PerpClearingHouse {
    using SafeTransferLib for address;

    struct Position {
        int256 sizeUsd;
        uint256 entryPrice;
        uint256 collateral;
        bool open;
    }

    error ZeroAddress();
    error ZeroAmount();
    error InvalidConfiguration();
    error InvalidPosition();
    error PositionAlreadyOpen();
    error PositionNotOpen();
    error InitialMarginTooLow(uint256 required, uint256 provided);
    error NotLiquidatable(int256 equity, uint256 maintenanceMargin);
    error UnexpectedReceived(uint256 expected, uint256 actual);
    error ReentrantCall();

    event PositionOpened(
        address indexed account, int256 sizeUsd, uint256 entryPrice, uint256 collateral
    );
    event InsuranceFunded(address indexed funder, uint256 amount, uint256 newInsuranceBalance);
    event Liquidated(
        address indexed account,
        uint256 markPrice,
        int256 equity,
        uint256 realizedLoss,
        uint256 liquidationFee,
        uint256 traderResidual,
        uint256 insuranceCoverage,
        uint256 uncoveredBadDebt
    );

    uint256 internal constant BPS = 10_000;

    address public immutable settlementToken;
    address public immutable counterparty;
    uint256 public immutable initialMarginBps;
    uint256 public immutable maintenanceMarginBps;
    uint256 public immutable liquidationFeeBps;

    mapping(address account => Position position) public positions;

    uint256 public totalOpenCollateral;
    uint256 public insuranceBalance;
    uint256 public uncoveredBadDebt;

    bool private locked;

    modifier nonReentrant() {
        if (locked) revert ReentrantCall();
        locked = true;
        _;
        locked = false;
    }

    constructor(
        address settlementToken_,
        address counterparty_,
        uint256 initialMarginBps_,
        uint256 maintenanceMarginBps_,
        uint256 liquidationFeeBps_
    ) {
        if (settlementToken_ == address(0) || counterparty_ == address(0)) revert ZeroAddress();
        if (
            initialMarginBps_ == 0 || initialMarginBps_ > BPS || maintenanceMarginBps_ == 0
                || maintenanceMarginBps_ >= initialMarginBps_ || liquidationFeeBps_ > BPS
        ) revert InvalidConfiguration();

        settlementToken = settlementToken_;
        counterparty = counterparty_;
        initialMarginBps = initialMarginBps_;
        maintenanceMarginBps = maintenanceMarginBps_;
        liquidationFeeBps = liquidationFeeBps_;
    }

    function openPosition(int256 sizeUsd, uint256 entryPrice, uint256 collateral)
        external
        nonReentrant
    {
        if (positions[msg.sender].open) revert PositionAlreadyOpen();
        if (sizeUsd == 0 || entryPrice == 0 || collateral == 0) revert InvalidPosition();

        uint256 required = PerpRisk.marginRequirement(sizeUsd, initialMarginBps);
        if (collateral < required) revert InitialMarginTooLow(required, collateral);

        _pullExact(msg.sender, collateral);

        positions[msg.sender] = Position({
            sizeUsd: sizeUsd, entryPrice: entryPrice, collateral: collateral, open: true
        });
        totalOpenCollateral += collateral;

        emit PositionOpened(msg.sender, sizeUsd, entryPrice, collateral);
    }

    function fundInsurance(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _pullExact(msg.sender, amount);
        insuranceBalance += amount;

        emit InsuranceFunded(msg.sender, amount, insuranceBalance);
    }

    function isLiquidatable(address account, uint256 markPrice) public view returns (bool) {
        Position memory position = _openPosition(account);
        return PerpRisk.isLiquidatable(
            position.sizeUsd,
            position.collateral,
            position.entryPrice,
            markPrice,
            maintenanceMarginBps
        );
    }

    function liquidate(address account, uint256 markPrice) external nonReentrant {
        Position memory position = _openPosition(account);

        int256 pnl = PerpRisk.unrealizedPnl(position.sizeUsd, position.entryPrice, markPrice);
        int256 accountEquity = PerpRisk.equity(position.collateral, pnl);
        uint256 maintenance = PerpRisk.marginRequirement(position.sizeUsd, maintenanceMarginBps);

        if (accountEquity > int256(maintenance)) {
            revert NotLiquidatable(accountEquity, maintenance);
        }

        delete positions[account];
        totalOpenCollateral -= position.collateral;

        uint256 realizedLoss = pnl < 0 ? uint256(-pnl) : 0;
        uint256 liquidationFee;
        uint256 traderResidual;
        uint256 insuranceCoverage;
        uint256 newBadDebt;

        if (accountEquity > 0) {
            uint256 positiveEquity = uint256(accountEquity);
            uint256 nominalFee = (PerpRisk.notional(position.sizeUsd) * liquidationFeeBps) / BPS;
            liquidationFee = nominalFee > positiveEquity ? positiveEquity : nominalFee;
            traderResidual = positiveEquity - liquidationFee;

            if (realizedLoss != 0) settlementToken.safeTransfer(counterparty, realizedLoss);
            if (traderResidual != 0) settlementToken.safeTransfer(account, traderResidual);

            insuranceBalance += liquidationFee;
        } else {
            newBadDebt = uint256(-accountEquity);
            insuranceCoverage = newBadDebt > insuranceBalance ? insuranceBalance : newBadDebt;
            insuranceBalance -= insuranceCoverage;

            uint256 counterpartyPayout = position.collateral + insuranceCoverage;
            if (counterpartyPayout != 0) {
                settlementToken.safeTransfer(counterparty, counterpartyPayout);
            }

            uint256 uncovered = newBadDebt - insuranceCoverage;
            uncoveredBadDebt += uncovered;
        }

        emit Liquidated(
            account,
            markPrice,
            accountEquity,
            realizedLoss,
            liquidationFee,
            traderResidual,
            insuranceCoverage,
            newBadDebt - insuranceCoverage
        );
    }

    function accountedAssets() external view returns (uint256) {
        return totalOpenCollateral + insuranceBalance;
    }

    function _pullExact(address from, uint256 amount) internal {
        uint256 beforeAssets = IERC20Minimal(settlementToken).balanceOf(address(this));
        settlementToken.safeTransferFrom(from, address(this), amount);
        uint256 received = IERC20Minimal(settlementToken).balanceOf(address(this)) - beforeAssets;

        if (received != amount) revert UnexpectedReceived(amount, received);
    }

    function _openPosition(address account) internal view returns (Position memory position) {
        position = positions[account];
        if (!position.open) revert PositionNotOpen();
    }
}
