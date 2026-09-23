# Solvency Queue Lab

A Foundry security lab for money-moving smart-contract state machines.

The project focuses on security properties that matter in custody, settlement, withdrawal, and queue-driven DeFi systems.

## Milestone 1 — solvency accounting

The first invariant is:

```text
internal liabilities <= assets actually controlled by the contract
```

The vulnerable implementation credits the requested ERC-20 transfer amount instead of the amount actually received. A fee-on-transfer token therefore creates immediate undercollateralization.

The hardened Pool:

- measures deposit balance deltas;
- credits only assets actually received;
- rejects outgoing token behavior that does not deliver the exact debited amount;
- relies on EVM atomicity so failed withdrawals preserve claims;
- is exercised with deterministic exploit tests, fuzz tests, and stateful invariants.

## Milestone 2 — EIP-712 signed withdrawals

The second failure class is authorization replay.

`VulnerableWithdrawalManager.sol` signs a nonce but never checks or consumes it. A relayer can submit the exact same valid signature twice and withdraw twice.

`WithdrawalManager.sol` hardens the flow by binding:

```text
user
token
recipient
amount
nonce
deadline
chainId
verifyingContract
```

The manager:

- checks and consumes a per-user nonce;
- allows third-party relayers;
- rejects expired authorizations;
- domain-separates signatures by chain and contract;
- rejects ECDSA high-s malleable signatures;
- consumes the nonce before the external Pool call while relying on transaction atomicity to roll it back if the Pool reverts.

The Pool exposes `withdrawFor` only to explicitly authorized withdrawal operators. Direct callers cannot bypass the manager.

## Repository map

```text
src/
  Pool.sol
  VulnerablePool.sol
  WithdrawalManager.sol
  VulnerableWithdrawalManager.sol
  interfaces/
  lib/
    ECDSA.sol
    SafeTransferLib.sol
  mocks/
    MockERC20.sol
    FeeOnTransferToken.sol

test/
  Pool.t.sol
  VulnerablePool.t.sol
  WithdrawalManager.t.sol
  VulnerableWithdrawalManager.t.sol
  invariant/
    PoolHandler.sol
    PoolInvariant.t.sol
```

## Verification

CI uses Foundry v1.8.3 and runs:

```bash
forge fmt --check
forge build
forge test -vv
```

Current verified coverage includes:

- deterministic fee-on-transfer insolvency exploit;
- deterministic signed-withdrawal replay exploit;
- two 1,000-run fuzz tests;
- three stateful solvency/accounting invariants over 256 runs and 16,384 calls;
- relayer execution;
- nonce replay rejection;
- recipient tampering;
- expired signatures;
- failed-withdrawal nonce rollback;
- cross-contract replay protection;
- cross-chain replay protection;
- ECDSA high-s malleability rejection;
- withdrawal-operator access control.

## Core invariants

### Solvency

```text
sum user claims <= pool token holdings
```

### Failed withdrawal conservation

```text
failed withdrawal => user claim and backing remain unchanged
```

### Signed authorization uniqueness

```text
one valid signed nonce => at most one successful withdrawal
```

### Domain separation

```text
authorization for contract A / chain X
must not authorize contract B / chain Y
```

## Roadmap

Next milestones:

1. Forced-withdrawal queue with liveness invariants.
2. Blacklisted-recipient / head-of-line blocking attack.
3. Reentrant and false-returning ERC-20 mocks.
4. Stateful queue fuzzing with handler/ghost variables.
5. Base fork tests.
6. Emergency pause / graceful-withdrawal semantics.

## Disclaimer

Educational security lab only. Not audited. Not production-ready.
