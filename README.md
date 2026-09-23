# Solvency Queue Lab

A Foundry security lab for money-moving smart-contract state machines.

The project focuses on security properties that matter in custody, settlement, withdrawal, and queue-driven DeFi systems.

## Milestone 1 — solvency accounting

The first invariant is:

```text
internal liabilities <= assets actually controlled by the contract
```

A vulnerable Pool credits the requested ERC-20 transfer amount instead of the amount actually received. A fee-on-transfer token therefore creates immediate undercollateralization.

The hardened Pool measures balance deltas, preserves claims on failed withdrawals, and is exercised with deterministic exploits, fuzz tests, and stateful invariants.

## Milestone 2 — EIP-712 signed withdrawals

`VulnerableWithdrawalManager.sol` signs a nonce but never checks or consumes it, so one valid signature can be replayed.

The hardened manager binds user, token, recipient, amount, nonce, deadline, chain ID, and verifying contract. It enforces per-user nonces, supports relayers, rejects expired/high-s signatures, and relies on EVM atomicity to roll nonce consumption back on downstream failure.

## Milestone 3 — forced-withdrawal queue liveness

`VulnerableForcedWithdrawalQueue.sol` advances only after a successful FIFO withdrawal. A blacklisted head recipient therefore freezes every later request.

`ForcedWithdrawalQueue.sol` isolates failures:

```text
Pending -> Processing -> Processed
                     \
                      -> Failed -> retry -> Processed
                               \
                                -> Failed
```

Global FIFO progress continues, failed claims remain intact in Pool, and failed requests can be retried independently.

## Milestone 4 — sequencer settlement trust boundary

This milestone separates **ordering correctness** from **economic correctness**.

`VulnerableSettlementVerifier.sol` enforces a strict sequential batch nonce but still accepts arbitrary sequencer-supplied cross-chain credits and P/L changes.

The exploit demonstrates:

```text
victim deposits real assets
        ↓
sequencer submits correctly ordered fake attacker credit
        ↓
liabilities > assets
        ↓
attacker withdraws victim-backed real tokens
```

The batch nonce was correct the entire time.

`SettlementVerifier.sol` adds two deliberately narrow economic checks:

1. cross-chain credits must consume one-time `DepositInbox` receipts whose assets already reached Pool;
2. P/L updates in this closed-system model must sum to zero.

`DepositInbox.sol` measures the actual assets delivered to Pool before creating a creditable receipt, and each receipt can be consumed once.

### Important modeling boundary

Zero-sum P/L is intentionally a **closed settlement model for this lab**. Real perpetual protocols also have explicit fee, funding, insurance-fund, liquidation, LP/market-maker, and bad-debt accounts. Those flows must be represented as named counterparties or conservation terms rather than simply assuming every production batch sums to zero.

That richer perp accounting model is the next stage.

## Verification

CI uses Foundry v1.8.3:

```bash
forge fmt --check
forge build
forge test -vv
```

Current verified suite:

- **34 / 34 tests passing**;
- two 1,000-run fuzz tests;
- fee-on-transfer insolvency exploit reproduced;
- signed-withdrawal replay exploit reproduced;
- blacklisted FIFO head-of-line freeze reproduced;
- fake sequencer cross-chain-credit drain reproduced;
- EIP-712 replay/domain-separation coverage;
- retryable queue failure isolation;
- Pool stateful invariants: **256 runs / 16,384 calls / 0 reverts**;
- Queue stateful invariants: **256 runs / 16,384 calls / 0 reverts**;
- Settlement stateful invariants: **256 runs / 16,384 calls / 0 reverts**.

Settlement invariants cover:

```text
Pool liabilities == Pool backing assets

sum known user claims == total liabilities

next batch nonce == successful batch count
```

while randomly exercising backed credits, zero-sum P/L redistribution, and withdrawals.

## Repository map

```text
src/
  Pool.sol
  VulnerablePool.sol
  WithdrawalManager.sol
  VulnerableWithdrawalManager.sol
  ForcedWithdrawalQueue.sol
  VulnerableForcedWithdrawalQueue.sol
  DepositInbox.sol
  SettlementVerifier.sol
  VulnerableSettlementVerifier.sol
  interfaces/
  lib/
  mocks/

test/
  deterministic exploit / hardening tests
  invariant/
    PoolHandler.sol
    PoolInvariant.t.sol
    QueueHandler.sol
    QueueInvariant.t.sol
    SettlementHandler.sol
    SettlementInvariant.t.sol
```

## Core invariants

### Solvency

```text
sum user claims <= Pool assets
```

### Failed withdrawal conservation

```text
failed withdrawal => claim and backing unchanged
```

### Signed authorization uniqueness

```text
one valid signed nonce => at most one successful withdrawal
```

### Queue liveness

```text
a failed request cannot permanently block a later valid request
```

### Backed credit conservation

```text
new cross-chain liability requires previously delivered backing assets
```

### Closed-system settlement conservation

```text
sum(P/L deltas) == 0
```

## Roadmap

Next:

1. explicit perp collateral / margin / PnL accounting;
2. funding and fee system accounts;
3. maintenance margin and liquidation;
4. bad debt / insurance-fund behavior;
5. Base fork tests;
6. UUPS / storage-layout upgrade safety;
7. emergency pause / graceful degradation.

## Disclaimer

Educational security lab only. Not audited. Not production-ready.
