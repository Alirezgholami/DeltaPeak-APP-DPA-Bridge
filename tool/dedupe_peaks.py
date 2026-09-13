#!/usr/bin/env python3
"""Merge and remove only high-confidence duplicate peaks from the bundled DPA DB.

A repeated name alone is NOT enough: Iran legitimately has different peaks with the
same name.  Two active records are merged only when their Persian-normalized names
match and either:
  1. both coordinates exist and are within 50 metres, or
  2. province and summit elevation match and a non-empty route or trailhead matches.

The more complete row is retained, missing reference fields are filled from the
other rows, GPX routes are re-parented, and duplicate peak rows are physically
removed from the bundled reference database.  Ambiguous homonyms remain separate.
"""
from __future__ import annotations

import argparse
import math
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

_ARABIC_TO_PERSIAN = str.maketrans({
    "ي": "ی", "ى": "ی", "ك": "ک", "ۀ": "ه", "ة": "ه",
    "ؤ": "و", "إ": "ا", "أ": "ا", "ٱ": "ا",
})
_DIACRITICS = re.compile(r"[\u064b-\u065f\u0670\u06d6-\u06edـ]")
_SPACE = re.compile(r"\s+")


def norm(value: object | None) -> str:
    if value is None:
        return ""
    text = str(value).strip().translate(_ARABIC_TO_PERSIAN)
    text = _DIACRITICS.sub("", text)
    return _SPACE.sub(" ", text).strip().lower()


def distance_m(a: sqlite3.Row, b: sqlite3.Row) -> float | None:
    if any(a[k] is None or b[k] is None for k in ("latitude", "longitude")):
        return None
    lat1, lon1 = math.radians(float(a["latitude"])), math.radians(float(a["longitude"]))
    lat2, lon2 = math.radians(float(b["latitude"])), math.radians(float(b["longitude"]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    q = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(q))


def same_elevation(a: sqlite3.Row, b: sqlite3.Row) -> bool:
    ea, eb = a["elevation"], b["elevation"]
    return ea is not None and eb is not None and abs(float(ea) - float(eb)) <= 1.0


def is_high_confidence_duplicate(a: sqlite3.Row, b: sqlite3.Row) -> bool:
    if not norm(a["name"]) or norm(a["name"]) != norm(b["name"]):
        return False
    d = distance_m(a, b)
    if d is not None and d <= 50.0:
        return True
    if a["province"] != b["province"] or not same_elevation(a, b):
        return False
    route_a, route_b = norm(a["route"]), norm(b["route"])
    trail_a, trail_b = norm(a["trailhead"]), norm(b["trailhead"])
    return bool((route_a and route_a == route_b) or (trail_a and trail_a == trail_b))


def completeness(row: sqlite3.Row) -> tuple[int, int, str]:
    weighted = {
        "latitude": 10, "longitude": 10, "county": 5, "district": 3,
        "elevation": 5, "map_elevation": 5, "mountain_range": 4,
        "route": 5, "trailhead": 5, "trailhead_elevation_m": 4,
        "elevation_gain_m": 4, "route_length_km": 4, "description": 2,
        "coordinate_source": 2, "source_url": 2,
    }
    score = 0
    for field, weight in weighted.items():
        value = row[field]
        if value is not None and (not isinstance(value, str) or value.strip()):
            score += weight
    score += min(int(row["route_count"] or 0), 5) * 3
    score += min(int(row["source_occurrence_count"] or 0), 10)
    # Stable tie-breaker: favour the lexicographically smaller source id.
    return (score, int(row["source_occurrence_count"] or 0), str(row["id"]))


def columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def active_rows(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    return list(conn.execute("SELECT * FROM peaks WHERE COALESCE(is_deleted,0)=0"))


def clusters(rows: list[sqlite3.Row]) -> list[list[sqlite3.Row]]:
    by_name: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in rows:
        by_name[norm(row["name"])].append(row)
    result: list[list[sqlite3.Row]] = []
    for _, group in by_name.items():
        if len(group) < 2:
            continue
        parent = list(range(len(group)))

        def find(i: int) -> int:
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        def union(i: int, j: int) -> None:
            ri, rj = find(i), find(j)
            if ri != rj:
                parent[rj] = ri

        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                if is_high_confidence_duplicate(group[i], group[j]):
                    union(i, j)
        components: dict[int, list[sqlite3.Row]] = defaultdict(list)
        for i, row in enumerate(group):
            components[find(i)].append(row)
        result.extend(c for c in components.values() if len(c) > 1)
    return result


def merge_cluster(conn: sqlite3.Connection, group: list[sqlite3.Row]) -> tuple[str, list[str]]:
    ordered = sorted(group, key=completeness, reverse=True)
    keeper, losers = ordered[0], ordered[1:]
    peak_cols = set(columns(conn, "peaks"))
    protected = {
        "id", "name", "province", "is_deleted", "favorite", "created_at_utc",
        "created_at_jalali", "deleted_at_utc", "deleted_at_jalali",
    }
    updates: dict[str, object] = {}
    for field in peak_cols - protected:
        current = keeper[field]
        if current is not None and (not isinstance(current, str) or current.strip()):
            continue
        for loser in losers:
            candidate = loser[field]
            if candidate is not None and (not isinstance(candidate, str) or candidate.strip()):
                updates[field] = candidate
                break

    # Do not double source occurrence counts; retain the strongest observed count.
    if "source_occurrence_count" in peak_cols:
        updates["source_occurrence_count"] = max(
            int(r["source_occurrence_count"] or 0) for r in group
        ) or None

    if updates:
        assignments = ", ".join(f"{k}=?" for k in updates)
        conn.execute(
            f"UPDATE peaks SET {assignments} WHERE id=?",
            [*updates.values(), keeper["id"]],
        )

    loser_ids = [str(r["id"]) for r in losers]
    if loser_ids:
        placeholders = ",".join("?" for _ in loser_ids)
        # Keep all route records but attach them to the canonical peak.
        conn.execute(
            f"UPDATE gpx_routes SET peak_id=? WHERE peak_id IN ({placeholders})",
            [keeper["id"], *loser_ids],
        )
        conn.execute(f"DELETE FROM peaks WHERE id IN ({placeholders})", loser_ids)
    return str(keeper["id"]), loser_ids


def refresh_counts(conn: sqlite3.Connection) -> int:
    conn.execute("""
        UPDATE peaks SET route_count=(
          SELECT COUNT(*) FROM gpx_routes r
          WHERE r.peak_id=peaks.id AND COALESCE(r.is_deleted,0)=0
        )
    """)
    count = int(conn.execute(
        "SELECT COUNT(*) FROM peaks WHERE COALESCE(is_deleted,0)=0"
    ).fetchone()[0])
    for key in ("record_count", "official_province_record_count"):
        conn.execute(
            "INSERT INTO metadata(key,value) VALUES(?,?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, str(count)),
        )
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("--max-removals", type=int, default=250,
                        help="Safety stop if heuristic wants to remove unexpectedly many rows")
    args = parser.parse_args()
    if not args.database.exists():
        raise SystemExit(f"Database not found: {args.database}")

    conn = sqlite3.connect(args.database)
    conn.row_factory = sqlite3.Row
    try:
        before = len(active_rows(conn))
        groups = clusters(active_rows(conn))
        removal_count = sum(len(g) - 1 for g in groups)
        if removal_count > args.max_removals:
            raise RuntimeError(
                f"Deduplication safety stop: {removal_count} proposed removals > {args.max_removals}"
            )
        merged: list[tuple[str, list[str]]] = []
        with conn:
            for group in groups:
                merged.append(merge_cluster(conn, group))
            after = refresh_counts(conn)
            conn.execute(
                "INSERT INTO metadata(key,value) VALUES('dedupe_high_confidence_removed',?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (str(removal_count),),
            )
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"SQLite integrity_check failed: {integrity}")
        print(f"DPA DEDUPE PASS: before={before} removed={removal_count} after={after} clusters={len(groups)}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
