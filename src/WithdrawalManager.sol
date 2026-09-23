// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pool} from "./Pool.sol";
import {ECDSA} from "./lib/ECDSA.sol";

/// @title WithdrawalManager
/// @notice EIP-712 withdrawal authorization with per-user nonce replay protection.
contract WithdrawalManager {
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
    error InvalidNonce(uint256 expected, uint256 actual);
    error InvalidSigner(address expected, address actual);

    event WithdrawalExecuted(
        address indexed user,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 nonce,
        address relayer
    );

    bytes32 public constant WITHDRAWAL_TYPEHASH = keccak256(
        "Withdrawal(address user,address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant NAME_HASH = keccak256("Solvency Queue Lab WithdrawalManager");
    bytes32 public constant VERSION_HASH = keccak256("1");

    Pool public immutable pool;
    mapping(address user => uint256 nonce) public nonces;

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

    /// @notice Anyone may relay a valid signed withdrawal.
    /// @dev The nonce is consumed before the external Pool call. If Pool reverts, EVM atomicity
    /// rolls the nonce change back together with the rest of this transaction.
    function withdrawWithSig(Withdrawal calldata request, bytes calldata signature) external {
        if (request.user == address(0) || request.recipient == address(0)) revert ZeroAddress();
        if (block.timestamp > request.deadline) revert Expired(request.deadline);

        uint256 expectedNonce = nonces[request.user];
        if (request.nonce != expectedNonce) {
            revert InvalidNonce(expectedNonce, request.nonce);
        }

        address signer = digest(request).recover(signature);
        if (signer != request.user) revert InvalidSigner(request.user, signer);

        nonces[request.user] = expectedNonce + 1;

        pool.withdrawFor(request.user, request.token, request.recipient, request.amount);

        emit WithdrawalExecuted(
            request.user,
            request.token,
            request.recipient,
            request.amount,
            request.nonce,
            msg.sender
        );
    }
}
