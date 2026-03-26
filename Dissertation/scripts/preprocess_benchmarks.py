#!/usr/bin/env python3
"""Preprocess benchmark CSVs into pgfplots-compatible .dat files.

Usage:
    python3 preprocess_benchmarks.py <direct_csv> <veilid_csv> <output_dir>

Example:
    python3 scripts/preprocess_benchmarks.py \
        ../Repos/dissertationapp/market/bench-results/direct_mpc.csv \
        ../Repos/dissertationapp/market/bench-results/veilid_auction.csv \
        Figures/data/
"""
import csv
import os
import sys
from collections import defaultdict
from math import sqrt


def median(vals):
    s = sorted(vals)
    n = len(s)
    if n == 0:
        return 0.0
    if n % 2 == 1:
        return s[n // 2]
    return (s[n // 2 - 1] + s[n // 2]) / 2.0


def mean(vals):
    return sum(vals) / len(vals) if vals else 0.0


def stddev(vals):
    if len(vals) < 2:
        return 0.0
    m = mean(vals)
    return sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))


def write_dat(path, header, rows):
    with open(path, "w") as f:
        f.write("  ".join(header) + "\n")
        for row in rows:
            f.write("  ".join(str(v) for v in row) + "\n")
    print(f"  wrote {path} ({len(rows)} rows)")


def process_direct(csv_path, out_dir):
    """Process direct_mpc.csv into per-protocol .dat files."""
    data = defaultdict(lambda: defaultdict(list))

    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            proto = row["protocol"]
            parties = int(row["num_parties"])
            wall = float(row["wall_clock_secs"])
            mpc = float(row["mpc_time_secs"])
            data_mb = float(row["data_sent_mb"])
            rounds = int(row["rounds"])
            global_mb = float(row["global_data_mb"])
            data[proto][parties].append(
                (wall, mpc, data_mb, rounds, global_mb)
            )

    for proto, party_data in data.items():
        header = [
            "parties",
            "wall_median",
            "wall_stddev",
            "mpc_median",
            "mpc_stddev",
            "data_mb",
            "rounds",
            "global_mb",
        ]
        rows = []
        for parties in sorted(party_data.keys()):
            vals = party_data[parties]
            walls = [v[0] for v in vals]
            mpcs = [v[1] for v in vals]
            rows.append([
                parties,
                f"{median(walls):.4f}",
                f"{stddev(walls):.4f}",
                f"{median(mpcs):.4f}",
                f"{stddev(mpcs):.4f}",
                f"{vals[0][2]:.3f}",
                vals[0][3],
                f"{vals[0][4]:.3f}",
            ])
        write_dat(os.path.join(out_dir, f"direct_{proto}.dat"), header, rows)


def process_veilid(csv_path, out_dir):
    """Process veilid_auction.csv into per-protocol-per-devnet .dat files."""
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            proto = row["protocol"]
            devnet = int(row["devnet_nodes"])
            parties = int(row["num_parties"])
            total = float(row["total_secs"])
            route = float(row["route_exchange_secs"])
            mpc_wall = float(row["mpc_wall_secs"])
            tunnel_sent = int(row["tunnel_bytes_sent"])
            tunnel_recv = int(row["tunnel_bytes_recv"])
            data[proto][devnet][parties].append(
                (total, route, mpc_wall, tunnel_sent, tunnel_recv)
            )

    # Per-protocol, per-devnet summary (successful runs only)
    for proto, devnet_data in data.items():
        for devnet, party_data in devnet_data.items():
            header = [
                "parties",
                "n_total",
                "n_success",
                "success_rate",
                "total_median",
                "total_stddev",
                "route_median",
                "route_stddev",
                "mpc_median",
                "mpc_stddev",
                "tunnel_sent_kb",
                "tunnel_recv_kb",
            ]
            rows = []
            for parties in sorted(party_data.keys()):
                vals = party_data[parties]
                n_total = len(vals)
                successful = [v for v in vals if v[2] > 0]
                n_success = len(successful)
                rate = n_success / n_total if n_total > 0 else 0

                if successful:
                    totals = [v[0] for v in successful]
                    routes = [v[1] for v in successful]
                    mpcs = [v[2] for v in successful]
                    tsent = [v[3] for v in successful]
                    trecv = [v[4] for v in successful]
                    rows.append([
                        parties,
                        n_total,
                        n_success,
                        f"{rate:.2f}",
                        f"{median(totals):.2f}",
                        f"{stddev(totals):.2f}",
                        f"{median(routes):.2f}",
                        f"{stddev(routes):.2f}",
                        f"{median(mpcs):.2f}",
                        f"{stddev(mpcs):.2f}",
                        f"{median(tsent) / 1024:.1f}",
                        f"{median(trecv) / 1024:.1f}",
                    ])
                else:
                    rows.append([
                        parties, n_total, 0, "0.00",
                        "0.00", "0.00", "0.00", "0.00",
                        "0.00", "0.00", "0.0", "0.0",
                    ])

            write_dat(
                os.path.join(out_dir, f"veilid_{proto}_{devnet}.dat"),
                header, rows,
            )

    # Success rate files (all devnets for one protocol)
    for proto, devnet_data in data.items():
        header = ["parties", "rate_40", "rate_60", "rate_80"]
        all_parties = sorted(
            set(p for dd in devnet_data.values() for p in dd.keys())
        )
        rows = []
        for parties in all_parties:
            row = [parties]
            for devnet in [40, 60, 80]:
                vals = devnet_data.get(devnet, {}).get(parties, [])
                if vals:
                    n_success = sum(1 for v in vals if v[2] > 0)
                    row.append(f"{n_success / len(vals):.2f}")
                else:
                    row.append("nan")  # missing data
            rows.append(row)
        write_dat(
            os.path.join(out_dir, f"success_{proto}.dat"), header, rows
        )

    # Overhead files: compare Veilid MPC wall time to direct MPC time
    # (generated separately after both CSVs are processed)
    return data


def process_overhead(direct_csv, veilid_data, out_dir):
    """Generate overhead comparison (direct vs Veilid MPC time, 40-node)."""
    # Load direct data
    direct = defaultdict(lambda: defaultdict(list))
    with open(direct_csv) as f:
        reader = csv.DictReader(f)
        for row in reader:
            proto = row["protocol"]
            parties = int(row["num_parties"])
            wall = float(row["wall_clock_secs"])
            direct[proto][parties].append(wall)

    for proto in ["mascot", "shamir"]:
        if proto not in veilid_data or 40 not in veilid_data[proto]:
            continue
        header = [
            "parties",
            "direct_median",
            "veilid_mpc_median",
            "veilid_total_median",
            "overhead_mpc",
            "overhead_total",
        ]
        rows = []
        vd = veilid_data[proto][40]
        for parties in sorted(vd.keys()):
            if parties not in direct[proto]:
                continue
            successful = [v for v in vd[parties] if v[2] > 0]
            if len(successful) < 1:
                continue
            d_med = median(direct[proto][parties])
            v_mpc_med = median([v[2] for v in successful])
            v_total_med = median([v[0] for v in successful])
            overhead_mpc = v_mpc_med / d_med if d_med > 0 else 0
            overhead_total = v_total_med / d_med if d_med > 0 else 0
            rows.append([
                parties,
                f"{d_med:.4f}",
                f"{v_mpc_med:.2f}",
                f"{v_total_med:.2f}",
                f"{overhead_mpc:.1f}",
                f"{overhead_total:.1f}",
            ])
        write_dat(
            os.path.join(out_dir, f"overhead_{proto}.dat"), header, rows
        )


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <direct_csv> <veilid_csv> <output_dir>")
        sys.exit(1)

    direct_csv, veilid_csv, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)

    print("Processing direct MPC data...")
    process_direct(direct_csv, out_dir)

    print("Processing Veilid auction data...")
    veilid_data = process_veilid(veilid_csv, out_dir)

    print("Computing overhead factors...")
    process_overhead(direct_csv, veilid_data, out_dir)

    print("Done.")


if __name__ == "__main__":
    main()
