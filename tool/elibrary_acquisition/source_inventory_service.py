#!/usr/bin/env python3
"""
source_inventory_service.py

Discover available source files and group them for EPUB-first or selective
text/HTML import.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from elibrary_import_normalizer import clean_text, file_checksum


SUPPORTED_SOURCE_EXTENSIONS = {
    ".epub": "epub",
    ".html": "html",
    ".htm": "html",
    ".xhtml": "html",
    ".txt": "txt",
}

CANDIDATE_DOCUMENT_EXTENSIONS = {
    ".epub",
    ".html",
    ".htm",
    ".xhtml",
    ".txt",
    ".pdf",
    ".doc",
    ".docx",
    ".rtf",
    ".odt",
    ".xlsx",
}

_IGNORED_PATH_PARTS = {
    ".git",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".venv",
    "venv",
    "node_modules",
}


@dataclass(frozen=True)
class SourceInventoryItem:
    path: Path
    source_type: str
    title: str
    author: str | None
    abbreviation: str | None
    group: str | None
    subgroup: str | None
    section: str | None
    chapter: str | None
    subchapter: str | None
    source_url: str | None = None
    checksum: str | None = None

    @property
    def is_epub(self) -> bool:
        return self.source_type == "epub"


@dataclass(frozen=True)
class SourceDiscovery:
    supported: list[SourceInventoryItem]
    unsupported: list[Path]


def _title_from_stem(stem: str) -> str:
    text = clean_text(stem.replace("_", " ").replace(".", " "))
    text = text.replace(" - ", " - ").strip()
    return text or stem


def _infer_metadata_from_path(path: Path, root: Path | None) -> tuple[str | None, str | None, str | None, str | None]:
    if root is not None:
        try:
            rel_parts = list(path.resolve().relative_to(root.resolve()).parts)
        except ValueError:
            rel_parts = [path.parent.name, path.parent.parent.name if path.parent.parent != path.parent else None]
    else:
        rel_parts = [path.parent.name]

    directories = [part for part in rel_parts[:-1] if part]

    author = directories[0] if len(directories) >= 1 else None
    group = directories[1] if len(directories) >= 2 else None
    subgroup = directories[2] if len(directories) >= 3 else None

    title = _title_from_stem(path.stem)
    if not author and " - " in title:
        left, right = title.split(" - ", 1)
        if left and right:
            author = left
            title = right

    abbreviation = None
    if len(title) <= 8 and title.isupper():
        abbreviation = title

    return author, group, subgroup, abbreviation


def discover_source_inventory(source_root: Path) -> list[SourceInventoryItem]:
    return scan_source_root(source_root).supported


def scan_source_root(source_root: Path) -> SourceDiscovery:
    root = Path(source_root)
    if root.is_file():
        root = root.parent

    supported: list[SourceInventoryItem] = []
    unsupported: list[Path] = []
    for path in sorted(Path(source_root).rglob("*") if Path(source_root).is_dir() else [Path(source_root)]):
        if not path.is_file():
            continue

        try:
            rel_parts = path.resolve().relative_to(root.resolve()).parts
        except ValueError:
            rel_parts = path.resolve().parts

        if any(part.startswith(".") or part in _IGNORED_PATH_PARTS for part in rel_parts):
            continue
        if path.suffix.lower() not in CANDIDATE_DOCUMENT_EXTENSIONS:
            continue

        source_type = SUPPORTED_SOURCE_EXTENSIONS.get(path.suffix.lower())
        if source_type is None:
            unsupported.append(path)
            continue

        author, group, subgroup, abbreviation = _infer_metadata_from_path(path, root)
        supported.append(
            SourceInventoryItem(
                path=path,
                source_type=source_type,
                title=_title_from_stem(path.stem),
                author=author,
                abbreviation=abbreviation,
                group=group,
                subgroup=subgroup,
                section=None,
                chapter=None,
                subchapter=None,
                checksum=file_checksum(path),
            )
        )

    return SourceDiscovery(supported=supported, unsupported=unsupported)


def inventory_group_label(item: SourceInventoryItem, source_root: Path | None = None) -> str:
    if item.author:
        return f"Author: {item.author}"

    group_bits = [bit for bit in [item.group, item.subgroup] if bit]
    if group_bits:
        return f"Group: {' > '.join(group_bits)}"

    if source_root is not None:
        try:
            relative_parent = item.path.resolve().parent.relative_to(Path(source_root).resolve())
            parent_text = relative_parent.as_posix()
        except ValueError:
            parent_text = item.path.parent.as_posix()
    else:
        parent_text = item.path.parent.as_posix()

    return f"Folder: {parent_text or item.path.stem}"


def group_inventory_items(
    items: list[SourceInventoryItem],
    source_root: Path | None = None,
) -> dict[str, list[SourceInventoryItem]]:
    grouped: dict[str, list[SourceInventoryItem]] = defaultdict(list)
    for item in items:
        grouped[inventory_group_label(item, source_root)].append(item)
    for values in grouped.values():
        values.sort(key=lambda item: (item.title.lower(), item.path.name.lower()))
    return dict(sorted(grouped.items(), key=lambda pair: pair[0].lower()))


def format_inventory_summary(items: list[SourceInventoryItem], source_root: Path | None = None) -> str:
    grouped = group_inventory_items(items, source_root)
    lines: list[str] = []
    for label, docs in grouped.items():
        epub_count = sum(1 for item in docs if item.is_epub)
        lines.append(f"{label} [{len(docs)} docs, {epub_count} epub]")
        for item in docs:
            group_bits = [bit for bit in [item.group, item.subgroup] if bit]
            group_text = f" | {' > '.join(group_bits)}" if group_bits else ""
            lines.append(f"  - {item.title} ({item.source_type}){group_text} | {item.path.name}")
    return "\n".join(lines)


def document_display_name(item: SourceInventoryItem, source_root: Path | None = None) -> str:
    if item.author:
        return f"{item.author} | {item.title}"
    group_label = inventory_group_label(item, source_root)
    if group_label.startswith("Group:"):
        return f"{group_label} | {item.title}"
    return f"{item.path.parent.name or item.path.stem} | {item.title}"


def filter_inventory(
    items: list[SourceInventoryItem],
    *,
    authors: set[str] | None = None,
    titles: set[str] | None = None,
    groups: set[str] | None = None,
) -> list[SourceInventoryItem]:
    selected: list[SourceInventoryItem] = []
    for item in items:
        if authors and (item.author or "") not in authors:
            continue
        if titles and item.title not in titles and item.path.name not in titles and item.path.stem not in titles:
            continue
        if groups:
            item_groups = {bit for bit in [item.group, item.subgroup] if bit}
            if item_groups.isdisjoint(groups):
                continue
        selected.append(item)
    return selected
