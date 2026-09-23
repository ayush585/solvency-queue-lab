// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeVaultV1} from "./UpgradeVaultV1.sol";

/// @title UpgradeVaultV2
/// @notice Storage-compatible V2: V1 fields remain untouched and new state is appended.
contract UpgradeVaultV2 is UpgradeVaultV1 {
    error V2AlreadyInitialized();

    address public guardian;
    bool public paused;
    uint256 private _v2InitializedFlag;

    event GuardianInitialized(address indexed guardian);
    event PauseUpdated(bool paused);

    function version() external pure override returns (uint256) {
        return 2;
    }

    function initializeV2(address guardian_) external onlyOwner {
        if (_v2InitializedFlag != 0) revert V2AlreadyInitialized();
        if (guardian_ == address(0)) revert ZeroAddress();

        _v2InitializedFlag = 1;
        guardian = guardian_;

        emit GuardianInitialized(guardian_);
    }

    function setPaused(bool paused_) external {
        if (msg.sender != owner && msg.sender != guardian) revert Unauthorized();

        paused = paused_;
        emit PauseUpdated(paused_);
    }
}
