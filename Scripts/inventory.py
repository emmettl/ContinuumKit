#!/usr/bin/env python3
"""Collect a read-only source inventory; never writes to the source repositories.

Imports and @Test counts are lexical observations, not symbol dependency analysis
or executed test counts. SwiftPM target information comes from supplied descriptions.
"""
import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def git(root, *arguments):
    result = subprocess.run(
        ["git", "-C", str(root), *arguments], capture_output=True, text=True, check=False
    )
    return result.stdout.rstrip("\n") if result.returncode == 0 else None


def source_entry(root, path):
    data = path.read_bytes()
    entry = {"path": path.relative_to(root).as_posix(), "bytes": len(data),
             "sha256": hashlib.sha256(data).hexdigest()}
    if path.suffix == ".swift":
        source = data.decode("utf-8")
        entry["imports"] = sorted(set(re.findall(
            r"^\s*(?:@\w+\s+)*import\s+(?:struct\s+|class\s+|enum\s+|func\s+)?([A-Za-z_]\w*)",
            source, re.MULTILINE)))
        entry["test_annotation_count"] = len(re.findall(r"@Test\b", source))
    return entry


def files_under(root, selections):
    files = set()
    for selection in selections:
        path = root / selection
        if path.is_file():
            files.add(path)
        elif path.is_dir():
            files.update(p for p in path.rglob("*") if p.is_file() and not p.is_symlink()
                         and not any(part in {".build", ".swiftpm", ".git", "__pycache__"}
                                     for part in p.relative_to(root).parts))
    return files


def collect(name, root, selections, description):
    root = root.resolve()
    package = json.loads(description.read_text())
    files = files_under(root, selections)
    # Edgerton studies contain large movies/images; include numerical study code,
    # documentation and verification text only, not rendered/binary study artifacts.
    if name == "edgerton":
        files = {p for p in files if "Studies" not in p.relative_to(root).parts
                 or p.suffix in {".swift", ".md", ".txt", ".sh", ".py"}}
        files.update(p for p in (root / "Studies").glob("*.md"))
        files.update(p for p in (root / "Studies").glob("*verification*.txt"))
    entries = [source_entry(root, p) for p in sorted(files)]
    indexed = {entry["path"]: entry for entry in entries}
    digest = hashlib.sha256()
    for entry in entries:
        digest.update((entry["path"] + "\0" + entry["sha256"] + "\n").encode())
    targets = []
    for target in package["targets"]:
        target_path = Path(target["path"])
        if target_path.is_absolute():
            target_path = target_path.relative_to(root)
        paths = [(target_path / source).as_posix() for source in target.get("sources", [])]
        selected = [indexed[p] for p in paths if p in indexed]
        resources = []
        for resource in target.get("resources", []):
            item = dict(resource)
            path = Path(item["path"])
            if path.is_absolute():
                item["path"] = path.relative_to(root).as_posix()
            resources.append(item)
        targets.append({
            "name": target["name"], "type": target["type"],
            "path": target_path.as_posix(), "source_count": len(paths),
            "target_dependencies": target.get("target_dependencies", []),
            "product_dependencies": target.get("product_dependencies", []),
            "imports_lexical": sorted({i for e in selected for i in e.get("imports", [])}),
            "test_annotations_lexical": sum(e.get("test_annotation_count", 0) for e in selected),
            "resources": resources,
        })
    status = git(root, "status", "--short", "--", ".")
    return {
        "name": name, "package_name": package["name"],
        "git_revision": git(root, "rev-parse", "--verify", "HEAD"),
        "git_branch": git(root, "symbolic-ref", "--short", "HEAD"),
        "git_remote": git(root, "remote", "get-url", "origin"),
        "working_tree_status_in_package": status.splitlines() if status else [],
        "tools_version": package.get("tools_version"),
        "products": package.get("products", []), "targets": targets,
        "scope": selections, "file_count": len(entries),
        "snapshot_sha256": digest.hexdigest(), "files": entries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bombcad", required=True, type=Path)
    parser.add_argument("--edgerton", required=True, type=Path)
    parser.add_argument("--roomcad", type=Path, help="Standalone RoomCAD repository; requires --core")
    parser.add_argument("--core", type=Path, help="ContinuumKit repository; requires --roomcad")
    parser.add_argument("--descriptions", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if (args.roomcad is None) != (args.core is None):
        parser.error("Supply both --roomcad and --core for the four-repository inventory")
    scopes = [
        ("simulationkit", args.bombcad / "Packages/SimulationKit", ["Package.swift", "README.md", "Sources", "Tests"]),
        ("roomcad", args.bombcad / "RoomCAD", ["Package.swift", "README.md", "Sources", "Tests", "Scripts", "Validation"]),
        ("bombcad", args.bombcad, ["Package.swift", "LICENSE", "Sources", "Tests", "Scripts", "Packages/SimulationKit"]),
        ("edgerton", args.edgerton, ["Package.swift", "Sources", "Scripts", "Calibration", "Studies/TargetMechanics"]),
    ]
    if args.roomcad is not None:
        scopes = [
            ("continuumkit", args.core, ["Package.swift", "LICENSE", "Sources", "Tests", "Scripts"]),
            ("roomcad", args.roomcad, ["Package.swift", "LICENSE", "Sources", "Tests", "Scripts", "Fixtures"]),
            ("bombcad", args.bombcad, ["Package.swift", "LICENSE", "Sources", "Tests", "Scripts"]),
            ("edgerton", args.edgerton, ["Package.swift", "Sources", "Scripts", "Calibration", "Studies/TargetMechanics"]),
        ]
    result = {
        "schema_version": 1, "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "purpose": "Source inventory, not a model conformance or physical validation result",
        "method": "SwiftPM descriptions plus scoped file hashes and lexical imports/test annotations",
        "packages": [collect(n, r, s, args.descriptions / (n + "-package.json")) for n, r, s in scopes],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    for package in result["packages"]:
        print(package["name"], package["file_count"], package["snapshot_sha256"])


if __name__ == "__main__":
    main()
