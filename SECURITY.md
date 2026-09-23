# Security model

This repository is a training lab, not production financial software.

## Asset/claim model

For each supported token:

```text
sum(user internal claims) <= ERC20.balanceOf(pool)
```

The vulnerable implementation violates this when it trusts the requested transfer amount for a fee-on-transfer token.

## Hardened rules

1. Deposits credit only the observed balance delta.
2. A failed withdrawal must not reduce the user's internal claim.
3. A successful withdrawal must reduce pool assets and increase recipient assets by exactly the debited claim.
4. Non-standard outgoing transfer behavior is rejected atomically.
5. `msg.sender` cannot withdraw more than its internal claim.

## Deliberate limitations

This first milestone does not yet implement:

- EIP-712 withdrawal authorizations
- a forced-withdrawal queue
- blacklisted-recipient failure isolation
- reentrancy-specific mocks
- upgradeability
- cross-chain state

Those are subsequent milestones in the same lab.
