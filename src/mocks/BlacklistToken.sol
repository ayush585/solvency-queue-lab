// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockERC20} from "./MockERC20.sol";

/// @notice ERC-20 mock that rejects transfers to blacklisted recipients.
/// @dev Models recipient-specific transfer failure such as a centrally blacklisted stablecoin address.
contract BlacklistToken is MockERC20 {
    error Unauthorized();
    error RecipientBlacklisted(address recipient);

    address public immutable owner;
    mapping(address account => bool blocked) public blacklisted;

    constructor() MockERC20("Blacklist Token", "BLK") {
        owner = msg.sender;
    }

    function setBlacklisted(address account, bool blocked) external {
        if (msg.sender != owner) revert Unauthorized();
        blacklisted[account] = blocked;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (blacklisted[to]) revert RecipientBlacklisted(to);
        super._transfer(from, to, amount);
    }
}
