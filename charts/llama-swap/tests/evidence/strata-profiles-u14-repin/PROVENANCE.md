# strata-profile fixtures — U14 re-pin era (primary era 3)

Captured 2026-11-01 from the default chart `strata-profile` ConfigMap DATA
(render_on path: `helm template gpu-ai-llama-swap charts/llama-swap --set
domain=test.example.com` + the seven strata flags), branch
`bug-strata-claim-venv-heal`, helm v3.16.4+g7877b45 — same binary as the era-1,
era-2 and strix captures, so renders stay directly comparable.

- File: `strata-iq3_s.json` — sha256
  `f1a8d6c869e5936e3fb386f9b3e078e34e76116672d11fe3606afda175aed1c6`
- Determinism: double-capture diffed clean; encoding
  (`json.dumps(indent=2, sort_keys=True) + "\n"`) reproduced the era-2 file
  byte-for-byte before this one was written.

## Era chain (primary)

| era | captured | sha256 | sanctioned delta |
| --- | --- | --- | --- |
| 1 | 2026-10-29 @ `4f7126689` — `../strata-profiles-pre-cf86/` | `a8de596cd95bcfd38e7e9c87acf4343c5758800a7ae9a8174202b8d3b8a4ce62` | original capture |
| 2 | 2026-11-01 U13/T0-T3 — `../strata-profiles-t03-repin/` | `ce1f66a8fe1d357bd1c5ed0d37d38dd779bc5c283372b622facc35f939d4ceb3` | `--prefill auto` → `auto:32768` |
| 3 | 2026-11-01 U14 (this directory) | `f1a8d6c869e5936e3fb386f9b3e078e34e76116672d11fe3606afda175aed1c6` | `--memory-limit-mib 92160` → `110592` |

Chain law: `test_strata_strix.py::test_primary_fixture_era_chain_is_one_owner_ruled_flag_per_step`
asserts each adjacent step is args-only, membership-identical and exactly ONE
flag value, with the conversation-cache/KV/max-context terms never riding an
unrelated step.

## Why era 3: the cap had never covered this rung's own terms

`--memory-limit-mib 92160` = 90.00 GiB, while the primary's terms are
46.84 GiB page-locked arena + 32 GiB conversation cache + ~13 GiB worst-case
4-slot KV ≈ **91.84 GiB**. The comment beside the value claimed the opposite
("90 GiB = arena ~50 + conversation cache 32 + KV ~13" — that sums to 95), and
the engine reported the consequence at the first boot after U13:

```
conversation cache: skip parking (physical RAM admission;
  need 1960 MiB plus 2560 MiB floor, 3259 MiB available, source flag; …)
```

`source flag` names `--memory-limit-mib` as the budget being exhausted — i.e.
parking was refused *inside the engine's own declaration* while the node's
`MemAvailable` measured 40 GiB. 110592 MiB (107.25 GiB) covers the term-sum
with ~15 GiB spare and keeps the same reserve style the q4 rung already rides.

## Why the cgroup moved to 116Gi with it (container level, not in this file)

Measured on the VM via Grafana/prometheus, 2026-11-01: node allocatable
125.08 GiB (kubelet reserving effectively nothing, so the gap IS the OS
margin); kube-system containers peak 0.31 GiB over 7 d; the node's own floor
with every non-strata workload running measured ~7.3 GiB total — so OS + k3s +
containerd + kernel ≈ 2–3 GiB against a 9.1 GiB gap at 116Gi. Observed worst
inside the old 108Gi: a 99.2 GiB container working set during the 288 GB
provisioning boot, node `MemAvailable` bottoming at 17.3 GiB, with 54.6 GiB of
that footprint reclaimable page cache — the kernel takes cache before victims.
Standing caveats, recorded in the values comment: swap is 2.0 GiB (1.7 free),
so this cgroup is the only containment; `requests` stay 64Gi, so the
scheduler can still pack a neighbour here and the ttl/alternation discipline
is what actually keeps the big llama.cpp rungs off a warm arena.

## Verified BEFORE re-capture

- top-level changed keys: exactly `["args"]`
- args membership: unchanged (no flag added or dropped)
- flags changed within `args`: exactly `["--memory-limit-mib"]`, 92160 → 110592
- untouched: `--conversation-cache-mib 32768`, `--conversation-cache-slots 16`,
  `--kv-resident 32768`, `--max-context 262144`, `--prefill auto:32768` (era 2's
  ruling, preserved), all pack/native/PLE/profile paths
- `env` at the profile layer: still `{}` (C-A keyless; T0's
  `STRATA_REQUEST_LINES=1` rides the llama-swap **model** env, outside this
  capture)
- declared cap 110592 MiB ≤ the 116Gi cgroup: yes (#1601 pairing)

q4 (103680) and orca (92160) declarations did NOT move with the cgroup — caps
are per-rung, and neither rung was bumping against the ceiling.
