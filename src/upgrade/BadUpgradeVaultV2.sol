// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title BadUpgradeVaultV2
/// @notice Deliberately storage-incompatible implementation.
/// @dev Inserting emergencyThreshold before V1's owner shifts every subsequent storage slot.
contract BadUpgradeVaultV2 is UUPSUpgradeable {
    error Unauthorized();
    error ZeroAddress();

    // BAD: new variable inserted before every V1 field.
    uint256 public emergencyThreshold;

    address public owner;
    uint256 public collateralFactorBps;
    uint256 public totalLiabilities;
    mapping(address account => uint256 amount) public balanceOf;
    uint256 private _initializedFlag;

    constructor() {
        _initializedFlag = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function setEmergencyThreshold(uint256 threshold) external onlyOwner {
        emergencyThreshold = threshold;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
