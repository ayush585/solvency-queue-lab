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

## Forced-withdrawal queue rules

The queue exists to preserve global withdrawal progress when individual requests fail.

Security properties:

1. `nextToProcess` never decreases.
2. `nextToProcess <= requestCount`.
3. Every entry behind the cursor is terminal: `Processed` or `Failed`.
4. Every unattempted entry ahead of the cursor remains `Pending`.
5. A failed request does not destroy the user's Pool claim.
6. A failed request cannot stop later valid requests from being attempted.
7. A failed request remains retryable.
8. A processed request cannot be retried.
9. Processing and retry entrypoints are non-reentrant.
10. Successful payouts and outstanding claims must conserve deposited value.

### Why failure isolation matters

The deliberately vulnerable queue performs:

```text
withdraw head
-> if success: increment cursor
```

A recipient-specific token revert therefore leaves the cursor unchanged and freezes all later users.

The hardened queue performs:

```text
mark Processing
-> advance cursor
-> try Pool withdrawal
   -> success: Processed
   -> revert:  Failed
```

The failed Pool call reverts its own state changes, so the user's claim remains in the Pool while the queue itself retains global progress.

### Retry model

Retries operate on failed entries directly and do not move the FIFO cursor. If the original failure condition disappears, the request can later transition from `Failed` to `Processed`.

## Deliberately vulnerable references

- `VulnerablePool.sol`: credits requested deposit amount instead of received assets.
- `VulnerableWithdrawalManager.sol`: signs a nonce but never enforces it.
- `VulnerableForcedWithdrawalQueue.sol`: lets one failing FIFO head freeze every later request.

## Current trust boundaries

- The Pool owner can authorize or revoke withdrawal operators.
- Each authorized operator can call `withdrawFor` and is therefore security-critical.
- The blacklist token mock has a privileged owner that can change recipient blacklist state.
- The hardened queue catches Pool execution failure generically; it does not yet classify or bound every possible external-call failure mode.

## Deliberate limitations

Not yet implemented:

- reserved balances for queued requests;
- bounded-gas external processing;
- stored failure-reason classification;
- reentrancy-specific malicious token mocks;
- false-returning / malformed ERC-20 mocks;
- upgradeability;
- cross-chain settlement state;
- account abstraction / passkeys;
- formal verification.

Those are subsequent milestones.
