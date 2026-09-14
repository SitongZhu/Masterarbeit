"""Verify and restore a locally supplied archived-generation bundle."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import shutil
import zipfile


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def restore(bundle, code):
    manifest = json.loads((bundle / "generation_bundle_manifest.json").read_text(encoding="utf-8"))
    if manifest["total_files"] != 580 or manifest["total_records"] != 5685270:
        raise ValueError("This is not the complete archived thesis generation bundle")
    records = {row["path"]: row for row in manifest["files"]}
    if len(records) != manifest["total_files"]:
        raise ValueError("Duplicate bundle paths")
    for row in manifest["archives"]:
        name = row["file"]
        if Path(name).name != name or "\\" in name:
            raise ValueError("Invalid archive name")
        path = bundle / name
        if digest(path) != row["sha256"]:
            raise ValueError(f"Archive checksum differs: {name}")
        with zipfile.ZipFile(path) as archive:
            expected = {key for key, item in records.items() if item["archive"] == name}
            if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
                raise ValueError(f"Unexpected archive entries: {name}")
            for member in archive.namelist():
                relative = PurePosixPath(member)
                if relative.is_absolute() or ".." in relative.parts or "\\" in member or ":" in member:
                    raise ValueError("Unsafe bundle path")
                if relative.parts[:3] != ("data", "llm_outputs", "outcome"):
                    raise ValueError("Bundle entry is outside the generation directory")
                target = code.joinpath(*relative.parts).resolve()
                if code not in target.parents:
                    raise ValueError("Bundle path escapes the code directory")
                if target.exists():
                    if digest(target) != records[member]["sha256"]:
                        raise ValueError(f"Existing file differs; preserved unchanged: {target}")
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = target.with_suffix(target.suffix + ".partial")
                with archive.open(member) as source, temporary.open("xb") as output:
                    shutil.copyfileobj(source, output)
                if digest(temporary) != records[member]["sha256"]:
                    raise ValueError(f"Extracted checksum differs: {member}")
                temporary.rename(target)
        print(f"Verified and restored {name}", flush=True)
    print(f"Restored {len(records)} generation files under {code / 'data/llm_outputs/outcome'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--code-dir", type=Path, default=Path(__file__).resolve().parents[1] / "code")
    args = parser.parse_args()
    restore(args.bundle_dir.resolve(), args.code_dir.resolve())
