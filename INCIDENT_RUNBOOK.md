# Incident Response Runbook

This runbook describes the operational model implemented by `OperationalSafetyVault.sol`.

It is an educational security lab, not a production incident-management policy.

## Goals

During an incident, prefer explicit degraded modes over continuing normal operation under uncertain state.

The safety order is:

```text
protect accounting integrity
        ↓
stop new risk
        ↓
preserve user exits when safe
        ↓
halt completely if backing is compromised
        ↓
reconcile
        ↓
recover deliberately
```

## Modes

### Active

Allowed:

- deposits;
- sequencer state changes;
- direct user withdrawals;
- sequencer heartbeats.

### ExitOnly

Allowed:

- direct user withdrawals;
- sequencer heartbeat for liveness recovery.

Blocked:

- new deposits;
- sequencer balance/P&L state changes;
- new internal liabilities.

Use this mode when the system should stop taking new risk but custody remains solvent enough for users to exit.

### Halted

Blocked:

- deposits;
- sequencer state changes;
- withdrawals.

Use only when allowing transfers may worsen an exploit or when actual token backing is below internal liabilities.

## Trigger matrix

| Signal | Expected response |
|---|---|
| Sequencer inactivity reaches threshold | Anyone may trigger `ExitOnly` |
| Monitoring detects suspicious behavior | Monitor / guardian enters `ExitOnly` |
| Confirmed exploit with uncertain transfer safety | Guardian enters `Halted` |
| Token backing < internal liabilities | Anyone may trigger `Halted` |
| Scheduled malicious / incorrect upgrade | Cancel timelock operation before execution |
| Storage-layout incompatibility found | Do not execute upgrade; fix implementation and rerun layout/tests |

## Health check

Run against a deployed vault:

```bash
OPERATIONAL_VAULT=0x... \
forge script script/OperationalHealthCheck.s.sol \
  --rpc-url "$RPC_URL"
```

The script exits with an error when it detects:

- insolvency;
- stale sequencer heartbeat;
- any non-Active mode.

Those failures are intended monitoring signals.

## Containment procedure

1. Record the current block, mode, token balance, liabilities, and last sequencer heartbeat.
2. Determine whether user exits are safe.
3. If accounting is solvent but the sequencer/settlement path is suspect, enter `ExitOnly`.
4. If backing is below liabilities or transfers themselves may be unsafe, enter `Halted`.
5. Do not attempt an automatic recovery.
6. Preserve logs, transaction hashes, affected accounts, and the exact implementation address.
7. Reconcile actual token assets against internal claims before proposing recovery.

## Recovery procedure

Recovery requires all of the following on-chain:

```text
recovery delay elapsed
AND
assets >= liabilities
AND
sequencer heartbeat is fresh
```

Operationally, also require:

- root cause identified;
- exploit path closed;
- pending upgrade reviewed if relevant;
- affected balances reconciled;
- monitoring restored;
- recovery transaction independently reviewed.

The owner schedules recovery first. Execution is intentionally separate and delayed.

## Deployment helper

The lab includes:

```text
script/DeployOperationalSafetyVault.s.sol
```

Required environment variables:

```text
DEPLOYER_PRIVATE_KEY
SETTLEMENT_TOKEN
VAULT_OWNER
SEQUENCER
GUARDIAN
MONITOR
INACTIVITY_THRESHOLD_SECONDS
RECOVERY_DELAY_SECONDS
```

Example:

```bash
forge script script/DeployOperationalSafetyVault.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Never commit private keys or production credentials.

## Trust boundaries

- The monitor can stop new risk but cannot fully halt the vault.
- The guardian can halt the vault.
- The sequencer can update claims only while Active and cannot create liabilities beyond backing.
- The owner controls recovery; in a production design this role should sit behind stronger governance such as multisig/timelock controls.
- Permissionless inactivity and insolvency triggers reduce dependence on privileged responders.

## Evidence in tests

Deterministic tests cover incident transitions and recovery preconditions.

The stateful invariant suite randomizes normal operations and emergency transitions while checking:

```text
assets >= liabilities

sum(user claims) == liabilities

degraded mode never increases liabilities

Halted mode freezes financial state

mode never de-escalates without recovery
```
