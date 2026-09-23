# Security model

This repository is a training lab, not production financial software.

## Pool solvency

For each supported token:

```text
sum(user internal claims) <= ERC20.balanceOf(pool)
```

Deposits credit observed assets, failed withdrawals preserve claims atomically, and privileged withdrawal / settlement operators are explicit trust boundaries.

## Signed withdrawals

The hardened EIP-712 flow binds user, token, recipient, amount, nonce, deadline, chain ID, and verifying contract.

A successful signed authorization consumes exactly one nonce. Failed downstream execution rolls that state change back.

## Forced-withdrawal queue

The hardened queue preserves global liveness while retaining failed user claims for retry.

Key properties include monotonic bounded cursor movement, terminal state for attempted entries, pending state for future entries, retryability of failed requests, and conservation of deposits across outstanding claims plus successful payouts.

## Sequencer settlement

A strict batch nonce provides ordering and replay protection. It does **not** prove that credits are backed, P/L is economically valid, or off-chain trades occurred.

The hardened lab model therefore requires:

- exact sequential batch nonce;
- sequencer authorization;
- one-time asset-backed deposit receipts;
- zero-sum P/L in the closed settlement model.

That zero-sum rule is intentionally not presented as a universal perp formula. Production systems must explicitly model fees, funding, liquidation flows, insurance, LP / market-maker counterparties, and bad debt.

## Perp risk model

`PerpRisk.sol` models a linear perpetual:

```text
P/L = signed size × price change / entry price
equity = collateral + P/L
margin = notional × configured margin rate
```

Positive signed size is long; negative signed size is short.

### Risk properties

1. Opening collateral must meet initial margin.
2. Maintenance margin is lower than initial margin by constructor configuration.
3. Collateral removal must leave resulting equity at or above initial margin.
4. In this lab, liquidation becomes eligible at `equity <= maintenance margin`.
5. Equal-and-opposite positions at the same entry and mark have equal-and-opposite price P/L.
6. P/L is zero at entry price.
7. Position notional and price inputs are bounded when opened.
8. Mark prices are bounded inside the pure risk math before multiplication.

### Arithmetic bounds

The lab caps:

```text
abs(sizeUsd) <= 1e36
price <= 1e30
```

These bounds keep `size × priceDelta` safely inside signed 256-bit arithmetic for the lab's 18-decimal USD representation.

Margin requirements are also bounded by notional and a rate no greater than 100%, so conversions used when comparing unsigned margin requirements with signed equity are safe under these bounds.

### Liquidation-boundary convention

The lab uses:

```text
equity <= maintenance margin
```

as the liquidation threshold.

This is a conservative explicit convention for this project. Different production protocols can differ in exact boundary semantics, fee inclusion, oracle choice, maintenance tiers, or pre-liquidation buffers.

### What liquidation does not yet mean

`IsolatedMarginBook.liquidate` currently closes position risk state only.

It does **not** yet settle:

- trader residual equity;
- counterparty / LP P&L;
- liquidator rewards;
- liquidation fees;
- protocol fees;
- funding;
- insurance-fund debits;
- bad debt.

Those are intentionally deferred so the next milestone can encode a full conservation equation.

## Deliberately vulnerable references

- `VulnerablePool.sol`: unbacked fee-on-transfer deposit accounting.
- `VulnerableWithdrawalManager.sol`: signed nonce without replay enforcement.
- `VulnerableForcedWithdrawalQueue.sol`: FIFO head-of-line blocking.
- `VulnerableSettlementVerifier.sol`: sequential batches that can still create arbitrary liabilities.

## Current invariant evidence

Three independent stateful suites cover Pool accounting, queue liveness, and settlement conservation.

Each verified suite runs:

```text
256 invariant runs
16,384 randomized handler calls
0 handler reverts
```

The perp risk layer additionally has deterministic boundary tests and two 1,000-run fuzz properties.

## Deliberate limitations

Not yet implemented:

- liquidation asset settlement;
- insurance fund / bad debt;
- funding;
- trading / liquidation fees;
- oracle freshness / manipulation checks;
- Base fork state;
- UUPS storage layouts and upgrade authorization;
- formal verification;
- cross-chain message proofs.

Those are subsequent milestones.


## Isolated perpetual risk

The perp-risk module introduces signed linear position accounting.

Security properties:

1. positive size is long and negative size is short;
2. long/short PnL is symmetric for equal and opposite positions;
3. PnL is zero when mark price equals entry price;
4. a position cannot open below initial margin;
5. collateral cannot be removed if resulting equity falls below initial margin;
6. liquidation is allowed only when equity is at or below maintenance margin;
7. exact maintenance-margin equality is treated as liquidatable;
8. extreme notional/price inputs are rejected before state storage and before unsafe multiplication.

### Risk-only limitation

`IsolatedMarginBook` intentionally separates **risk eligibility** from **financial settlement**.

Closing a liquidatable position currently changes risk state only. It does not decide who absorbs losses or how remaining collateral is distributed.

The next security boundary is therefore:

```text
liquidation equity >= 0
    => residual collateral allocation + liquidation fee

liquidation equity < 0
    => bad debt
    => insurance fund / explicit loss waterfall
```

Until that layer exists, the module must not be described as a production liquidation engine.


## Liquidation loss waterfall

The clearing-house milestone converts abstract liquidation equity into actual token movements.

### Solvent liquidation invariant

For positive liquidation equity:

```text
collateral
=
realized loss paid to counterparty
+
liquidation fee retained as insurance
+
trader residual
```

The fee is capped by positive equity, so liquidation cannot create a negative trader payout.

### Bankruptcy invariant

For negative equity:

```text
bad debt
=
insurance coverage
+
uncovered bad debt
```

and:

```text
counterparty payout
=
all trader collateral
+
insurance coverage
```

The protocol does not fabricate settlement assets to erase a deficit.

### Asset conservation

Under the stateful harness:

```text
clearing-house ERC-20 balance
=
total open collateral
+
insurance balance
```

and every minted settlement token remains located in one of:

- clearing house;
- explicit counterparty;
- trader wallets;
- invariant handler during funding setup.

### Bad-debt monotonicity

The current model has no debt-resolution path.

Therefore:

```text
uncoveredBadDebt(t + 1) >= uncoveredBadDebt(t)
```

must hold.

A future ADL / recapitalization mechanism must make any decrease explicit and separately conserved.

### Trust boundary

The fixed `counterparty` address represents the winning-side/system settlement recipient. That is a deliberate simplification: a production matching engine must prove which counterparties are owed realized P/L rather than routing all losses to one address.
