# Presentation Cheat-Sheet — SMPC Auction over Veilid

Everything is driven by the Makefile at the repo root (`~/Repos/Dissertation/Makefile`).
`make help` lists all targets.

Node map (both `make run` and `make demo`):
- Node 20 → port 5170, IP 1.2.3.21 — Bidder 1
- Node 21 → port 5171, IP 1.2.3.22 — Bidder 2
- Node 22 → port 5172, IP 1.2.3.23 — Auctioneer / Seller

`run` vs `demo`:
- **`make demo`** — auto-auction: seller auto-creates a listing, bidders auto-discover + auto-bid, MASCOT runs at deadline. Bidder UIs auto-open the listing. Hands-off.
- **`make run`** — 3 interactive GUI nodes, **no** auto-pull. You drive it: paste the listing key, type a bid, submit. (Auto-select of the first listing is now demo-only — fixed in `components.rs`.)

---

## 0. Pre-flight (run BEFORE the talk)

```bash
cd ~/Repos/Dissertation

make build-release build-playground build-mpspdz   # build everything, nothing compiles on stage
make test                                            # ~227 mock tests, ~1s — confidence shot
ls Repos/MP-SPDZ/mascot-party.x                      # MASCOT binary present
```
(`make demo` / `make run` also build their deps first, but doing it ahead avoids a long silent pause on stage.)

---

## 1. The live demo — auto-auction

```bash
cd ~/Repos/Dissertation
make demo 2>&1 | tee /tmp/demo.log
```
This starts the 20-node playground devnet (no Docker) and the 3 market nodes, all in one
terminal with `[Node 20]` / `[Node 21]` / `[Node 22]` prefixes. `tee` lets you grep highlights live.

For the **interactive / manual** story instead:
```bash
make run 2>&1 | tee /tmp/run.log
```

---

## 2. Loglines to narrate the demo

`make demo` sets `RUST_LOG=market=info,veilid_core=warn`, so you see the **market** crate's
`info!` markers (clean signal, no Veilid noise). Watch the story unfold in a second pane:

```bash
tail -F /tmp/demo.log \
  | grep -E "DEMO|listing|bid record|All parties ready|MASCOT|Open sent to Party|winner|decryption key|Commitment verified|No sale"
```

| Phase | Grep for | Says |
|---|---|---|
| Listing published | `=== DEMO: Listing published! Key:` | seller put listing on DHT |
| Bid placed | `We bid on this listing, our bid record` | bidder committed `SHA256(bid‖nonce)` |
| Bid discovery | `Discovering bids from DHT bid registry` / `Found N bidders` | registry read |
| Routes exchanged | `Recreated own MPC route` / `Post-barrier DHT poll: picked up N` | per-auction private routes via DHT subkey 1 |
| Readiness barrier | `all peers confirmed SynAckComplete - launching MPC` | every party ready |
| MPC running | `Starting MPC TunnelProxy for Party N` / `Open sent to Party N` | MASCOT tunnelled over Veilid |
| Result | `Parsed winner party ID` / `Parsed winning bid` | only seller (party 0) learns these |
| Reveal / verify | `I won - waiting for seller's challenge` → `Commitment verified for winner` | winner proves bid |
| Payout | `I am the winner! Received decryption key` | AES-256-GCM key released |
| No winner | `No bidder exceeded the reserve price - no sale` | reserve not met |

Privacy line to say out loud: only **party 0 (the seller)** ever sees the winner ID and winning
bid; every other party learns only `won: 0/1`.

---

## 3. Key code to open / point at

| Topic | File | What to show |
|---|---|---|
| Two coordination layers | `src/veilid/auction_coordinator/mod.rs` | real Veilid coordinator (~1100 lines) |
| Testable core | `src/veilid/auction_logic.rs` | `AuctionLogic<D, C>` generic over DHT + clock → why tests run in ~1s |
| MPC orchestration | `src/veilid/mpc_orchestrator.rs` | readiness **barrier**, per-auction route refresh |
| MPC tunnel | `src/veilid/mpc.rs` | `app_call` for confirmed delivery (not `app_message`) — the "no silent footgun" decision |
| Route exchange via DHT | `src/veilid/mpc_routes.rs` | route blob written to bid record **subkey 1**, read as fallback |
| MP-SPDZ spawn | `src/veilid/mpc_execution.rs` | `resolve_protocol()` → defaults to `mascot-party.x` |
| Commitment + verify | `src/veilid/mpc_verification.rs` | challenge → reveal → `Commitment verified` |
| Crypto | `src/crypto/` | SHA256 commitment, AES-256-GCM content encryption |
| Demo driver | `src/demo.rs` | uses the *same* `actions::` fns as the GUI — demo == real path |

Three architectural points worth stating explicitly:
1. **All MPC traffic goes through Veilid private routes** — never direct TCP. Privacy depends on it.
2. **Only 1 active private route per node** in Veilid → MPC sessions are **sequential per node**,
   which drove the DHT-backed route exchange and the deterministic listing-ordering deadlock fix.
3. **app_call over app_message** everywhere point-to-point — fire-and-forget silently drops data
   on stale routes; confirmed delivery surfaces errors instead.

---

## 4. Fallback if the live demo misbehaves

You have a recorded run — play that if a route goes cold on stage; don't debug live.
Backup proof of correctness:
```bash
cd ~/Repos/Dissertation && make test     # mock suite, fast and deterministic
```
Known-good full-auction timings: happy-path ~169s, sequential ~380s, concurrent ~284s. MASCOT
itself is ~9s warm — the rest is Veilid route latency on a cold devnet (good answer to
"why is it slow?").

---

## 5. Teardown

```bash
cd ~/Repos/Dissertation && make clean    # removes build artifacts + node data
# or just Ctrl+C — make run/demo trap EXIT and kill the playground + nodes
```
