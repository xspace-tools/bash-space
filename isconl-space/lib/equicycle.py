# sconl-space/lib/equicycle.py
# Equicycle date engine for sconlx CLI.
# All date arithmetic lives here. Called as subprocess from bash.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v2.0.0 — Added --all-formats (key=value for dashboard), --birthday (age,
#             hours, countdown), sprint (biweekly blocks), year progress,
#             YEAR_BAR / CYCLE_BAR progress bar strings.
#   v1.0.0 — Initial: from_gregorian, year_start, cycle_date_range.
# ─────────────────────────────────────────────────────────────────────────────

import sys, argparse, json, calendar
from datetime import date, datetime, timedelta
from typing import Optional

# ─── CONFIG ───────────────────────────────────────────────────────────────────

CYCLE_THEMES = [
    "Genesis","Momentum","Ascent","Harvest","Depth","Synthesis","Renewal",
    "Vision","Growth","Creation","Flow","Preparation","Reflection",
]
DAYS_PER_CYCLE = 28
NUM_CYCLES     = 13
DAYS_PER_YEAR  = DAYS_PER_CYCLE * NUM_CYCLES  # 364
BAR_WIDTH      = 20

# ─── PROGRESS BAR ─────────────────────────────────────────────────────────────

def progress_bar(current, total, width=BAR_WIDTH):
    if total <= 0: return "[" + "░" * width + "]"
    filled = min(int(width * current / total), width)
    return "[" + "█" * filled + "░" * (width - filled) + "]"

# ─── EQUICYCLE CORE ───────────────────────────────────────────────────────────

def year_start(year):
    """First Sunday of June for the given Equicycle year."""
    june1 = date(year, 6, 1)
    return june1 + timedelta(days=(6 - june1.weekday()) % 7)

def from_gregorian(d):
    year = d.year
    ys = year_start(year)
    if d < ys:
        year -= 1
        ys = year_start(year)
    elapsed = (d - ys).days
    if elapsed >= DAYS_PER_YEAR:
        return {"year":year,"cycle":None,"day":None,"theme":None,
                "out_of_time":True,"gregorian":str(d),
                "gregorian_formatted":d.strftime("%A, %B %d, %Y")}
    cycle = elapsed // DAYS_PER_CYCLE + 1
    day   = elapsed %  DAYS_PER_CYCLE + 1
    return {"year":year,"cycle":cycle,"day":day,"theme":CYCLE_THEMES[cycle-1],
            "out_of_time":False,"gregorian":str(d),
            "gregorian_formatted":d.strftime("%A, %B %d, %Y")}

def cycle_date_range(year, cycle):
    ys = year_start(year)
    s  = ys + timedelta(days=(cycle-1)*DAYS_PER_CYCLE)
    return s, s + timedelta(days=DAYS_PER_CYCLE-1)

# ─── YEAR PROGRESS ────────────────────────────────────────────────────────────

def year_progress(d):
    ys   = date(d.year, 1, 1)
    ye   = date(d.year, 12, 31)
    doy  = (d - ys).days + 1
    tot  = (ye - ys).days + 1
    pct  = int(doy * 100 / tot)
    return {"day":doy,"total":tot,"week":d.isocalendar()[1],"pct":pct,"bar":progress_bar(doy,tot)}

# ─── SPRINT (biweekly Gregorian blocks) ───────────────────────────────────────

def sprint_info(d):
    ys  = date(d.year, 1, 1)
    doy = (d - ys).days  # 0-indexed
    num = doy // 14 + 1
    day = doy %  14 + 1
    s   = ys + timedelta(days=(num-1)*14)
    e   = min(s + timedelta(days=13), date(d.year,12,31))
    return {"sprint":num,"day":day,"start":str(s),"end":str(e),
            "short":f"Sprint {num}  ·  Day {day}"}

# ─── BIRTHDAY / AGE ───────────────────────────────────────────────────────────

def age_from_birthday(birthday_str, today=None):
    today = today or date.today()
    try:
        bday = date.fromisoformat(birthday_str)
    except ValueError:
        return {"error": f"Invalid: {birthday_str}"}

    y = today.year  - bday.year
    m = today.month - bday.month
    d = today.day   - bday.day

    if d < 0:
        m -= 1
        pm = today.month - 1 if today.month > 1 else 12
        py = today.year  if today.month > 1 else today.year - 1
        d += calendar.monthrange(py, pm)[1]
    if m < 0:
        y -= 1
        m += 12

    birth_dt = datetime(bday.year, bday.month, bday.day)
    today_dt = datetime(today.year, today.month, today.day)
    hours    = int((today_dt - birth_dt).total_seconds() / 3600)

    try:    nb = date(today.year, bday.month, bday.day)
    except: nb = date(today.year, 3, 1)
    if nb <= today:
        try:    nb = date(today.year+1, bday.month, bday.day)
        except: nb = date(today.year+1, 3, 1)

    turning = nb.year - bday.year
    return {
        "years":y,"months":m,"days":d,
        "short":f"{y}y {m}m {d}d",
        "total_hours":hours,
        "next_birthday":str(nb),
        "next_birthday_formatted":nb.strftime("%B %d, %Y"),
        "days_to_next":(nb-today).days,
        "turning":turning,
    }

# ─── ALL-FORMATS (dashboard mode) ─────────────────────────────────────────────

def all_formats(d, birthday_str=None):
    """Output all context variables as KEY=VALUE for shell consumption."""
    eq = from_gregorian(d)
    yp = year_progress(d)
    sp = sprint_info(d)
    out = {}

    out["GREGORIAN"]       = d.strftime("%A, %B %d, %Y")
    out["GREGORIAN_SHORT"] = d.strftime("%a %d %b %Y")

    if not eq["out_of_time"]:
        c, day, theme, year = eq["cycle"], eq["day"], eq["theme"], eq["year"]
        out["EQ_YEAR"]    = str(year)
        out["EQ_CYCLE"]   = str(c)
        out["EQ_DAY"]     = str(day)
        out["EQ_THEME"]   = theme
        out["EQ_SHORT"]   = f"Cycle {c}  ·  Day {day}  ·  {theme}"
        out["CYCLE_BAR"]  = progress_bar(day, DAYS_PER_CYCLE)
        out["CYCLE_PCT"]  = str(int(day * 100 / DAYS_PER_CYCLE))
        cs, ce = cycle_date_range(year, c)
        out["CYCLE_START"] = str(cs)
        out["CYCLE_END"]   = str(ce)
    else:
        out["EQ_YEAR"]  = str(eq["year"])
        out["EQ_SHORT"] = "Out of Time"
        out["CYCLE_BAR"] = progress_bar(0, 1)
        out["CYCLE_PCT"] = "0"

    out["SPRINT"]       = str(sp["sprint"])
    out["SPRINT_DAY"]   = str(sp["day"])
    out["SPRINT_SHORT"] = sp["short"]
    out["SPRINT_START"] = sp["start"]
    out["SPRINT_END"]   = sp["end"]

    out["YEAR_DAY"]   = str(yp["day"])
    out["YEAR_TOTAL"] = str(yp["total"])
    out["YEAR_WEEK"]  = str(yp["week"])
    out["YEAR_PCT"]   = str(yp["pct"])
    out["YEAR_BAR"]   = yp["bar"]

    if birthday_str:
        age = age_from_birthday(birthday_str, d)
        if "error" not in age:
            out["AGE_YEARS"]    = str(age["years"])
            out["AGE_MONTHS"]   = str(age["months"])
            out["AGE_DAYS"]     = str(age["days"])
            out["AGE_SHORT"]    = age["short"]
            out["AGE_HOURS"]    = str(age["total_hours"])
            out["NEXT_BDAY"]    = age["next_birthday_formatted"]
            out["DAYS_TO_BDAY"] = str(age["days_to_next"])
            out["TURNING"]      = str(age["turning"])

    return out

# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Equicycle date engine.")
    p.add_argument("--date",        default=str(date.today()))
    p.add_argument("--format",      default="short",
                   choices=["short","full","fields","json","progress"])
    p.add_argument("--all-formats", action="store_true")
    p.add_argument("--birthday",    default=None)
    p.add_argument("--cycle-range", nargs=2, metavar=("YEAR","CYCLE"))
    args = p.parse_args()

    if args.cycle_range:
        s, e = cycle_date_range(int(args.cycle_range[0]), int(args.cycle_range[1]))
        print(f"{s}\t{e}")
        return

    d = date.fromisoformat(args.date)

    if args.all_formats:
        for k, v in all_formats(d, args.birthday).items():
            print(f"{k}={str(v).replace(chr(10),' ')}")
        return

    if args.birthday and not args.all_formats:
        age = age_from_birthday(args.birthday, d)
        if "error" in age:
            print(age["error"], file=sys.stderr); sys.exit(1)
        if args.format == "json":    print(json.dumps(age))
        elif args.format == "fields":
            print(f"{age['years']}\t{age['months']}\t{age['days']}\t"
                  f"{age['total_hours']}\t{age['next_birthday']}\t"
                  f"{age['days_to_next']}\t{age['turning']}")
        else:
            print(f"{age['short']}  ({age['total_hours']:,} hours)  "
                  f"·  {age['days_to_next']}d to next birthday ({age['next_birthday_formatted']})")
        return

    eq = from_gregorian(d)
    if eq["out_of_time"]:
        print(f"Out of Time — {eq['gregorian_formatted']}" if args.format != "fields"
              else f"{eq['year']}\t0\t0\tOut of Time")
        return

    c, day, theme, year = eq["cycle"], eq["day"], eq["theme"], eq["year"]
    if   args.format == "short":    print(f"Cycle {c}  ·  Day {day}  ·  {theme}  ·  {d.strftime('%b %d')}")
    elif args.format == "full":     print(f"Cycle {c}  ·  Day {day}  ·  {theme} ({year})  ·  {eq['gregorian_formatted']}")
    elif args.format == "fields":   print(f"{year}\t{c}\t{day}\t{theme}")
    elif args.format == "json":     print(json.dumps(eq))
    elif args.format == "progress":
        print(f"{progress_bar(day,DAYS_PER_CYCLE)} Day {day}/{DAYS_PER_CYCLE} ({int(day*100/DAYS_PER_CYCLE)}%)")

if __name__ == "__main__":
    main()