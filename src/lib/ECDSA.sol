// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ECDSA recovery helper with canonical low-s enforcement.
/// @dev Supports standard 65-byte {r,s,v} signatures used by this security lab.
library ECDSA {
    error InvalidSignature();
    error InvalidSignatureLength(uint256 length);
    error InvalidSignatureS(bytes32 s);
    error InvalidSignatureV(uint8 v);

    // secp256k1n / 2, required by EIP-2 to reject malleable high-s signatures.
    uint256 internal constant SECP256K1_HALF_ORDER =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    function recover(bytes32 digest, bytes memory signature)
        internal
        pure
        returns (address signer)
    {
        if (signature.length != 65) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (uint256(s) > SECP256K1_HALF_ORDER) revert InvalidSignatureS(s);
        if (v != 27 && v != 28) revert InvalidSignatureV(v);

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
