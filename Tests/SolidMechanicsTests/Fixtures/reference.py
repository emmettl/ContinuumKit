#!/usr/bin/env python3
"""Independent P1 laminate reference. Standard library only; no Edgerton imports.

Closed-form stiffness rotation is checked against tensor transformations;
thickness antiderivatives are checked against per-ply Simpson integration.
Neither path evaluates an application shell or proves its numerical correctness.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import platform
import resource
import time


def mv(a, x):
    return [sum(v * w for v, w in zip(row, x)) for row in a]


def dot(a, b):
    return sum(v * w for v, w in zip(a, b))


def local_q(p):
    e1, e2, g, nu = (p[k] for k in ("E1_Pa", "E2_Pa", "G12_Pa", "nu12"))
    if not all(math.isfinite(v) and v > 0 for v in (e1, e2, g)):
        raise ValueError("positive finite elastic moduli required")
    den = 1 - nu * nu * e2 / e1
    if not math.isfinite(den) or den <= 0:
        raise ValueError("non-positive plane-stress compliance")
    return [[e1 / den, nu * e2 / den, 0],
            [nu * e2 / den, e2 / den, 0], [0, 0, g]]


def rotated_q(q, angle):
    m, n = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    a, b, c, g = q[0][0], q[1][1], q[0][1], q[2][2]
    q11 = a*m**4 + 2*(c+2*g)*m*m*n*n + b*n**4
    q22 = a*n**4 + 2*(c+2*g)*m*m*n*n + b*m**4
    q12 = (a+b-4*g)*m*m*n*n + c*(m**4+n**4)
    q16 = (a-c-2*g)*m**3*n - (b-c-2*g)*m*n**3
    q26 = (a-c-2*g)*m*n**3 - (b-c-2*g)*m**3*n
    q66 = (a+b-2*c-2*g)*m*m*n*n + g*(m**4+n**4)
    return [[q11, q12, q16], [q12, q22, q26], [q16, q26, q66]]


def tensor_response(q, angle, strain):
    """Rotate symmetric strain to grain axes and symmetric stress back to x/y."""
    m, n = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    ex, ey, gamma = strain
    local = [m*m*ex+n*n*ey+m*n*gamma,
             n*n*ex+m*m*ey-m*n*gamma,
             -2*m*n*ex+2*m*n*ey+(m*m-n*n)*gamma]
    s1, s2, t = mv(q, local)
    return [m*m*s1+n*n*s2-2*m*n*t,
            n*n*s1+m*m*s2+2*m*n*t,
            m*n*(s1-s2)+(m*m-n*n)*t], local


def laminate(q, angles, thickness):
    matrices = [[[0.0]*3 for _ in range(3)] for _ in range(3)]
    z = -len(angles)*thickness/2
    for angle in angles:
        top = z + thickness
        qb = rotated_q(q, angle)
        for order, matrix in enumerate(matrices):
            weight = (top**(order+1)-z**(order+1))/(order+1)
            for i in range(3):
                for j in range(3):
                    matrix[i][j] += qb[i][j]*weight
        z = top
    return matrices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path(__file__).with_name("input.json"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    args = parser.parse_args()
    started = time.perf_counter()
    if not args.output.resolve().is_relative_to(Path("/Volumes/StudioData")):
        parser.error("generated outputs must be on StudioData")
    # Fresh directory only: preserve all previous reference/evidence runs.
    if args.output.exists():
        parser.error("output already exists; use a new run directory")
    raw = args.input.read_bytes()
    p = json.loads(raw)
    q = local_q(p)
    for key in ("length_m", "width_m", "ply_thickness_m", "density_kg_m3"):
        if not math.isfinite(p[key]) or p[key] <= 0:
            raise ValueError(f"{key}: positive finite value required")
    if p["increments_per_leg"] <= 0 or not isinstance(p["increments_per_leg"], int):
        raise ValueError("positive integer increments_per_leg required")
    if any(len(angles) != 3 or not all(math.isfinite(v) for v in angles)
           for angles in p["layups_deg"].values()):
        raise ValueError("three finite ply angles required")
    if len(p["curvature_path_per_m"]) < 2 or not all(math.isfinite(v) for v in p["curvature_path_per_m"]):
        raise ValueError("finite curvature path required")
    errors = {}

    def check(name, error, tolerance=1e-12):
        errors[name] = {"error": error, "tolerance": tolerance}
        if not math.isfinite(error) or error > tolerance:
            raise AssertionError(f"{name}: {error} > {tolerance}")

    # Combined strain exercises coupling and engineering/tensor shear conversion.
    for angle in (0, 30, 90):
        for strain in ([1e-4, 0, 0], [0, 1e-4, 0], [0, 0, 1e-4], [1e-4, -2e-5, 3e-5]):
            actual, local = tensor_response(q, angle, strain)
            formula = mv(rotated_q(q, angle), strain)
            key = f"rotation-{angle}-{strain}"
            check(key, max(abs(a-b) for a, b in zip(actual, formula))/max(abs(a) for a in actual))
            eglobal, elocal = dot(strain, actual)/2, dot(local, mv(q, local))/2
            check(key+"-energy", abs(eglobal-elocal)/elocal)

    results, histories = {}, []
    for name, angles in p["layups_deg"].items():
        a, b, d = laminate(q, angles, p["ply_thickness_m"])
        check(name+"-symmetric-B", max(abs(v) for row in b for v in row)/max(v for row in a for v in row)/ (3*p["ply_thickness_m"]))
        # Independent stress-through-thickness integration, Simpson exact for z².
        ds = [[0.0]*3 for _ in range(3)]
        z = -len(angles)*p["ply_thickness_m"]/2
        for angle in angles:
            top = z+p["ply_thickness_m"]
            for j in range(3):
                unit = [float(i == j) for i in range(3)]
                stress, _ = tensor_response(q, angle, unit)
                weight = (top-z)*(z*z+4*((top+z)/2)**2+top*top)/6
                for i in range(3):
                    ds[i][j] += stress[i]*weight
            z = top
        check(name+"-D-integral", max(abs(d[i][j]-ds[i][j]) for i in range(3) for j in range(3))/max(abs(v) for row in d for v in row))
        area = p["length_m"]*p["width_m"]
        sequence = [p["curvature_path_per_m"][0]]
        for lo, hi in zip(p["curvature_path_per_m"], p["curvature_path_per_m"][1:]):
            sequence += [lo+(hi-lo)*i/p["increments_per_leg"] for i in range(1, p["increments_per_leg"]+1)]
        work, previous_k, previous_m = 0.0, 0.0, 0.0
        peak_energy = area*d[0][0]*max(sequence)**2/2
        for step, k in enumerate(sequence):
            mx, my = d[0][0]*k, d[1][0]*k
            energy = area*mx*k/2
            work += area*(previous_m+mx)*(k-previous_k)/2
            check(f"{name}-work-{step}", abs(work-energy)/peak_energy)
            histories.append([name, step, k, mx, my, energy, work])
            previous_k, previous_m = k, mx
        results[name] = {"angles_deg": angles, "A_N_per_m": a, "B_N": b,
                         "D_N_m": d, "peak_energy_J": peak_energy,
                         "peak_Mx_N_per_unit_width": d[0][0]*max(sequence),
                         "peak_My_N_per_unit_width": d[1][0]*max(sequence)}

    check("mass", abs(p["length_m"]*p["width_m"]*3*p["ply_thickness_m"]*p["density_kg_m3"]-0.00432)/0.00432)
    args.output.mkdir(parents=True)
    with (args.output/"bending-reference.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["layup", "step", "curvature_per_m", "Mx_N_per_unit_width", "My_N_per_unit_width", "energy_J", "constraint_work_J"])
        writer.writerows(histories)
    # Uniaxial STRESS controls allow transverse Poisson contraction, unlike bending.
    with (args.output/"constitutive-reference.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["control", "strain_scale", "epsilon_1", "epsilon_2", "gamma_12", "sigma_1_Pa", "sigma_2_Pa", "tau_12_Pa", "energy_density_J_per_m3"])
        for mode in ("grain-tension", "cross-grain-tension", "shear"):
            for value in (0, 5e-5, 1e-4, 5e-5, 0, -1e-4, 0):
                e = ([value, -p["nu12"]*value, 0] if mode == "grain-tension" else
                     [-p["nu12"]*p["E2_Pa"]/p["E1_Pa"]*value, value, 0] if mode == "cross-grain-tension" else [0, 0, value])
                s = mv(q, e)
                expected = ([p["E1_Pa"]*value, 0, 0] if mode == "grain-tension" else
                            [0, p["E2_Pa"]*value, 0] if mode == "cross-grain-tension" else
                            [0, 0, p["G12_Pa"]*value])
                check(f"{mode}-{value}", max(abs(a-b) for a, b in zip(s, expected))/max(1, max(abs(v) for v in expected)))
                writer.writerow([mode, value, *e, *s, dot(e, s)/2])
    summary = {"fixture_id": p["fixture_id"], "scope": p["scope"],
               "source_revision": args.source_revision, "input_sha256": hashlib.sha256(raw).hexdigest(),
               "reference_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "python": platform.python_version(), "machine": platform.machine(),
               "output_root": str(args.output.resolve()), "terminal_reason": "reference self-checks passed",
               "elapsed_seconds": time.perf_counter()-started,
               "peak_RSS_bytes_macOS": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
               "self_checks": errors, "laminates": results,
               "baseline_control_D11_ratio": results["baseline"]["D_N_m"][0][0]/results["orientation-control"]["D_N_m"][0][0]}
    (args.output/"reference-summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(json.dumps({"terminal_reason": summary["terminal_reason"], "output": str(args.output),
                      "D11_ratio": summary["baseline_control_D11_ratio"],
                      "elapsed_seconds": summary["elapsed_seconds"], "peak_RSS_bytes": summary["peak_RSS_bytes_macOS"]}))


if __name__ == "__main__":
    main()
