# Solvency Queue Lab

[![Foundry CI](https://github.com/ayush585/solvency-queue-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/ayush585/solvency-queue-lab/actions/workflows/ci.yml)

A Foundry security lab for **perp-DEX custody, settlement, withdrawals, risk, liquidation, funding, oracle, and upgrade state machines**.

The goal is not to ship another toy token contract. The repo takes security properties that matter when contracts hold real value, deliberately breaks them, reproduces the failure, and then hardens the design with adversarial tests, fuzzing, stateful invariants, and Base Mainnet fork integration.

> Educational security lab. Not audited. Not production-ready.

## Verified snapshot

Current CI on `main`:

| Evidence | Verified result |
|---|---:|
| Local unit / adversarial / fuzz tests | **89 passed / 0 failed** |
| Base Mainnet fork tests | **3 passed / 0 failed** |
| Standalone fuzz tests | **7 × 1,000 runs** |
| Stateful invariant suites | **5** |
| Calls per invariant suite | **16,384** |
| Reverts in each invariant harness | **0** |
| Foundry | **v1.8.3** |
| OpenZeppelin Contracts | **v5.7.0** |

Stateful suites cover **Pool solvency, forced-withdrawal queues, sequencer settlement, perp clearing / bad debt, and funding**.

## What this lab demonstrates

- Solidity accounting for real ERC-20 assets and internal liabilities
- Foundry unit, fuzz, invariant, and fork testing
- adversarial ERC-20 behavior
- EIP-712 withdrawal authorization and replay resistance
- ECDSA malleability checks and domain separation
- failure-isolating forced-withdrawal queues
- sequencer / on-chain settlement trust boundaries
- backed cross-chain credit receipts
- linear perp P/L, initial margin, maintenance margin, and liquidation eligibility
- ERC-20-backed liquidation settlement, insurance, and explicit bad debt
- cumulative funding checkpoints and long/short conservation
- stale / future / malformed oracle rejection
- UUPS / ERC-1967 upgrade authorization and storage-layout corruption
- timelocked upgrade governance
- integration against canonical native USDC on **Base Mainnet**

## Failure classes reproduced

| Failure | Vulnerable behavior | Hardened property |
|---|---|---|
| Fee-on-transfer accounting | Credits requested amount although fewer tokens arrived | Credit observed balance delta |
| Signed-withdrawal replay | Nonce is signed but never consumed | Per-user nonce is validated and consumed once |
| FIFO head-of-line blocking | One blacklisted recipient freezes every later withdrawal | Failed entry is isolated; global cursor advances; retry remains possible |
| Fake sequencer credit | Correct batch nonce still creates unbacked liabilities | Cross-chain credit requires a one-time asset-backed receipt |
| Invalid settlement P/L | Privileged batch can create claims without conservation | Closed-model P/L is checked before applying state |
| Liquidation insolvency | Loss handling can become implicit or unaccounted | Collateral → insurance → explicit uncovered bad-debt waterfall |
| Funding double charge | Historical accrual could be charged repeatedly | Per-position cumulative funding checkpoints |
| Unsafe oracle use | Stale/future/zero data could feed liquidation math | All risk decisions pass through freshness/timestamp validation |
| UUPS storage corruption | New slot inserted before V1 state reinterprets financial/access-control storage | Safe V2 appends state; CI inspects layouts |
| Instant privileged upgrade | Admin could replace implementation immediately | Upgrade authority sits behind an explicit timelock |

## Architecture map

The modules are intentionally focused security labs rather than one claimed production protocol.

```text
                          ┌────────────────────┐
                          │   OracleGuard      │
                          └─────────┬──────────┘
                                    │ validated price
                          ┌─────────▼──────────┐
                          │ Perp risk / margin │
                          └────────────────────┘

 FundingMarket ── cumulative per-size funding checkpoints


 user ── deposit ────────────────┐
                                 ▼
                          ┌──────────────┐
                          │     Pool     │
                          │ assets/claims│
                          └──────┬───────┘
                                 │
             ┌───────────────────┼────────────────────┐
             │                   │                    │
             ▼                   ▼                    ▼
   WithdrawalManager   ForcedWithdrawalQueue   SettlementVerifier
       EIP-712              retry/liveness       batch nonce +
       nonce/replay                              economic checks
                                                       │
                                                       ▼
                                                DepositInbox
                                               backed receipts


                          ┌────────────────────┐
                          │ PerpClearingHouse  │
                          │ collateral         │
                          │ insurance          │
                          │ bad debt           │
                          └────────────────────┘


 ERC1967Proxy
      │
      ▼
 UpgradeVaultV1 ── safe UUPS upgrade ──► UpgradeVaultV2
      │
      └──────── bad layout ─────────────► observable corruption

 TimelockController ── delayed authority ──► UUPS upgrade
```

## Core invariants

### Solvency

```text
sum(user claims) <= assets actually held
```

In the closed Pool harness, where assets cannot be donated outside the modeled actions:

```text
total liabilities == Pool token balance
```

### Failed-withdrawal conservation

```text
failed withdrawal
=> user claim unchanged
=> backing unchanged
```

### Signed authorization uniqueness

```text
one valid signed nonce
=> at most one successful withdrawal
```

### Queue liveness

```text
failure(request[i])
must not permanently block
valid request[j > i]
```

### Sequencer settlement

```text
strict batch ordering
!=
economic validity
```

A new external deposit liability requires prior asset backing. In the deliberately closed P/L model:

```text
sum(batch P/L deltas) == 0
```

### Perp risk

```text
unrealized P/L
= sizeUsd × (markPrice - entryPrice) / entryPrice

equity
= collateral + unrealized P/L

liquidatable
<=> equity <= maintenance margin
```

### Liquidation asset conservation

```text
clearing-house token balance
=
open collateral + insurance balance
```

For bankruptcy:

```text
bad debt
=
insurance coverage + uncovered bad debt
```

### Funding conservation

```text
market funding paid == market funding received
```

For equal long / short OI:

```text
long total funding + short total funding == 0
```

### Upgrade safety

```text
governance delay
!=
storage-layout compatibility
```

Both authorization **and** storage compatibility are required.

## Base Mainnet fork

The fork gate exercises the hardened `Pool` against Circle's canonical native USDC deployment on Base:

```text
chain ID: 8453
USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

It verifies:

- the selected fork is Base Mainnet;
- the USDC address has live deployed code;
- the live token reports `USDC` with 6 decimals;
- deposit credit equals the actual token balance delta;
- deposit / withdrawal preserve Pool backing and liabilities.

Foundry's `deal` cheatcode seeds only ephemeral fork state; approvals and transfers still execute through the real deployed USDC implementation.

## Key files

### Custody and withdrawals

- `src/Pool.sol`
- `src/VulnerablePool.sol`
- `src/WithdrawalManager.sol`
- `src/VulnerableWithdrawalManager.sol`
- `src/ForcedWithdrawalQueue.sol`
- `src/VulnerableForcedWithdrawalQueue.sol`

### Settlement and perp risk

- `src/DepositInbox.sol`
- `src/SettlementVerifier.sol`
- `src/VulnerableSettlementVerifier.sol`
- `src/lib/PerpRisk.sol`
- `src/IsolatedMarginBook.sol`
- `src/PerpClearingHouse.sol`
- `src/FundingMarket.sol`
- `src/OracleGuard.sol`
- `src/OracleMarginBook.sol`

### Upgrade safety

- `src/upgrade/UpgradeVaultV1.sol`
- `src/upgrade/UpgradeVaultV2.sol`
- `src/upgrade/BadUpgradeVaultV2.sol`
- `test/UUPSUpgrade.t.sol`
- `test/UpgradeTimelock.t.sol`

### Stateful invariants

- `test/invariant/PoolInvariant.t.sol`
- `test/invariant/QueueInvariant.t.sol`
- `test/invariant/SettlementInvariant.t.sol`
- `test/invariant/ClearingHouseInvariant.t.sol`
- `test/invariant/FundingInvariant.t.sol`

### Fork integration

- `test/fork/BaseFork.t.sol`

See `SECURITY.md` for the detailed threat model, trust boundaries, and deliberate limitations.

## Run locally

Install dependencies:

```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-commit
```

Run deterministic local tests:

```bash
forge fmt --check
forge build
forge test --no-match-path 'test/fork/*.t.sol' -vv
```

Run Base integration:

```bash
BASE_RPC_URL=https://mainnet.base.org \
forge test --match-path 'test/fork/*.t.sol' -vv
```

## Scope and limitations

This repo deliberately does **not** claim to be a deployable perp DEX.

Important systems still outside the model include:

- a real matching engine and trade-proof mechanism;
- production oracle aggregation / confidence / deviation logic;
- funding debit/credit integrated directly into collateral balances;
- partial liquidation and ADL / socialized-loss resolution;
- multi-market portfolio margin;
- cross-chain message verification;
- production multisig operations and incident tooling;
- formal verification.

Those boundaries are documented rather than hidden behind a "production-ready" claim.
