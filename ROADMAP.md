# Roadmap: Veilid 0.5.7 Upgrade & Codebase Strengthening

Long-running tracker for upgrading the Veilid fork from upstream v0.5.3 to **v0.5.7** and
modernizing the market codebase. Updated every working session; each phase lands as its own
commit set with green build/tests before the next begins.

**End goal:** a codebase strong enough to publish from. Candidate routes (pick 1–2, not ranked):
**(A)** patches upstream to core Veilid devs · **(B)** Veilid community release (playground/ipspoof)
· **(C)** general-public write-up · **(D)** MPC research community publication · **(E)** P2P
research community publication. See [Publication notes](#publication-notes).

## Guiding principles

- **Idiomatic Veilid**: prefer the newest first-class APIs (0.5.4–0.5.7) over patterns inherited
  from 0.5.2/0.5.3-era limitations. When touching a subsystem, check whether a modern API covers
  what we hand-rolled — migrate deliberately, one change per commit, measured against E2E.
- **Evidence-based change**: workarounds are removed only when E2E (3/3, equal-or-better timing)
  proves them unnecessary. Devnet failures are code bugs, never "flakiness".
- **Pinned toolchain**: MP-SPDZ builds against the **vendored Boost 1.91.0**, never system/PATH
  Boost. Never "fix" an MP-SPDZ build by pointing it at system boost.
- **Standing constraints**: MPC traffic only via Veilid private routes; no
  `SafetySelection::Unsafe`; no `footgun-nodeid-target`; `app_call` over `app_message`;
  E2E sequential (`--test-threads=1`); one active private route per node.
- **Git hygiene**: push submodules (veilid, dissertationapp) before bumping parent pointers.
  Logical, semantic commits.

## Baseline (Phase 0)

| Item | Value |
|---|---|
| Parent repo | `bcbda37` |
| dissertationapp | `2f56b32` (master) |
| veilid fork | `583edabd` (main, = upstream v0.5.3 merge + local patches) |
| MP-SPDZ | `14a5d571` (pinned, vendored Boost 1.91.0) |
| Rust toolchain | 1.95.0 (0.5.7 MSRV: 1.89 ✓) |
| clippy/fmt | clean at `cb88483` (repaired for clippy 1.95: test exemptions + ~17 lint fixes) |
| unit/integration tests | 224 passed, 0 failed |
| E2E happy path | **116.2s** (2026-07-19, playground devnet, was 169s in Mar) |
| E2E concurrent | **207.8s** (was 284s) |
| E2E sequential | **263.4s** (was 380s) |

## Phases

### Phase 0 — Preflight, baseline, this doc
- [x] Commit uncommitted work as logical units (app: 2 commits; veilid fork: 2 commits)
- [x] Repoint stale local `master` in dissertationapp onto mainline (pre-rewrite pointer, no merge-base with origin/master)
- [x] Create ROADMAP.md
- [x] Record clippy/fmt/test baseline (market crate) — required repair: clippy 1.95 broke the old
  baseline (test-code unwrap exemption removed + stricter lints); fixed in `cb88483`, including
  a footgun fix (loser-key IPC errors now fail tests loudly instead of reading as "no key")
- [x] Record E2E baseline timings: 3/3 PASS — seq 263.4s / conc 207.8s / happy 116.2s
- [x] Commit parent pointer bumps + ROADMAP.md

### Phase 1 — Fork upgrade: merge upstream v0.5.7
- [x] Add upstream remote (`gitlab.com/veilid/veilid`), fetch tag `v0.5.7` (= `f5cdcca3`)
- [x] Merge dry-run (`git merge-tree`): only **2 conflicts** — `Cargo.lock` (regenerate) and
  `bucket_entry.rs` modify/delete (upstream split it into `bucket_entry/` module).
  Everything else auto-merges, including ipspoof/playground/BOOT-v0/route-cache patches.
- [x] Merged as `19d2c0f7` (2026-07-19). Conflicts as predicted: Cargo.lock regenerated;
  `bucket_entry.rs` deletion accepted (ping-span patch dropped with it).
- [x] Per-patch disposition:
  - [x] `a59bb1b3` recursion_limit CI fix → dropped (superseded upstream 0.5.4)
  - [x] `f2d3b461` route-cache panic→graceful → kept (auto-merged), re-evaluate in 5e
  - [x] `d68c16b8` BOOT v0 self-PeerInfo → kept (auto-merged); with/without supersession test
    still pending → moved to Phase 6 track A prep
  - [x] `07587551` devnet ping span → dropped (mechanism removed upstream). Equivalent knob if
    devnet convergence regresses: `UNRELIABLE_ANSWER_SPAN` (60s) in `bucket_entry/state_reason.rs:30`
  - [x] `ecb1ade8` playground limits → superseded; `set_config` calls removed in `fb8380f1`
  - [x] `ipspoof/` + `playground/` crates → clean auto-merge
- [x] Verified: fork workspace `cargo check` green; `cargo test -p veilid-core --lib` **25/25 pass**
  (incl. 0.5.7 HPKE known-answer tests + attachment manager); market compiled immediately after

### Phase 2 — Playground/devnet repair
- [x] Investigated (pre-merge, via v0.5.7 source): attachment limits are no longer config at all —
  0.5.7 computes attachment level adaptively (`attachment_manager/attachment_level_calculator.rs`,
  `SATURATION_TARGET_RELIABLE_NODES = 32`, latency-penalty tiers). The old high-limit hack is
  obsolete for 20-node devnets (all peers fit under saturation target). `doc/config/sample.config`
  upstream still lists `limit_*` — stale docs (candidate upstream docs patch, track A).
  veilid-server warns-and-ignores unknown/moved `--set-config` keys (settings.rs:1198) — playground
  won't hard-fail, but the calls must go.
- [x] Removed `limit_*` `set_config` calls from playground (`fb8380f1`); binaries rebuilt at 0.5.7
- [x] 20-node devnet → all attach + bootstrap converges (2026-07-20, after Phase 2b patches;
  E2E setup gate: 20/20 reachable in 5.1s); escalate 100/254 only if needed for benchmarks.
- [ ] If large-N tuning is ever needed: `core.internal.*` paths exist, honored only when
  veilid-server is built with `footgun-settings` (→ `veilid-core/footgun-config`); devnet-only, never production
- [x] Keep `detect_address_changes=false` (verified in 0.5.7 node logs: "Manually-disabled
  detection of PublicInternet address changes")
- [x] Validate `--set-config` parser accepts our syntax (empirical: all keys applied at 0.5.7;
  note removed/moved keys now hard-fail rather than warn — see Phase 2b min_peer_count)
- [x] Re-validate ipspoof LD_PRELOAD hooks vs 0.5.4 "dynamic source binding" (empirical: 20-node
  mesh forms over 1.2.3.x, full E2E suite passes)
- [x] Verify: `make demo` completes an auction (2026-07-20: 3-node auto-auction, MPC +
  commitment verification + decryption key delivered to winning bidder; first key transfer
  timed out at 20s, reveal-triggered resend delivered — designed retry path)

### Phase 3 — Market compile fix
- [x] Done in `00bb773` (folded into Phase 1 gate — market must compile post-merge). Actual
  breakage beyond predictions: `VeilidConfigRPC.timeout_ms`, `VeilidConfigDHT` timeouts,
  `VeilidConfigTCP/WS.max_connections`, `VeilidConfigUDP.socket_pool_size` all moved internal
  (dropped — public block collapsed to `VeilidConfigNetwork::default()`); ed25519-dalek
  `rand_core` feature no longer unified in transitively (now explicit in Cargo.toml);
  `RouteBlob` newly `#[must_use]` (one intentional drop annotated).
  `Bare*`/`AppCall`/`RouteChange`/DHT signatures: unchanged, compiled clean.
- [x] Dead plumbing removed: `limit_over_attached` + `rpc_timeout_ms` chains
  (config.rs, node.rs, e2e smoke.rs)
- [x] **Watch-item for Phase 4**: rpc timeout back to 10s default (was 5s tuned for faster
  dead-route detection in MPC tunnel) — check dead-route retry behavior in timings
- [x] Verified: clippy `-D warnings` 0 errors, fmt clean, 224/224 tests

### Phase 2b — 0.5.7 devnet genesis deadlock (found 2026-07-19/20, root-caused via strace + debug logs)
First 0.5.7 E2E run: 3/3 FAIL, uniform ~97s — "Devnet not reachable within 90 seconds".
A fresh isolated network cannot form at 0.5.7. **Four interlocking chicken-and-egg gates**
(each verified empirically; upstream design assumes an established public network exists):
1. **Static dial info requires live peers to confirm**: `confirm_dial_info.rs` gates publication
   on ≥5 live connectivity-capable peers (`EXTERNAL_INFO_VALIDATIONS`) even for fully-static
   config, and empty discovery (all-static) returns failure. `network_state.rs` even documents
   the intended static bypass — never implemented. → **Fork patch 1** (`b979a4f9`): fully-static
   nodes confirm without live peers; static-only skips discovery, derives address types statically.
2. **BOOT v0 returns `[]` before publication**: verified with strace — request arrives, reply is
   `[]` because `get_published_peer_info` is None on a fresh bootstrap. → **Fork patch 2**
   (`fac1a4d8`, extends d68c16b8): fall back to current *unpublished* PeerInfo when it has
   confirmed dial info.
3. **Relay requirements unsatisfiable in devnet**: `relay_requirements.rs` demands relay coverage
   for ALL transports (WS/WSS/IPv6 included). A UDP/TCP/IPv4-only devnet can never satisfy this
   → every node stuck `inbound=NeedsRelays` → publish never happens even after bootstrap works
   (verified: bootstrap succeeded in ~5ms via patches 1+2, but mesh never grew). → **Fork patch 3**
   (`1c3655b4`): scope requirement set to the node's `address_types` × `outbound_protocols`; plus
   devnet config sets `ws.connect=false` (playground `f68bec29` + market node.rs `7929a01`) so the
   scope equals static coverage.
4. **Translated addresses demand relays even for Direct-class dial info**: ipspoof's 1.2.3.x
   addresses aren't interface addresses, so 0.5.7 classifies them as NAT-translated and demands a
   relay for the address type regardless of dial info class — still `NeedsRelays` after patch 3.
   → **Fork patch 4** (`b6c3fb2f`): Direct class (confirmed/static full inbound reachability)
   exempt from the translation-driven relay requirement.
- Also fixed: `--set-config core.network.dht.min_peer_count` hard-fails at 0.5.7 (moved to
  core.internal) — removed from playground (it killed all nodes at spawn; the "97s" root cause).
- Also: playground no longer strips connectivity capabilities from the bootstrap node
  (0.5.7 gates on them). Both in `f68bec29`.
- **Verified 2026-07-20**: fresh 20-node devnet with all four patches — every node bootstraps
  exactly once (7–138ms, no retry cycling); E2E setup gate reports **20/20 reachable in 5.1s**
  (was: timeout at 90s).
- **Track A gold**: the genesis deadlock + four patches is a coherent upstream contribution
  ("support fully-static/isolated network bootstrap"), with a repro harness (playground).

### Phase 4 — E2E revalidation + timing comparison
- [x] 3 E2E tests sequentially on repaired devnet (2026-07-20): **3/3 PASS**, suite 573.3s

  | Test | 0.5.3 baseline | 0.5.7 | Δ |
  |---|---|---|---|
  | sequential | 263.4s | **215.5s** | −18.2% |
  | concurrent | 207.8s | **210.3s** | +1.2% (flat) |
  | happy path | 116.2s | **142.3s** | +22.5% (regression) |
  | devnet setup gate | ~90s timeout-prone | **5.1s** | genesis patches |

- [x] Expectation partially met: sequential (heaviest MPC reuse of routes) benefits most from
  0.5.4–0.5.7 route work; happy path regressed — single-auction cold-route cost apparently
  moved, not removed. Candidate causes to profile in Phase 5g: rpc timeout back at 10s default
  (was 5s tuned — the Phase 3 watch-item), relay-compiler startup work, route optimizer warmup.
- [x] No ConnectionManager deadlock symptoms under connect storms
- [x] Gate: 3/3 green → Phase 5 unlocked

### Phase 5 — Incremental strengthening (each sub-phase = own commit, idiomatic-Veilid pass)
- [ ] **(a)** `VeilidConfigDHT.max_concurrent_operations` — set/tune (node.rs:173,223), measure
- [ ] **(b)** `flush_dht_record` after critical writes (bid_storage, bid_announcement, registry);
  verify E2E timing doesn't regress
- [ ] **(c)** **HPKE design spike (investigate only — no production code without sign-off)**:
  design note here; prototype key-derivation round-trip (VLD0 signing identity →
  `encapsulation_key_from_signing_key`/`decapsulation_key_from_signing_secret` → seal/open)
  in a throwaway test
- [ ] **(d)** Richer `VeilidUpdate::Attachment` — network-size estimates in UI status/logs
- [ ] **(e)** Route-workaround simplification, evidence-based per candidate (remove on branch,
  full E2E 3/3, equal-or-better timing): post-barrier refresh · reactive refresh ·
  fresh-devnet-per-test · fork patch `f2d3b461`
- [ ] **(f)** Optional: DHT transactions for `read_modify_write_subkey` — only if (a)–(e) reveal
  a concurrency gap (NOTES.md:322 wished for native CAS; transactions may answer it)
- [ ] **(g)** E2E speedup pass (user-requested): profile where wall time goes at 0.5.7
  (devnet startup, announcement sleeps, MPC polling cadence, barrier waits, MASCOT round
  latency) and tune measured-worst-first. Caution from Feb 2026 optimization round:
  aggressive sleep reductions previously caused 849 route errors — change one knob per run.

### Phase 6 — Publication track (gated on Phases 1–4 green; user picks 1–2 of A–E)
- [ ] Accumulate material per route in [Publication notes](#publication-notes)
- [ ] A: MR candidates = surviving fork patches (`d68c16b8`, `f2d3b461`) with repro evidence
- [ ] B: playground + ipspoof as standalone "local Veilid devnet without Docker" tool; README/announcement scope
- [ ] C: build-a-private-auction-on-Veilid narrative
- [ ] D: MPC-over-anonymous-routes transport characterization (Phase 4 before/after data is the kernel)
- [ ] E: private-route behavior under sustained load (route death, refresh strategies, 5e measurements)

### Phase 7 — Docs & memory
- [ ] Update `Dissertation/NOTES.md` ("Current State (Veilid 0.5.2)" §, CAS discussion)
- [ ] Update project memory: SHAs, timing deltas, patch dispositions, new constraints

## Publication notes

_Measurements and observations accumulate here per route until 1–2 routes are chosen._

## Session log

- **2026-07-19** — Plan researched & approved. Verified: fork = v0.5.3 + patches (stale fork tags
  make `git describe` misleading); v0.5.7 breaking surface identified (`limit_*` config fields
  gone; `Sequencing`/`Attachment` usage unaffected); HPKE/`flush_dht_record`/
  `max_concurrent_operations` adoption candidates confirmed present. Phase 0 started: preflight
  commits landed (app 718d62e+2f56b32, fork 8245b546+583edabd), stale app `master` repointed,
  ROADMAP.md created.
- **2026-07-19/20** — Phases 1–4 landed. Merged v0.5.7 (`19d2c0f7`), market compiles at 0.5.7
  (`00bb773`), clippy-1.95 baseline repair (`cb88483`). Root-caused + fixed the **genesis
  deadlock** (Phase 2b): four fork patches `b979a4f9`/`fac1a4d8`/`1c3655b4`/`b6c3fb2f` +
  playground `f68bec29` + market `7929a01`. Devnet: 20/20 reachable in 5.1s. E2E **3/3 PASS**
  (573.3s suite): sequential −18%, concurrent flat, happy path +22% (profiling target for 5g).
  Fork pushed (`f68bec29` verified on remote).
