# Security model

This repository is a training lab, not production financial software.

## Asset / claim invariant

For each supported token:

```text
sum(user internal claims) <= ERC20.balanceOf(pool)
```

The vulnerable Pool violates this when it trusts the requested transfer amount for a fee-on-transfer token.

## Pool rules

1. Deposits credit only the observed balance delta.
2. A failed withdrawal must not reduce the user's internal claim.
3. A successful withdrawal must reduce Pool assets and increase recipient assets by exactly the debited claim.
4. Non-standard outgoing transfer behavior is rejected atomically.
5. Direct users can withdraw only their own claim.
6. `withdrawFor` is restricted to explicit withdrawal operators.

## Signed-withdrawal rules

The hardened EIP-712 authorization binds:

- user
- token
- recipient
- amount
- nonce
- deadline
- chain ID
- verifying contract

Security properties:

1. The recovered signer must equal `request.user`.
2. The request nonce must equal the current per-user nonce.
3. Every successful signed withdrawal increments that nonce exactly once.
4. A failed Pool withdrawal must roll the nonce increment back atomically.
5. Expired requests do not consume a nonce.
6. A signature for another contract or chain is invalid.
7. High-s ECDSA signatures are rejected.
8. The transaction sender is only a relayer; authorization comes from the signature.

## Deliberately vulnerable reference

`VulnerableWithdrawalManager.sol` includes the nonce in signed data but never checks or consumes it.

That demonstrates an important principle:

> putting a nonce inside a signature does not provide replay protection unless protocol state enforces uniqueness.

## Current trust boundary

The Pool owner can authorize or revoke withdrawal operators. An authorized operator can call `withdrawFor`, so each operator is a security-critical component and must enforce its own authorization rules correctly.

## Deliberate limitations

Not yet implemented:

- forced-withdrawal queue
- blacklisted-recipient failure isolation
- reentrancy-specific mocks
- upgradeability
- cross-chain settlement state
- account abstraction / passkeys
- formal verification

Those are subsequent milestones.
