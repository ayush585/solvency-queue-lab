# Solvency Queue Lab

A Foundry security lab for money-moving smart-contract state machines.

The project starts from one invariant that matters in any custody/accounting protocol:

```text
internal liabilities <= assets actually controlled by the contract
```

The first vulnerable implementation breaks that invariant by crediting the requested ERC-20 transfer amount instead of the amount actually received. A fee-on-transfer token creates immediate undercollateralization.

The hardened implementation:

- measures deposit balance deltas;
- credits only assets actually received;
- rejects outgoing token behavior that does not deliver the exact debited amount;
- relies on EVM atomicity so failed withdrawals preserve claims;
- is exercised with deterministic exploit tests, fuzz tests, and stateful invariant tests.

## Repository map

```text
src/
  VulnerablePool.sol
  Pool.sol
  interfaces/IERC20Minimal.sol
  lib/SafeTransferLib.sol
  mocks/MockERC20.sol
  mocks/FeeOnTransferToken.sol

test/
  VulnerablePool.t.sol
  Pool.t.sol
  invariant/
    PoolHandler.sol
    PoolInvariant.t.sol
```

## What the exploit demonstrates

For a token charging a 10% transfer fee:

```text
user requests deposit: 1,000
pool actually receives:   900
naive internal credit:  1,000
```

Result:

```text
liabilities = 1,000
assets      =   900
```

The contract is insolvent immediately even though every Solidity call succeeded.

## Install

This repo targets Foundry v1.8.3.

```bash
forge install foundry-rs/forge-std --no-commit
forge build
forge test -vv
```

For the stateful invariant suite:

```bash
forge test --match-contract PoolInvariantTest -vv
```

For a failing trace or deeper inspection:

```bash
forge test -vvvv
```

## Current invariants

### Solvency

```text
sum user claims <= pool token holdings
```

### Failed withdrawal conservation

```text
failed withdrawal => claim unchanged and pool backing unchanged
```

### Closed-system accounting

Under this test harness, where nobody transfers tokens directly to the Pool:

```text
totalLiabilities == pool token holdings
```

The equality is stronger than the production solvency invariant and makes accounting drift easier to detect.

## Roadmap

Next milestones intentionally mirror failure classes relevant to high-value DeFi systems:

1. EIP-712 withdrawal authorization + nonce replay resistance.
2. Forced-withdrawal queue with liveness invariants.
3. Blacklisted-recipient / head-of-line blocking attack.
4. Reentrant and false-returning ERC-20 mocks.
5. Stateful queue fuzzing with handler/ghost variables.
6. Base fork tests.
7. Emergency pause / graceful-withdrawal semantics.

## Disclaimer

Educational security lab only. Not audited. Not production-ready.
