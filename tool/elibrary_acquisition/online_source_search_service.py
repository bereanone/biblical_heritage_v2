#!/usr/bin/env python3
"""
online_source_search_service.py

Optional search-before-import support for sources that expose a remote search
endpoint or searchable local metadata/content inventory.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Iterable
from urllib.parse import quote_plus
from urllib.request import urlopen

from elibrary_import_normalizer import clean_text
from source_inventory_service import SourceInventoryItem


@dataclass(frozen=True)
class SearchResult:
    item: SourceInventoryItem
    snippet: str | None
    score: int
    match_source: str


def _local_snippet(path: Path, query: str, limit: int = 240) -> str | None:
    if not path.exists() or not path.is_file():
        return None

    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None

    lowered = text.lower()
    needle = query.lower()
    position = lowered.find(needle)
    if position < 0:
        return None

    start = max(0, position - 80)
    end = min(len(text), position + len(query) + 120)
    snippet = clean_text(text[start:end])
    if len(snippet) > limit:
        snippet = snippet[:limit].rstrip() + "..."
    return snippet


def search_inventory_locally(items: Iterable[SourceInventoryItem], query: str) -> list[SearchResult]:
    query_text = clean_text(query)
    if not query_text:
        return []

    terms = [term for term in query_text.lower().split() if term]
    if not terms:
        return []

    results: list[SearchResult] = []
    for item in items:
        haystack = " ".join(
            part
            for part in [
                item.author or "",
                item.title,
                item.group or "",
                item.subgroup or "",
                item.path.as_posix(),
                item.source_type,
            ]
            if part
        ).lower()

        if not all(term in haystack for term in terms):
            snippet = _local_snippet(item.path, query_text)
            if snippet is None:
                continue
            results.append(SearchResult(item=item, snippet=snippet, score=1, match_source="content"))
            continue

        score = sum(haystack.count(term) for term in terms)
        results.append(SearchResult(item=item, snippet=_local_snippet(item.path, query_text), score=score, match_source="metadata"))

    results.sort(key=lambda result: (-result.score, result.item.author or "", result.item.title.lower()))
    return results


def search_remote_source(search_url_template: str, query: str, timeout_seconds: int = 20) -> list[dict[str, object]]:
    encoded_query = quote_plus(clean_text(query))
    url = search_url_template.format(query=encoded_query)
    with urlopen(url, timeout=timeout_seconds) as response:
        payload = response.read()
        content_type = response.headers.get_content_type()

    if content_type == "application/json":
        data = json.loads(payload.decode("utf-8", errors="ignore"))
        if isinstance(data, dict):
            results = data.get("results") or data.get("items") or []
            return results if isinstance(results, list) else []
        if isinstance(data, list):
            return data
        return []

    text = payload.decode("utf-8", errors="ignore")
    return [
        {
            "title": clean_text(line),
            "snippet": None,
            "raw": line,
        }
        for line in text.splitlines()
        if clean_text(line)
    ]
