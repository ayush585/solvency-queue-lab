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


## Milestone 6 — liquidation settlement, insurance, and bad debt

`PerpClearingHouse.sol` moves liquidation from pure risk math into actual ERC-20 settlement.

The clearing house holds real settlement-token balances for:

```text
open position collateral
+
insurance assets
```

and exposes those buckets directly through:

```text
token.balanceOf(clearingHouse)
==
totalOpenCollateral + insuranceBalance
```

### Solvent liquidation

For a liquidatable account with positive remaining equity:

```text
realized trader loss -> counterparty/system account

remaining positive equity
    -> liquidation fee (capped by equity) -> insurance
    -> residual -> trader
```

The liquidation fee is based on position notional but can never consume more than the trader's remaining positive equity.

### Bankrupt liquidation

If the account equity is negative:

```text
trader collateral exhausted first
        ↓
insurance covers min(deficit, insuranceBalance)
        ↓
remaining deficit -> cumulative uncoveredBadDebt
```

No hidden minting occurs to make the books balance.

### Asset behavior

- collateral is transferred into the clearing house at position open;
- insurance funding is transferred in as real tokens;
- fee-on-transfer collateral is rejected via exact balance-delta checks;
- liquidation settlement uses the same ERC-20 backing that the invariant suite observes.

### Verified loss-waterfall coverage

- solvent liquidation loss / fee / trader-residual split;
- partial insurance coverage;
- full insurance coverage;
- liquidation fee capped by remaining positive equity;
- healthy-position liquidation rejection;
- real-token insurance backing;
- fee-on-transfer collateral rejection with atomic rollback;
- **1,000-run fuzz test** over insurance size and adverse price movement.

### Stateful clearing-house invariants

The handler randomizes:

- insurance funding;
- long/short position opens;
- adverse liquidations.

Verified across:

```text
256 invariant runs
16,384 randomized calls
0 handler reverts
```

with these properties:

```text
engine token balance
==
open collateral + insurance

all minted settlement assets remain accounted for

token total supply
==
tracked minted assets

aggregate open-position collateral
==
totalOpenCollateral

uncovered bad debt never decreases
without an explicit resolution mechanism
```

### Current full suite

```text
55 / 55 tests passing
4 independent stateful invariant suites
each at 256 runs / 16,384 calls / 0 reverts
```

### Modeling boundary

The counterparty is an explicit system recipient standing in for the winning side / settlement counterparty.

The lab still does not model:

- matching-engine trade execution;
- funding accrual;
- oracle validity / staleness;
- partial liquidation;
- ADL / socialized-loss resolution;
- insurance recapitalization;
- multi-market netting.

Those remain explicit future layers instead of being hidden inside liquidation accounting.


## Milestone 7 — funding checkpoints and oracle safety

This milestone adds two separate perp-risk boundaries: funding settlement and price freshness.

### Funding checkpoints

`FundingMarket.sol` stores cumulative funding-per-size indexes for the long and short sides.

The signed rate convention is:

```text
fundingRatePerSecond > 0
=> longs pay shorts

fundingRatePerSecond < 0
=> shorts pay longs
```

Each position snapshots the current side-specific cumulative funding index when it opens or settles.

Pending funding is then:

```text
position size
×
(current cumulative index - position checkpoint)
/
precision
```

This means a position is charged only for funding accrued since its own checkpoint rather than for market history that existed before the position.

The receiving side is scaled by long/short open interest so market-level funding paid equals market-level funding received even when OI is unequal.

Verified behaviors:

- equal-OI long/short funding nets exactly to zero;
- unequal OI scales the receiving side without creating value;
- repeated settlement at the same checkpoint cannot double-charge;
- a new position does not inherit historical funding;
- rate direction can reverse;
- no funding accrues while one side has zero open interest;
- funding rate is explicitly bounded;
- unequal-OI conservation is fuzzed within integer-rounding dust.

### Stateful funding invariants

The funding handler randomizes:

- authorized funding-rate changes;
- time jumps;
- explicit accrual;
- long settlement;
- short settlement.

Verified:

```text
totalFundingPaid == totalFundingReceived

equal-OI long total funding
+
equal-OI short total funding
== 0

longOI == shortOI
```

across:

```text
256 invariant runs
16,384 randomized calls
0 handler reverts
```

### Oracle safety

`OracleGuard.sol` wraps an external price feed and rejects:

- zero price;
- missing timestamp;
- future timestamp;
- stale timestamp.

The freshness rule is half-open in time:

```text
block.timestamp - updatedAt <= maxAge
=> accepted

block.timestamp - updatedAt > maxAge
=> stale
```

`OracleMarginBook.sol` uses only `OracleGuard.validatedPrice()` for:

- position entry;
- equity;
- liquidation checks;
- liquidation execution.

A caller cannot supply an arbitrary mark price to the liquidation path.

Verified behaviors:

- exact max-age boundary accepted;
- one second beyond max age rejected;
- future timestamps rejected;
- zero / missing data rejected;
- stale oracle data cannot liquidate a position;
- fresh oracle data can liquidate exactly at maintenance margin;
- **1,000-run freshness-boundary fuzz test**.

### Current full verification

```text
73 / 73 tests passing
5 independent stateful invariant suites
each at 256 runs / 16,384 calls / 0 reverts
```

This milestone follows the same broad pattern used by current perp protocols: cumulative per-position funding checkpoints and oracle-driven collateral/liquidation decisions. It intentionally keeps the rate source and oracle aggregation mechanism outside the lab so those trust boundaries remain explicit rather than implied.


## Milestone 8 — UUPS upgrade and storage-layout safety

This milestone uses OpenZeppelin Contracts v5.7.0 with an ERC-1967 proxy and UUPS implementation logic.

`UpgradeVaultV1.sol` stores:

```text
slot 0: owner
slot 1: collateralFactorBps
slot 2: totalLiabilities
slot 3: balanceOf mapping seed
slot 4: initialization flag
```

The implementation instance locks its own initializer in its constructor, while the proxy is initialized atomically through `ERC1967Proxy` constructor calldata.

### Safe V2

`UpgradeVaultV2.sol` preserves every V1 field and appends new guardian/pause state.

Verified after upgrade:

- owner preserved;
- collateral factor preserved;
- total liabilities preserved;
- existing mapping balances preserved;
- implementation reports V2;
- new guardian state can initialize once;
- guardian pause authority works;
- V2 initializer cannot replay.

### Deliberately bad V2

`BadUpgradeVaultV2.sol` inserts:

```text
slot 0: emergencyThreshold
```

before the original V1 state.

That shifts every V1 slot:

```text
old owner             -> interpreted as emergencyThreshold
old collateral factor -> interpreted as owner
old total liabilities -> interpreted as collateralFactor
old mapping base       -> interpreted as totalLiabilities
old mapping entries    -> no longer reachable through the new mapping slot
```

The corruption is severe enough that the original owner can lose authorization to upgrade the proxy back to a safe implementation.

### Upgrade authorization

`_authorizeUpgrade` is owner-gated.

Verified:

- unauthorized account cannot upgrade;
- upgrade function cannot be used directly on the implementation;
- non-UUPS targets are rejected by OpenZeppelin's UUPS compatibility check.

### CI storage evidence

CI now runs:

```bash
forge inspect UpgradeVaultV1 storage-layout
forge inspect UpgradeVaultV2 storage-layout
forge inspect BadUpgradeVaultV2 storage-layout
```

and tests the observed state behavior behind a real ERC-1967 proxy.

### Current full verification

```text
82 / 82 tests passing
5 stateful invariant suites
OpenZeppelin Contracts v5.7.0
Foundry v1.8.3
```


## Milestone 9 — timelocked upgrade governance

The proxy owner is moved from a directly callable EOA to OpenZeppelin `TimelockController`.

Governance roles are explicit:

```text
proposer
  -> schedules upgrade

canceller
  -> may cancel scheduled operation

executor
  -> executes only after minDelay

timelock contract
  -> is the UUPS proxy owner
```

The lab uses a two-day minimum delay.

Verified:

- direct EOAs cannot bypass the timelock and call UUPS upgrade authority;
- unauthorized accounts cannot schedule upgrades;
- scheduled upgrades cannot execute before the delay;
- unscheduled operations cannot execute even after arbitrary time passes;
- explicitly cancelled upgrades cannot execute;
- a delayed safe V2 upgrade preserves V1 state;
- V2 initialization can execute atomically inside `upgradeToAndCall`;
- a timelock does **not** make an incompatible implementation safe.

The last point is deliberate:

```text
governance delay
!=
storage-layout validation
```

A delayed bad implementation still corrupts state when executed.

### Current full verification

```text
89 / 89 tests passing
OpenZeppelin Contracts v5.7.0
Foundry v1.8.3
```


## Milestone 10 — Base Mainnet fork integration

The lab now has a dedicated fork-testing gate against live Base Mainnet state.

Fork target:

```text
chain ID: 8453
default RPC: https://mainnet.base.org
canonical native USDC:
0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

The fork tests verify:

- the selected fork is actually Base Mainnet;
- canonical Base USDC has deployed runtime code;
- the live contract reports `USDC` and 6 decimals;
- the hardened Pool can approve, deposit, account for, and withdraw against the real deployed USDC implementation;
- the Pool credits the exact observed balance delta;
- Pool liabilities remain equal to real USDC backing after deposit and withdrawal.

Foundry's token `deal` cheatcode is used only to seed a fork-local test balance. The ERC-20 code path exercised by approvals/transfers is the actual Base deployment.

CI keeps fork integration separate from deterministic local tests:

```bash
forge test --no-match-path 'test/fork/*.t.sol' -vv
forge test --match-path 'test/fork/*.t.sol' -vv
```

Verified CI result:

```text
local unit/fuzz/invariant tests:
89 passed / 0 failed

Base Mainnet fork:
3 passed / 0 failed
```

The fork gate is intentionally small: it proves that the accounting assumptions survive contact with a real Base asset without turning the entire test suite into an RPC-dependent integration suite.
