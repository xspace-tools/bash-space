# sconl-space/lib/equicycle.py
# Equicycle date engine for sconlx CLI.
# Called as a subprocess from bash — never imported directly.
# Keeps all date arithmetic in Python because bash date math is fragile
# across macOS/Linux/Git Bash, and we already need python3 for Pillow.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial implementation. Full Equicycle engine: year start
#             detection, cycle/day/theme calculation, multiple output formats.
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   python3 equicycle.py [--date YYYY-MM-DD] [--format short|full|fields|json]
#
# Formats:
#   short   → "Cycle 3 · Day 7 · Renewal · Apr 18"
#   full    → "Cycle 3 · Day 7 · Renewal (2026) · Saturday, April 18, 2026"
#   fields  → "2026\t3\t7\tRenewal"   (tab-separated, for bash read)
#   json    → {"year":2026,"cycle":3,"day":7,"theme":"Renewal",...}

import sys
import argparse
import json
from datetime import date, timedelta

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

# 13 cycles, one theme each — ordered cycle 1 to 13
CYCLE_THEMES: list[str] = [
    "Genesis",      # 1  — new beginnings, planting seeds
    "Momentum",     # 2  — building velocity
    "Ascent",       # 3  — climbing, effort
    "Harvest",      # 4  — reaping early results
    "Depth",        # 5  — going deeper
    "Synthesis",    # 6  — connecting dots
    "Renewal",      # 7  — mid-year reset
    "Vision",       # 8  — seeing clearly
    "Growth",       # 9  — expanding
    "Creation",     # 10 — making things
    "Flow",         # 11 — in the zone
    "Preparation",  # 12 — getting ready
    "Reflection",   # 13 — looking back before the year closes
]

DAYS_PER_CYCLE = 28
NUM_CYCLES = 13
DAYS_PER_YEAR = DAYS_PER_CYCLE * NUM_CYCLES  # 364


# ─────────────────────────────────────────────────────────────────────────────
# CORE ENGINE
# ─────────────────────────────────────────────────────────────────────────────

def year_start(year: int) -> date:
    """First Sunday of June for the given Equicycle year.

    The Equicycle year anchors to the first Sunday of June because
    June is the natural mid-year reset point — post-spring, pre-summer.
    Sunday is the traditional week-start for weekly planning systems.
    """
    june1 = date(year, 6, 1)
    # weekday(): Mon=0, Tue=1, ..., Sun=6
    days_until_sunday = (6 - june1.weekday()) % 7
    return june1 + timedelta(days=days_until_sunday)


def from_gregorian(d: date) -> dict:
    """Convert a Gregorian date to Equicycle components.

    Returns a dict with: year, cycle, day, theme, out_of_time, gregorian.
    'out_of_time' is True for the 1-2 day gap between year-end and next
    year's start (364-day year vs 365/366-day Gregorian year).
    """
    # Walk back to find the Equicycle year this date falls in
    year = d.year
    ys = year_start(year)
    if d < ys:
        year -= 1
        ys = year_start(year)

    days_elapsed = (d - ys).days

    if days_elapsed >= DAYS_PER_YEAR:
        # The gap day(s) between year end and next year's start
        return {
            "year": year,
            "cycle": None,
            "day": None,
            "theme": None,
            "out_of_time": True,
            "gregorian": str(d),
            "gregorian_formatted": d.strftime("%A, %B %d, %Y"),
        }

    cycle = days_elapsed // DAYS_PER_CYCLE + 1   # 1-indexed
    day   = days_elapsed % DAYS_PER_CYCLE + 1     # 1-indexed
    theme = CYCLE_THEMES[cycle - 1]

    return {
        "year": year,
        "cycle": cycle,
        "day": day,
        "theme": theme,
        "out_of_time": False,
        "gregorian": str(d),
        "gregorian_formatted": d.strftime("%A, %B %d, %Y"),
    }


def cycle_date_range(year: int, cycle: int) -> tuple[date, date]:
    """Return (start_date, end_date) for a given Equicycle year + cycle number."""
    ys = year_start(year)
    start = ys + timedelta(days=(cycle - 1) * DAYS_PER_CYCLE)
    end   = start + timedelta(days=DAYS_PER_CYCLE - 1)
    return start, end


def progress_bar(current: int, total: int, width: int = 20) -> str:
    """ASCII progress bar: [████░░░░░░░░░░░░░░░░] for terminal display."""
    filled = int(width * current / total) if total > 0 else 0
    bar = "█" * filled + "░" * (width - filled)
    return f"[{bar}]"


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Equicycle date engine — converts Gregorian to Equicycle format."
    )
    parser.add_argument(
        "--date", default=str(date.today()),
        help="Date to convert (YYYY-MM-DD). Defaults to today."
    )
    parser.add_argument(
        "--format", default="short",
        choices=["short", "full", "fields", "json", "progress"],
        help="Output format."
    )
    # Extra flag for cycle range queries
    parser.add_argument(
        "--cycle-range", nargs=2, metavar=("YEAR", "CYCLE"),
        help="Print start/end dates for a specific cycle (YEAR CYCLE)."
    )
    args = parser.parse_args()

    # Cycle range query — used by sconlx scope cycle display
    if args.cycle_range:
        yr, cy = int(args.cycle_range[0]), int(args.cycle_range[1])
        start, end = cycle_date_range(yr, cy)
        print(f"{start}\t{end}")
        return

    d = date.fromisoformat(args.date)
    eq = from_gregorian(d)

    if eq["out_of_time"]:
        # The brief gap between Equicycle years
        if args.format == "fields":
            print(f"{eq['year']}\t0\t0\tOut of Time")
        elif args.format == "json":
            print(json.dumps(eq))
        else:
            print(f"Out of Time — {eq['gregorian_formatted']}")
        return

    c, day, theme, year = eq["cycle"], eq["day"], eq["theme"], eq["year"]
    short_date = d.strftime("%b %d")

    if args.format == "short":
        print(f"Cycle {c} · Day {day} · {theme} · {short_date}")

    elif args.format == "full":
        print(f"Cycle {c} · Day {day} · {theme} ({year}) · {eq['gregorian_formatted']}")

    elif args.format == "fields":
        # Tab-separated for bash: read eq_year eq_cycle eq_day eq_theme
        print(f"{year}\t{c}\t{day}\t{theme}")

    elif args.format == "json":
        print(json.dumps(eq))

    elif args.format == "progress":
        # Day progress within cycle — used in the cycle display
        bar = progress_bar(day, DAYS_PER_CYCLE)
        pct = int(day * 100 / DAYS_PER_CYCLE)
        print(f"{bar} Day {day}/{DAYS_PER_CYCLE} ({pct}%)")


if __name__ == "__main__":
    main()