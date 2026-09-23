// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title FundingMarket
/// @notice Cumulative per-size funding checkpoints for a single perpetual market.
/// @dev Positive fundingRatePerSecond means longs pay shorts; negative means shorts pay longs.
contract FundingMarket {
    struct Position {
        bool isLong;
        uint256 sizeUsd;
        int256 fundingCheckpoint;
        int256 settledFunding;
        bool open;
    }

    error Unauthorized();
    error InvalidPosition();
    error PositionAlreadyOpen();
    error PositionNotOpen();
    error RateTooLarge();

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_POSITION_SIZE = 1e30;
    int256 public constant MAX_ABS_RATE_PER_SECOND = 1e15;

    address public immutable owner;

    int256 public fundingRatePerSecond;
    int256 public cumulativeFundingPerSizeLong;
    int256 public cumulativeFundingPerSizeShort;
    uint256 public lastFundingTime;

    uint256 public totalLongOpenInterest;
    uint256 public totalShortOpenInterest;
    uint256 public totalAccruedFundingPaid;
    uint256 public totalAccruedFundingReceived;

    mapping(address account => Position position) public positions;

    constructor() {
        owner = msg.sender;
        lastFundingTime = block.timestamp;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setFundingRate(int256 newRatePerSecond) external onlyOwner {
        _accrue();

        if (
            newRatePerSecond > MAX_ABS_RATE_PER_SECOND
                || newRatePerSecond < -MAX_ABS_RATE_PER_SECOND
        ) revert RateTooLarge();

        fundingRatePerSecond = newRatePerSecond;
    }

    function openPosition(bool isLong, uint256 sizeUsd) external {
        if (positions[msg.sender].open) revert PositionAlreadyOpen();
        if (sizeUsd == 0 || sizeUsd > MAX_POSITION_SIZE) revert InvalidPosition();

        _accrue();

        int256 checkpoint = isLong ? cumulativeFundingPerSizeLong : cumulativeFundingPerSizeShort;

        positions[msg.sender] = Position({
            isLong: isLong,
            sizeUsd: sizeUsd,
            fundingCheckpoint: checkpoint,
            settledFunding: 0,
            open: true
        });

        if (isLong) {
            totalLongOpenInterest += sizeUsd;
        } else {
            totalShortOpenInterest += sizeUsd;
        }
    }

    function settleFunding(address account) external returns (int256 fundingDelta) {
        _accrue();

        Position storage position = positions[account];
        if (!position.open) revert PositionNotOpen();

        fundingDelta = _pendingFunding(position);
        position.settledFunding += fundingDelta;
        position.fundingCheckpoint =
            position.isLong ? cumulativeFundingPerSizeLong : cumulativeFundingPerSizeShort;
    }

    function pendingFunding(address account) external view returns (int256) {
        Position memory position = positions[account];
        if (!position.open) revert PositionNotOpen();

        (int256 longIndex, int256 shortIndex) = previewFundingIndexes();
        int256 current = position.isLong ? longIndex : shortIndex;
        int256 deltaPerSize = current - position.fundingCheckpoint;

        return (int256(position.sizeUsd) * deltaPerSize) / int256(PRECISION);
    }

    function accrueFunding() external {
        _accrue();
    }

    function previewFundingIndexes() public view returns (int256 longIndex, int256 shortIndex) {
        longIndex = cumulativeFundingPerSizeLong;
        shortIndex = cumulativeFundingPerSizeShort;

        if (
            block.timestamp == lastFundingTime || fundingRatePerSecond == 0
                || totalLongOpenInterest == 0 || totalShortOpenInterest == 0
        ) {
            return (longIndex, shortIndex);
        }

        uint256 duration = block.timestamp - lastFundingTime;
        uint256 absoluteRate =
            uint256(fundingRatePerSecond > 0 ? fundingRatePerSecond : -fundingRatePerSecond);

        if (fundingRatePerSecond > 0) {
            uint256 transferUsd = (totalLongOpenInterest * absoluteRate * duration) / PRECISION;
            if (transferUsd == 0) return (longIndex, shortIndex);

            longIndex -= int256((transferUsd * PRECISION) / totalLongOpenInterest);
            shortIndex += int256((transferUsd * PRECISION) / totalShortOpenInterest);
        } else {
            uint256 transferUsd = (totalShortOpenInterest * absoluteRate * duration) / PRECISION;
            if (transferUsd == 0) return (longIndex, shortIndex);

            shortIndex -= int256((transferUsd * PRECISION) / totalShortOpenInterest);
            longIndex += int256((transferUsd * PRECISION) / totalLongOpenInterest);
        }
    }

    function _accrue() internal {
        if (block.timestamp == lastFundingTime) return;

        if (fundingRatePerSecond == 0 || totalLongOpenInterest == 0 || totalShortOpenInterest == 0)
        {
            lastFundingTime = block.timestamp;
            return;
        }

        uint256 duration = block.timestamp - lastFundingTime;
        uint256 absoluteRate =
            uint256(fundingRatePerSecond > 0 ? fundingRatePerSecond : -fundingRatePerSecond);

        uint256 transferUsd;

        if (fundingRatePerSecond > 0) {
            transferUsd = (totalLongOpenInterest * absoluteRate * duration) / PRECISION;

            if (transferUsd != 0) {
                cumulativeFundingPerSizeLong -= int256(
                    (transferUsd * PRECISION) / totalLongOpenInterest
                );
                cumulativeFundingPerSizeShort += int256(
                    (transferUsd * PRECISION) / totalShortOpenInterest
                );
            }
        } else {
            transferUsd = (totalShortOpenInterest * absoluteRate * duration) / PRECISION;

            if (transferUsd != 0) {
                cumulativeFundingPerSizeShort -= int256(
                    (transferUsd * PRECISION) / totalShortOpenInterest
                );
                cumulativeFundingPerSizeLong += int256(
                    (transferUsd * PRECISION) / totalLongOpenInterest
                );
            }
        }

        totalAccruedFundingPaid += transferUsd;
        totalAccruedFundingReceived += transferUsd;
        lastFundingTime = block.timestamp;
    }

    function _pendingFunding(Position memory position) internal view returns (int256) {
        int256 current =
            position.isLong ? cumulativeFundingPerSizeLong : cumulativeFundingPerSizeShort;
        int256 deltaPerSize = current - position.fundingCheckpoint;

        return (int256(position.sizeUsd) * deltaPerSize) / int256(PRECISION);
    }
}
