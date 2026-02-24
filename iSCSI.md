# iSCSI Configuration for Storage Migration (TrueNAS + Proxmox)

This document describes a recurring issue when migrating VM disks **to** a `truenas:` storage (TrueNAS 25.10 API) from other storages (e.g. `zfs:`), and how to fix it by configuring iSCSI **Authorized Networks** on the destination TrueNAS.

---

## Problem Summary

Storage migration to a `truenas:`-type storage fails with:

```text
TASK ERROR: storage migration failed: mirroring error: VM 158 qmp command 'drive-mirror' failed - iSCSI: Failed to connect to LUN : Failed to log in to target. Status: Target not found(515)
```

The Proxmox/TrueNAS plugin **does** create the new zvol and LUN on the destination TrueNAS successfully. The failure happens in the next step: when the Proxmox host (the iSCSI initiator) tries to **log in** to the destination iSCSI target to perform the drive-mirror. The target rejects the login or does not advertise itself to that initiator, so the initiator reports "Target not found (515)".

---

## Root Cause: iSCSI Authorized Networks

On the **destination** TrueNAS (the one used as `truenas:` storage, e.g. nas02-1-cpt01-s):

- The iSCSI **target** (e.g. `iqn.2005-10.org.freenas.ctl:proxmox`) has an **iSCSI Authorized Networks** setting.
- If that list includes **only** certain subnets (e.g. `102.216.79.0/24`), then **only** initiators from those networks are allowed to discover and log in to the target.
- Your Proxmox nodes may be on a **different** subnet (e.g. `10.0.0.0/24`) and use the TrueNAS host’s IP on that subnet as the **portal** (e.g. `10.0.0.7`).
- When a node on `10.0.0.x` tries to connect to the target at `10.0.0.7`, TrueNAS does not authorize that network, so:
  - Discovery from the node: `iscsiadm -m discovery -t st -p 10.0.0.7` → **No portals found**
  - Login fails → **Target not found (515)** during migration.

So the failure is **not** a bug in the Proxmox TrueNAS plugin; it is due to the destination target’s **Authorized Networks** not including the subnet of the Proxmox node performing the migration.

---

## Solution: Add the Proxmox Network to Authorized Networks

On the **destination** TrueNAS (the host that backs your `truenas:` storage):

1. Open **Shares → iSCSI → Targets**.
2. Select the target used by that storage (e.g. **proxmox** for `nas02-1-cpt01-s`).
3. Click **Edit**.
4. In **iSCSI Authorized Networks**, add the subnet where your Proxmox nodes live that will connect to this target (e.g. **`10.0.0.0/24`**).
5. Save and apply.

After this, initiators from that subnet can discover and log in to the target. Storage migration to this `truenas:` storage should then succeed (assuming portal, LUN mapping, and initiator groups are already correct).

---

## Verifying From a Proxmox Node

From a Proxmox node that will perform the migration (e.g. hvX), run:

```bash
# Discovery (should list the target)
iscsiadm -m discovery -t st -p 10.0.0.7
# Expected (example): 10.0.0.7:3260,1 iqn.2005-10.org.freenas.ctl:proxmox

# Optional: manual login test
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox -p 10.0.0.7 --login

# Check sessions
iscsiadm -m session
```

If discovery returns "No portals found", the target is still not reachable from that node’s network—double-check Authorized Networks and that the portal is listening on the IP the node uses (e.g. 10.0.0.7).

---

## Clarification: Middlewared “Target is in use” Warning

When a migration fails, the plugin cleans up the newly created LUN and zvol on the destination. In `/var/log/middlewared.log` you may see:

```text
(WARNING) middlewared.do_delete():167 - Associated target iqn.2005-10.org.freenas.ctl:proxmox is in use.
```

This means: “You are deleting something (e.g. an extent) that belongs to a target that still has active sessions.” It is a **warning** from the cleanup step, **not** the cause of the migration failure. The actual failure is the iSCSI login (Target not found 515) **before** cleanup.

---

## Two Targets on the Same TrueNAS

It is normal to have multiple iSCSI targets on one TrueNAS, for example:

- **proxmox** – used by the `truenas:` storage (e.g. nas02-1-cpt01-s), pool `tank/proxmox`, target IQN `iqn.2005-10.org.freenas.ctl:proxmox`.
- **target** – used by older or other setups (e.g. `zfs:` with iscsiprovider truenas), often with a different portal/target IQN.

Ensure **Authorized Networks** (and Portal bindings) are correct for **each** target that Proxmox nodes need to use. For migrations to a given `truenas:` storage, the relevant target is the one referenced in that storage’s `portal` and `target` in `/etc/pve/storage.cfg`.

---

## Quick Reference

| Symptom | Cause | Action |
|--------|--------|--------|
| Migration to `truenas:` fails with "Target not found (515)" | Initiator’s network not in target’s Authorized Networks | Add initiator’s subnet (e.g. 10.0.0.0/24) to iSCSI Authorized Networks for that target on the destination TrueNAS. |
| `iscsiadm -m discovery -t st -p <portal>` → No portals found | Same as above, or portal not bound to that IP | Fix Authorized Networks; check Portals so the target is reachable on the IP the node uses. |
| middlewared "Associated target ... is in use" | Cleanup after failed migration | Informational; fix the login/Authorized Networks so migration succeeds. |

Adding the Proxmox node’s network (e.g. **10.0.0.0/24**) to the destination target’s **iSCSI Authorized Networks** resolves the "Target not found (515)" migration error.
