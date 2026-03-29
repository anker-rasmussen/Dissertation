# Privacy-Preserving Sealed-Bid Auctions over Veilid with MASCOT MPC

BSc Computer Science Dissertation — City, University of London (2025/26)

A decentralised sealed-bid auction marketplace where bids are committed via SHA-256, resolved by multi-party computation (MP-SPDZ MASCOT protocol), and all MPC traffic is tunnelled over Veilid private routes. Only the seller learns the winner; all other parties learn only whether they won or lost.

## Repository Structure

| Path | Description |
|------|-------------|
| `Repos/dissertationapp/market/` | Main Rust crate — P2P auction marketplace |
| `Repos/MP-SPDZ/` | MP-SPDZ framework (submodule, BSD-3-Clause) |
| `Repos/veilid/` | Veilid P2P framework (submodule, MPL-2.0) |

## Quick Start

```bash
git clone --recurse-submodules https://github.com/anker-rasmussen/Dissertation
cd Dissertation
make install-deps    # System dependencies (tested on Arch Linux)
make run             # Build everything, start devnet, launch 3 interactive nodes
make demo            # Same as above, but with automated auction demo
```

> **Note:** Tested on Arch Linux and macOS. The Makefile includes a Debian dependency list — check `make install-deps` and adjust if needed.

## License

MPL-2.0
