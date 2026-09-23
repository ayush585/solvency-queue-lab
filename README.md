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

## Milestone 3 — forced-withdrawal queue liveness

The third failure class is FIFO head-of-line blocking.

`VulnerableForcedWithdrawalQueue.sol` advances its queue cursor only after the Pool withdrawal succeeds. If request 0 targets a recipient rejected by the token, the external call reverts, the cursor stays at 0, and every valid request behind it remains frozen.

`ForcedWithdrawalQueue.sol` isolates that failure:

```text
Pending -> Processing -> Processed
                     \
                      -> Failed -> retry -> Processed
                               \
                                -> Failed
```

The hardened queue:

- advances global FIFO progress even when one withdrawal fails;
- records failed requests instead of silently dropping them;
- leaves the failed user's Pool claim untouched because the failed Pool call reverts atomically;
- allows failed requests to be retried later without rewinding the queue;
- prevents processed entries from being retried;
- uses a reentrancy guard around processing and retries.

`BlacklistToken.sol` models recipient-specific transfer failure such as a blacklisted stablecoin address.

## Repository map

```text
src/
  Pool.sol
  VulnerablePool.sol
  WithdrawalManager.sol
  VulnerableWithdrawalManager.sol
  ForcedWithdrawalQueue.sol
  VulnerableForcedWithdrawalQueue.sol
  interfaces/
  lib/
    ECDSA.sol
    SafeTransferLib.sol
  mocks/
    MockERC20.sol
    FeeOnTransferToken.sol
    BlacklistToken.sol

test/
  Pool.t.sol
  VulnerablePool.t.sol
  WithdrawalManager.t.sol
  VulnerableWithdrawalManager.t.sol
  ForcedWithdrawalQueue.t.sol
  VulnerableForcedWithdrawalQueue.t.sol
  invariant/
    PoolHandler.sol
    PoolInvariant.t.sol
    QueueHandler.sol
    QueueInvariant.t.sol
```

## Verification

CI uses Foundry v1.8.3 and runs:

```bash
forge fmt --check
forge build
forge test -vv
```

Current verified coverage:

- **25 / 25 tests passing**;
- deterministic fee-on-transfer insolvency exploit;
- deterministic signed-withdrawal replay exploit;
- deterministic blacklisted-head FIFO freeze;
- two 1,000-run fuzz tests;
- three Pool invariants across **256 runs / 16,384 calls / 0 reverts**;
- five queue invariants across **256 runs / 16,384 calls / 0 reverts**;
- relayer execution and nonce replay protection;
- cross-contract and cross-chain EIP-712 replay protection;
- ECDSA high-s malleability rejection;
- failed queue entry isolation;
- successful processing behind a failed head;
- failed-request retry and claim preservation.

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

### Queue monotonicity

```text
0 <= nextToProcess <= requestCount
nextToProcess never decreases
```

### Queue failure isolation

```text
failure(request[i])
must not permanently block valid request[j > i]
```

### Queue accounting conservation

```text
deposits = outstanding claims + successful payouts
```

## Roadmap

Next milestones:

1. Reentrant and false-returning ERC-20 mocks.
2. Queue failure-reason / bounded-gas hardening.
3. Base fork tests.
4. Emergency pause / graceful-withdrawal semantics.
5. UUPS / storage-layout upgrade safety.
6. Perp collateral and liquidation accounting.

## Disclaimer

Educational security lab only. Not audited. Not production-ready.
