#!/usr/bin/env python3
"""Build and search a lightweight repository context map."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


DEFAULT_MAP_PATH = Path(".factory/context/repo-map.json")
MAX_TEXT_BYTES = 512 * 1024
MAX_SEARCH_RESULTS = 10

EXCLUDED_PREFIXES = (
    ".git/",
    ".worktrees/",
    ".symphony/",
    ".venv/",
    "venv/",
    "node_modules/",
    "vendor/",
    "Pods/",
    "DerivedData/",
    ".build/",
    "build/",
    "dist/",
    ".pytest_cache/",
    "__pycache__/",
    "docs/build-evidence/",
)

EXCLUDED_PARTS = {
    ".git",
    ".worktrees",
    ".symphony",
    ".venv",
    "venv",
    "node_modules",
    "vendor",
    "Pods",
    "DerivedData",
    ".build",
    "build",
    "dist",
    ".pytest_cache",
    "__pycache__",
}

BINARY_EXTENSIONS = {
    ".a",
    ".app",
    ".bin",
    ".car",
    ".cer",
    ".db",
    ".dmg",
    ".gif",
    ".gz",
    ".heic",
    ".icns",
    ".ico",
    ".jar",
    ".jpeg",
    ".jpg",
    ".key",
    ".mp4",
    ".pdf",
    ".pkl",
    ".png",
    ".sqlite",
    ".tar",
    ".webp",
    ".xcarchive",
    ".zip",
}

MARKDOWN_EXTENSIONS = {".md", ".markdown"}
SWIFT_EXTENSIONS = {".swift"}
PYTHON_EXTENSIONS = {".py"}
GO_EXTENSIONS = {".go"}
JS_TS_EXTENSIONS = {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx"}

TOKEN_RE = re.compile(r"[A-Za-z0-9]+")
CAMEL_RE = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")


def repo_root_from_cwd() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return Path(result.stdout.strip())


def git_ls_files(repo_root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def should_include(path: str, repo_root: Path) -> bool:
    if path.startswith(EXCLUDED_PREFIXES):
        return False
    parts = set(Path(path).parts)
    if parts & EXCLUDED_PARTS:
        return False
    extension = Path(path).suffix.lower()
    if extension in BINARY_EXTENSIONS:
        return False
    try:
        size = (repo_root / path).stat().st_size
    except OSError:
        return False
    if size > MAX_TEXT_BYTES:
        return False
    return True


def category_for_path(path: str, extension: str) -> str:
    if path.startswith(".github/workflows/") and extension in {".yml", ".yaml"}:
        return "github-workflow"
    if extension in MARKDOWN_EXTENSIONS:
        return "docs"
    if extension in SWIFT_EXTENSIONS:
        return "swift"
    if extension in PYTHON_EXTENSIONS:
        return "python"
    if extension in GO_EXTENSIONS:
        return "go"
    if extension in JS_TS_EXTENSIONS:
        return "javascript"
    if extension in {".json", ".yaml", ".yml", ".toml", ".plist", ".xcconfig"}:
        return "config"
    if path.startswith("ios/"):
        return "ios"
    if path.startswith("backend/"):
        return "backend"
    if path.startswith("website/"):
        return "website"
    if path.startswith("docs/"):
        return "docs"
    return "other"


def read_text(path: Path) -> str:
    data = path.read_bytes()
    if b"\0" in data:
        raise UnicodeDecodeError("utf-8", data, 0, 1, "binary file")
    return data.decode("utf-8", errors="replace")


def markdown_headings(text: str) -> list[str]:
    headings = []
    for line in text.splitlines():
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if match:
            headings.append(match.group(1).strip())
    return unique_preserving_order(headings)


def swift_entities(text: str) -> list[str]:
    patterns = [
        r"\b(?:public|private|fileprivate|internal|open|final|indirect)?\s*(?:struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)",
        r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
    ]
    return unique_from_patterns(text, patterns)


def python_entities(text: str) -> list[str]:
    patterns = [
        r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)\b",
        r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
    ]
    return unique_from_patterns(text, patterns)


def go_entities(text: str) -> list[str]:
    patterns = [
        r"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s+",
        r"^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\(",
    ]
    return unique_from_patterns(text, patterns)


def js_ts_entities(text: str) -> list[str]:
    patterns = [
        r"\bexport\s+(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
        r"\bexport\s+(?:default\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)\b",
        r"\bexport\s+(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\b",
        r"\b(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
        r"\bclass\s+([A-Za-z_$][A-Za-z0-9_$]*)\b",
        r"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=",
    ]
    return unique_from_patterns(text, patterns)


def workflow_entities(text: str) -> list[str]:
    entities = []
    for line in text.splitlines():
        match = re.match(r"^name:\s*(.+?)\s*$", line)
        if match:
            entities.append(f"workflow:{strip_yaml_scalar(match.group(1))}")
            break

    in_jobs = False
    for line in text.splitlines():
        if re.match(r"^jobs:\s*$", line):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if match:
            entities.append(f"job:{match.group(1)}")
        elif line and not line.startswith(" "):
            in_jobs = False
    return unique_preserving_order(entities)


def strip_yaml_scalar(value: str) -> str:
    return value.strip().strip("\"'")


def unique_from_patterns(text: str, patterns: list[str]) -> list[str]:
    names = []
    for pattern in patterns:
        names.extend(re.findall(pattern, text, flags=re.MULTILINE))
    return unique_preserving_order(names)


def unique_preserving_order(values: list[str]) -> list[str]:
    seen = set()
    unique = []
    for value in values:
        if value and value not in seen:
            unique.append(value)
            seen.add(value)
    return unique


def extract_entities(category: str, extension: str, text: str, headings: list[str]) -> list[str]:
    if category == "github-workflow":
        return workflow_entities(text)
    if extension in MARKDOWN_EXTENSIONS:
        return headings
    if extension in SWIFT_EXTENSIONS:
        return swift_entities(text)
    if extension in PYTHON_EXTENSIONS:
        return python_entities(text)
    if extension in GO_EXTENSIONS:
        return go_entities(text)
    if extension in JS_TS_EXTENSIONS:
        return js_ts_entities(text)
    return []


def build_entry(repo_root: Path, path: str) -> dict[str, object] | None:
    full_path = repo_root / path
    try:
        text = read_text(full_path)
    except UnicodeDecodeError:
        return None
    extension = full_path.suffix.lower()
    category = category_for_path(path, extension)
    headings = markdown_headings(text) if extension in MARKDOWN_EXTENSIONS else []
    entities = extract_entities(category, extension, text, headings)
    size_bytes = full_path.stat().st_size
    return {
        "path": path,
        "extension": extension,
        "category": category,
        "lineCount": len(text.splitlines()),
        "sizeBytes": size_bytes,
        "headings": headings,
        "entities": entities,
    }


def build_repo_map(repo_root: Path, out_path: Path | None = None) -> dict[str, object]:
    repo_root = repo_root.resolve()
    files = []
    for path in git_ls_files(repo_root):
        if not should_include(path, repo_root):
            continue
        entry = build_entry(repo_root, path)
        if entry is not None:
            files.append(entry)

    repo_map = {
        "schemaVersion": 1,
        "generatedBy": "scripts/context/context_map.py",
        "fileCount": len(files),
        "files": files,
    }
    if out_path is not None:
        write_json(repo_map, out_path)
    return repo_map


def write_json(repo_map: dict[str, object], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(repo_map, indent=2, sort_keys=True) + "\n")


def load_repo_map(path: Path) -> dict[str, object]:
    return json.loads(path.read_text())


def tokenize(value: str) -> set[str]:
    pieces = []
    for token in TOKEN_RE.findall(value):
        pieces.extend(CAMEL_RE.sub(" ", token).split())
    return {piece.lower() for piece in pieces if piece}


def score_entry(entry: dict[str, object], query_tokens: set[str]) -> dict[str, object] | None:
    why = []
    score = 0

    fields = [
        ("path", entry["path"], 3),
        ("category", entry["category"], 2),
    ]
    fields.extend(("entities", entity, 4) for entity in entry.get("entities", []))
    fields.extend(("headings", heading, 3) for heading in entry.get("headings", []))

    for field_name, value, weight in fields:
        tokens = tokenize(str(value))
        overlap = sorted(query_tokens & tokens)
        if not overlap:
            continue
        score += len(overlap) * weight
        if field_name in {"entities", "headings"}:
            why.append(f"{field_name}:{value}")
        else:
            why.extend(f"{field_name}:{token}" for token in overlap)

    if score == 0:
        return None
    return {
        "path": entry["path"],
        "score": score,
        "why": unique_preserving_order(why),
        "entities": entry.get("entities", []),
        "headings": entry.get("headings", []),
        "category": entry["category"],
        "lineCount": entry["lineCount"],
        "sizeBytes": entry["sizeBytes"],
    }


def search_repo_map(repo_map: dict[str, object], query: str, limit: int = MAX_SEARCH_RESULTS) -> list[dict[str, object]]:
    query_tokens = tokenize(query)
    if not query_tokens:
        return []
    results = []
    for entry in repo_map.get("files", []):
        scored = score_entry(entry, query_tokens)
        if scored is not None:
            results.append(scored)
    results.sort(key=lambda item: (-int(item["score"]), str(item["path"])))
    return results[:limit]


def format_results(query: str, results: list[dict[str, object]]) -> str:
    lines = [f"Top matches for: {query}"]
    if not results:
        lines.append("No matches.")
        return "\n".join(lines)
    for index, result in enumerate(results, start=1):
        lines.append(f"{index}. {result['path']} [{result['category']}, score {result['score']}]")
        lines.append(f"   why: {', '.join(result['why'])}")
        if result["entities"]:
            lines.append(f"   entities: {', '.join(result['entities'][:12])}")
        if result["headings"]:
            lines.append(f"   headings: {', '.join(result['headings'][:8])}")
    return "\n".join(lines)


def handle_build(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_cwd()
    out_path = Path(args.out)
    repo_map = build_repo_map(repo_root, out_path)
    print(f"Wrote {out_path} with {repo_map['fileCount']} files.")
    return 0


def handle_search(args: argparse.Namespace) -> int:
    repo_map = load_repo_map(Path(args.map))
    results = search_repo_map(repo_map, args.query)
    print(format_results(args.query, results))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build and search the EPAC repository context map.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="Build a repo context map from tracked files.")
    build.add_argument("--out", default=str(DEFAULT_MAP_PATH), help="Output JSON path.")
    build.set_defaults(func=handle_build)

    search = subparsers.add_parser("search", help="Search a generated repo context map.")
    search.add_argument("--query", required=True, help="Search query.")
    search.add_argument("--map", default=str(DEFAULT_MAP_PATH), help="Path to repo-map.json.")
    search.set_defaults(func=handle_search)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
