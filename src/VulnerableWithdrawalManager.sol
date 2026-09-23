// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";
import {ECDSA} from "./lib/ECDSA.sol";

/// @notice Intentionally vulnerable EIP-712 withdrawal manager used to demonstrate replay.
/// @dev The signed nonce is included in the message but never checked or consumed.
contract VulnerableWithdrawalManager {
    using ECDSA for bytes32;

    struct Withdrawal {
        address user;
        address token;
        address recipient;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    error ZeroAddress();
    error Expired(uint256 deadline);
    error InvalidSigner(address expected, address actual);

    bytes32 public constant WITHDRAWAL_TYPEHASH = keccak256(
        "Withdrawal(address user,address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant NAME_HASH = keccak256("Solvency Queue Lab VulnerableWithdrawalManager");
    bytes32 public constant VERSION_HASH = keccak256("1");

    Pool public immutable pool;

    constructor(Pool pool_) {
        if (address(pool_) == address(0)) revert ZeroAddress();
        pool = pool_;
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this))
        );
    }

    function structHash(Withdrawal calldata request) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                WITHDRAWAL_TYPEHASH,
                request.user,
                request.token,
                request.recipient,
                request.amount,
                request.nonce,
                request.deadline
            )
        );
    }

    function digest(Withdrawal calldata request) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash(request)));
    }

    function withdrawWithSig(Withdrawal calldata request, bytes calldata signature) external {
        if (request.user == address(0) || request.recipient == address(0)) revert ZeroAddress();
        if (block.timestamp > request.deadline) revert Expired(request.deadline);

        address signer = digest(request).recover(signature);
        if (signer != request.user) revert InvalidSigner(request.user, signer);

        // BUG: request.nonce is never validated or consumed.
        pool.withdrawFor(request.user, request.token, request.recipient, request.amount);
    }
}
