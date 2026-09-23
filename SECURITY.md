# Security model

This repository is a training lab, not production financial software.

## Pool solvency

For each supported token:

```text
sum(user internal claims) <= ERC20.balanceOf(pool)
```

Deposits credit observed assets, failed withdrawals preserve claims atomically, and privileged withdrawal/settlement operators are explicit trust boundaries.

## Signed withdrawals

The hardened EIP-712 flow binds user, token, recipient, amount, nonce, deadline, chain ID, and verifying contract.

A successful signed authorization consumes exactly one nonce. Failed downstream execution rolls that state change back.

## Forced-withdrawal queue

Security properties:

1. cursor never decreases;
2. cursor never exceeds request count;
3. attempted entries are terminal: Processed or Failed;
4. unattempted entries remain Pending;
5. failed Pool execution preserves the user's claim;
6. one failing recipient cannot permanently block later requests;
7. failed requests remain retryable;
8. processed requests cannot replay;
9. processing/retry entrypoints are non-reentrant.

## Sequencer settlement

A strict batch nonce provides ordering and replay protection. It does **not** prove that credits are backed, that P/L is economically valid, or that off-chain trades actually occurred.

`VulnerableSettlementVerifier.sol` deliberately demonstrates that distinction.

### Hardened lab model

`DepositInbox` creates a deposit receipt only after the exact corresponding token amount reaches Pool. The receipt is one-time consumable.

`SettlementVerifier` requires:

- exact sequential batch nonce;
- sequencer authorization;
- backed one-time deposit receipts;
- zero-sum P/L in the lab's closed accounting model.

All batch state is atomic. If a later P/L application fails, the batch nonce, deposit-receipt consumption, and earlier credits roll back together.

### Closed-system P/L limitation

The invariant:

```text
sum P/L deltas == 0
```

is not intended as a universal perpetual-DEX formula.

Production perp settlement must explicitly model value flows involving trading fees, funding payments, liquidation fees, insurance funds, LP / market-maker counterparties, protocol revenue, and bad debt / socialized loss.

The next accounting milestone should turn those into explicit system accounts and conservation equations.

## Deliberately vulnerable references

- `VulnerablePool.sol`: unbacked fee-on-transfer deposit accounting.
- `VulnerableWithdrawalManager.sol`: signed nonce without replay enforcement.
- `VulnerableForcedWithdrawalQueue.sol`: FIFO head-of-line blocking.
- `VulnerableSettlementVerifier.sol`: sequential batches that can still create arbitrary liabilities.

## Trust boundaries

- Pool owner controls operator authorization.
- Withdrawal operators can execute user claims and must authenticate correctly.
- Settlement operators can change internal claims and therefore require batch-level economic validation.
- DepositInbox owner selects its one-time consumer.
- The sequencer remains trusted to provide valid trade results within the invariants enforced on-chain.
- The lab does not prove off-chain trade execution correctness.

## Current invariant evidence

Three independent stateful suites currently cover Pool accounting, queue liveness, and settlement conservation.

Each runs:

```text
256 invariant runs
16,384 randomized handler calls
0 handler reverts
```

on the verified CI head.

## Deliberate limitations

Not yet implemented:

- real perp position accounting;
- mark/index prices and oracle validation;
- funding;
- maintenance margin;
- liquidation;
- insurance fund / bad debt;
- Base fork state;
- UUPS storage layouts and upgrade authorization;
- formal verification;
- cross-chain message proofs.

Those are subsequent milestones.
