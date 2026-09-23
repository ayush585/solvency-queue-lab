// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title UpgradeVaultV1
/// @notice Minimal UUPS implementation with explicit storage used for upgrade-safety tests.
contract UpgradeVaultV1 is UUPSUpgradeable {
    error Unauthorized();
    error ZeroAddress();
    error AlreadyInitialized();
    error InvalidCollateralFactor();

    address public owner;
    uint256 public collateralFactorBps;
    uint256 public totalLiabilities;
    mapping(address account => uint256 amount) public balanceOf;
    uint256 private _initializedFlag;

    event Credited(address indexed account, uint256 amount);
    event CollateralFactorUpdated(uint256 oldFactor, uint256 newFactor);

    /// @dev Locks the implementation instance itself while leaving proxy storage uninitialized.
    constructor() {
        _initializedFlag = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function initialize(address owner_, uint256 collateralFactorBps_) external {
        if (_initializedFlag != 0) revert AlreadyInitialized();
        if (owner_ == address(0)) revert ZeroAddress();
        if (collateralFactorBps_ == 0 || collateralFactorBps_ > 10_000) {
            revert InvalidCollateralFactor();
        }

        _initializedFlag = 1;
        owner = owner_;
        collateralFactorBps = collateralFactorBps_;
    }

    function version() external pure virtual returns (uint256) {
        return 1;
    }

    function credit(address account, uint256 amount) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();

        balanceOf[account] += amount;
        totalLiabilities += amount;

        emit Credited(account, amount);
    }

    function setCollateralFactor(uint256 newFactor) external onlyOwner {
        if (newFactor == 0 || newFactor > 10_000) revert InvalidCollateralFactor();

        uint256 oldFactor = collateralFactorBps;
        collateralFactorBps = newFactor;

        emit CollateralFactorUpdated(oldFactor, newFactor);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
