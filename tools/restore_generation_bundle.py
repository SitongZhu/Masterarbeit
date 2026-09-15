"""Verify and restore a locally supplied archived-generation bundle."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import shutil
import zipfile

EXPECTED_FILES = 580
EXPECTED_RECORDS = 5685270


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def restore(bundle, code):
    bundle, code = Path(bundle).resolve(), Path(code).resolve()
    manifest = json.loads((bundle / "generation_bundle_manifest.json").read_text(encoding="utf-8"))
    if manifest["total_files"] != EXPECTED_FILES or manifest["total_records"] != EXPECTED_RECORDS:
        raise ValueError("This is not the complete archived thesis generation bundle")
    records = {row["path"]: row for row in manifest["files"]}
    if len(records) != len(manifest["files"]) or len(records) != manifest["total_files"]:
        raise ValueError("Duplicate bundle paths or file count mismatch")
    archives = {row["file"]: row for row in manifest["archives"]}
    if len(archives) != len(manifest["archives"]):
        raise ValueError("Duplicate archive names")
    if {row["archive"] for row in records.values()} != set(archives):
        raise ValueError("Archive list does not cover exactly the referenced archives")
    if any(type(row["records"]) is not int or row["records"] < 0 for row in records.values()):
        raise ValueError("Invalid per-file record count")
    if sum(row["records"] for row in records.values()) != manifest["total_records"]:
        raise ValueError("Per-file record counts do not match the bundle total")
    targets = {}
    for member in records:
        relative = PurePosixPath(member)
        if (relative.is_absolute() or ".." in relative.parts or "\\" in member or ":" in member
                or relative.as_posix() != member):
            raise ValueError("Unsafe bundle path")
        if relative.parts[:3] != ("data", "llm_outputs", "outcome"):
            raise ValueError("Bundle entry is outside the generation directory")
        target = code.joinpath(*relative.parts).resolve()
        if code not in target.parents:
            raise ValueError("Bundle path escapes the code directory")
        targets[member] = target
    if len(set(targets.values())) != len(targets):
        raise ValueError("Bundle paths resolve to duplicate destinations")
    # Check all archives before writing any generation files.
    for row in manifest["archives"]:
        name = row["file"]
        if Path(name).name != name or "\\" in name or ":" in name:
            raise ValueError("Invalid archive name")
        if row["records"] != sum(item["records"] for item in records.values() if item["archive"] == name):
            raise ValueError(f"Archive record count differs: {name}")
        path = bundle / name
        if digest(path) != row["sha256"]:
            raise ValueError(f"Archive checksum differs: {name}")
        with zipfile.ZipFile(path) as archive:
            expected = {key for key, item in records.items() if item["archive"] == name}
            if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
                raise ValueError(f"Unexpected archive entries: {name}")
    restored = set()
    for name in archives:
        with zipfile.ZipFile(bundle / name) as archive:
            for member in archive.namelist():
                target = targets[member]
                if target.exists():
                    if digest(target) != records[member]["sha256"]:
                        raise ValueError(f"Existing file differs; preserved unchanged: {target}")
                    restored.add(member)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = target.with_suffix(target.suffix + ".partial")
                with archive.open(member) as source, temporary.open("xb") as output:
                    shutil.copyfileobj(source, output)
                if digest(temporary) != records[member]["sha256"]:
                    raise ValueError(f"Extracted checksum differs: {member}")
                temporary.rename(target)
                restored.add(member)
        print(f"Verified and restored {name}", flush=True)
    if restored != set(records):
        raise ValueError("Incomplete restoration: expected files are missing")
    verified_records = 0
    for member, target in targets.items():
        if not target.is_file() or digest(target) != records[member]["sha256"]:
            raise ValueError(f"Restored file missing or checksum differs: {member}")
        with target.open("rb") as handle:
            count = sum(1 for line in handle if line.strip())
        if count != records[member]["records"]:
            raise ValueError(f"Restored record count differs: {member}")
        verified_records += count
    if verified_records != manifest["total_records"]:
        raise ValueError("Restored record total differs")
    print(f"Restored and verified {len(restored)} generation files and {verified_records} records "
          f"under {code / 'data/llm_outputs/outcome'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--code-dir", type=Path, default=Path(__file__).resolve().parents[1] / "code")
    args = parser.parse_args()
    restore(args.bundle_dir.resolve(), args.code_dir.resolve())
