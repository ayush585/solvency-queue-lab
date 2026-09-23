# Solvency Queue Lab

A Foundry security lab for money-moving smart-contract state machines.

The project focuses on security properties that matter in custody, settlement, withdrawal, and perpetual-DEX systems.

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

`ForcedWithdrawalQueue.sol` isolates failures, preserves failed claims, advances global FIFO progress, and allows failed requests to be retried without rewinding the queue.

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

The hardened lab requires one-time backed deposit receipts and zero-sum P/L in a deliberately closed settlement model.

## Milestone 5 — isolated perp risk and liquidation math

This milestone adds the first actual perpetual risk model.

`PerpRisk.sol` uses 18-decimal USD units with signed position size:

```text
size > 0 => long
size < 0 => short

unrealized P/L
    = sizeUsd × (markPrice - entryPrice) / entryPrice

equity
    = collateral + unrealized P/L

margin requirement
    = abs(sizeUsd) × marginBps / 10,000
```

`IsolatedMarginBook.sol` adds:

- initial-margin checks at position open;
- maintenance-margin calculations;
- isolated collateral additions;
- collateral-removal checks using current mark-price equity;
- liquidation eligibility;
- explicit notional / price bounds so extreme stored inputs cannot later make risk checks unusable.

The lab defines a position as liquidatable when:

```text
equity <= maintenance margin
```

The equality case is an explicit conservative boundary chosen for this lab, not a claim that every production perp protocol uses the same exact comparison operator.

### Modeling boundary

This milestone models **risk eligibility**, not asset settlement.

Liquidation currently closes risk state but does not yet distribute:

- remaining collateral;
- liquidation fees;
- funding;
- protocol fees;
- insurance-fund transfers;
- bad debt.

Those value flows belong in the next milestone so their conservation rules are explicit instead of hidden inside the risk formula.

## Verification

CI uses Foundry v1.8.3:

```bash
forge fmt --check
forge build
forge test -vv
```

Current verified suite:

- **46 / 46 tests passing**;
- four 1,000-run fuzz tests total;
- **12 / 12 isolated-margin risk tests passing**;
- long / short P/L symmetry fuzzed for 1,000 runs;
- zero P/L at entry fuzzed for 1,000 runs;
- exact maintenance-margin boundary tested;
- initial-margin and collateral-removal protections tested;
- fee-on-transfer insolvency exploit reproduced;
- signed-withdrawal replay exploit reproduced;
- blacklisted FIFO head-of-line freeze reproduced;
- fake sequencer cross-chain-credit drain reproduced;
- Pool stateful invariants: **256 runs / 16,384 calls / 0 reverts**;
- Queue stateful invariants: **256 runs / 16,384 calls / 0 reverts**;
- Settlement stateful invariants: **256 runs / 16,384 calls / 0 reverts**.

## Core invariants and properties

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

### Backed settlement credit

```text
new cross-chain liability requires previously delivered backing assets
```

### Closed settlement conservation

```text
sum(P/L deltas) == 0
```

### Perp P/L symmetry

For equal and opposite linear positions at the same entry/mark:

```text
long P/L == -short P/L
```

### Liquidation threshold

```text
liquidatable <=> equity <= maintenance margin
```

for this isolated-margin lab model.

## Roadmap

Next:

1. liquidation settlement + insurance fund + bad debt;
2. explicit trading / liquidation fees;
3. funding-payment system accounts;
4. oracle freshness / price sanity;
5. Base fork tests;
6. UUPS / storage-layout upgrade safety;
7. emergency pause / graceful degradation.

## Disclaimer

Educational security lab only. Not audited. Not production-ready.


## Milestone 5 — isolated perp risk and liquidation math

This milestone adds the first actual perpetual-risk state machine.

`PerpRisk.sol` models a linear perpetual using signed USD notional:

```text
sizeUsd > 0  => long
sizeUsd < 0  => short

unrealized PnL
= sizeUsd × (markPrice - entryPrice) / entryPrice

equity
= collateral + unrealized PnL

initial margin
= abs(sizeUsd) × initialMarginBps / 10_000

maintenance margin
= abs(sizeUsd) × maintenanceMarginBps / 10_000

liquidatable
= equity <= maintenance margin
```

`IsolatedMarginBook.sol` enforces:

- minimum initial margin at position open;
- bounded price and notional inputs before state is stored;
- long/short PnL symmetry;
- isolated collateral removal only when resulting equity still satisfies initial margin;
- exact maintenance-margin liquidation boundary;
- healthy positions cannot be liquidated;
- adding collateral can restore a position above maintenance.

### Verified risk coverage

- +10% price move on a long produces +10% notional PnL;
- -10% price move on a short produces +10% notional PnL;
- long and short PnL are symmetric;
- exact maintenance boundary is liquidatable;
- initial-margin undercollateralization is rejected;
- collateral removal cannot create an under-margined account;
- oversized/toxic risk inputs are rejected before arithmetic can become unusable;
- **2 fuzz tests × 1,000 runs** cover PnL symmetry and zero PnL at entry.

### Current full verification

```text
46 / 46 tests passing
Pool invariants:       256 runs / 16,384 calls / 0 reverts
Queue invariants:      256 runs / 16,384 calls / 0 reverts
Settlement invariants: 256 runs / 16,384 calls / 0 reverts
```

### Modeling boundary

This milestone decides **whether** an account is liquidatable and closes its risk state.

It does not yet settle:

- trader collateral;
- realized loss;
- liquidation fees;
- liquidator reward;
- insurance-fund transfers;
- bad debt;
- socialized loss;
- funding.

Those flows are intentionally the next milestone rather than being hidden inside the risk formula.
