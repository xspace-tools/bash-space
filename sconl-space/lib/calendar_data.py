# sconl-space/lib/calendar_data.py
# Calendar intelligence layer for sconlx.
# Handles: holidays (Kenya + international), today-in-history facts,
# birthday calculations from calendar.json, and journal "on this day" lookups.
# Called as subprocess from calendar.sh — never imported directly.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Holidays (KE + INT), today-in-history facts,
#             birthday calculations, upcoming events, "on this day" journal.
# ─────────────────────────────────────────────────────────────────────────────

import sys, json, os, argparse
from datetime import date, timedelta
from typing import Optional

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

# International holidays (MM-DD : name)
INT_HOLIDAYS: dict[str, str] = {
    "01-01": "New Year's Day",
    "02-14": "Valentine's Day",
    "03-08": "International Women's Day",
    "04-01": "April Fools' Day",
    "04-22": "Earth Day",
    "05-01": "International Labour Day",
    "06-05": "World Environment Day",
    "06-21": "World Music Day",
    "07-04": "Independence Day (US)",
    "08-12": "International Youth Day",
    "09-21": "International Day of Peace",
    "10-10": "World Mental Health Day",
    "10-31": "Halloween",
    "11-11": "Remembrance Day",
    "12-01": "World AIDS Day",
    "12-10": "Human Rights Day",
    "12-25": "Christmas Day",
    "12-26": "Boxing Day",
    "12-31": "New Year's Eve",
}

# Kenya public holidays (MM-DD : name)
# Easter dates change yearly — not included in fixed list
KE_HOLIDAYS: dict[str, str] = {
    "01-01": "New Year's Day",
    "04-10": "Good Friday (approx)",
    "04-13": "Easter Monday (approx)",
    "05-01": "Labour Day",
    "06-01": "Madaraka Day",
    "06-10": "Eid ul-Fitr (approx, varies)",
    "10-10": "Huduma Day",
    "10-20": "Mashujaa Day",
    "12-12": "Jamhuri Day",
    "12-25": "Christmas Day",
    "12-26": "Boxing Day",
}

# Notable events in history by MM-DD
# Curated for global significance and positive framing where possible
TODAY_IN_HISTORY: dict[str, list[str]] = {
    "01-01": ["1863 — US Emancipation Proclamation took effect", "1994 — NAFTA came into force", "2002 — Euro coins and banknotes entered circulation in 12 EU countries"],
    "01-04": ["1903 — First transatlantic wireless radio message received"],
    "01-09": ["2007 — Steve Jobs introduced the first iPhone"],
    "01-15": ["1929 — Martin Luther King Jr. born in Atlanta", "2009 — US Airways Flight 1549 safely landed on the Hudson River"],
    "01-20": ["1961 — JFK inaugurated as US President"],
    "01-22": ["1984 — Apple's Macintosh computer launched with iconic Super Bowl ad"],
    "02-04": ["2004 — Facebook launched at Harvard"],
    "02-11": ["1990 — Nelson Mandela released from prison after 27 years"],
    "02-14": ["270 — Martyrdom of Saint Valentine (traditional)", "1876 — Alexander Graham Bell filed patent for the telephone"],
    "02-20": ["1962 — John Glenn became first American to orbit Earth"],
    "03-06": ["1869 — Dmitri Mendeleev presented the Periodic Table"],
    "03-08": ["1917 — International Women's Day first observed worldwide"],
    "03-14": ["1879 — Albert Einstein born in Ulm, Germany", "1883 — Karl Marx died in London"],
    "03-25": ["1807 — British Parliament abolished the slave trade"],
    "03-31": ["2005 — Apple released GarageBand, democratising music production"],
    "04-04": ["1968 — Martin Luther King Jr. assassinated in Memphis"],
    "04-12": ["1961 — Yuri Gagarin became first human in space"],
    "04-15": ["1955 — McDonald's first restaurant opened by Ray Kroc in Illinois"],
    "04-22": ["1970 — First Earth Day celebrated"],
    "04-23": ["1985 — Coca-Cola launched New Coke (and quickly reversed course)"],
    "05-05": ["1961 — Alan Shepard became first American in space"],
    "05-09": ["1960 — FDA approved the first oral contraceptive in the US"],
    "05-25": ["1977 — Star Wars Episode IV released", "1963 — Organisation of African Unity founded in Addis Ababa"],
    "05-27": ["1937 — Golden Gate Bridge opened to pedestrians"],
    "06-01": ["1963 — Kenya achieved internal self-governance (Madaraka Day)"],
    "06-04": ["1989 — Tiananmen Square crackdown, Beijing"],
    "06-06": ["1944 — D-Day: Allied forces landed on Normandy beaches"],
    "06-12": ["1963 — US Civil Rights leader Medgar Evers assassinated"],
    "07-04": ["1776 — United States Declaration of Independence signed"],
    "07-07": ["2007 — Live Earth concerts raised awareness of climate change"],
    "07-16": ["1969 — Apollo 11 launched, heading to the Moon"],
    "07-20": ["1969 — Neil Armstrong became first human to walk on the Moon"],
    "08-06": ["1945 — First atomic bomb dropped on Hiroshima"],
    "08-09": ["1995 — Netscape IPO, sparking the dot-com boom"],
    "08-28": ["1963 — Martin Luther King Jr. delivered 'I Have a Dream' speech"],
    "09-04": ["1998 — Google founded by Larry Page and Sergey Brin"],
    "09-11": ["2001 — September 11 attacks in New York and Washington"],
    "09-12": ["1962 — JFK gave 'We Choose to Go to the Moon' speech"],
    "09-25": ["2015 — UN adopted the Sustainable Development Goals"],
    "10-04": ["1957 — Sputnik 1, first artificial satellite, launched by USSR"],
    "10-10": ["2010 — Kenya's new constitution came into effect", "1985 — Achille Lauro hijacking"],
    "10-14": ["1066 — Battle of Hastings"],
    "10-20": ["1920 — Kenya became a British Crown Colony"],
    "10-28": ["1886 — Statue of Liberty dedicated in New York Harbor"],
    "11-04": ["2008 — Barack Obama elected first African American US President"],
    "11-09": ["1989 — Berlin Wall fell"],
    "11-10": ["1971 — Intel released the first commercial microprocessor"],
    "12-01": ["1955 — Rosa Parks refused to give up her bus seat in Montgomery"],
    "12-10": ["1948 — UN General Assembly adopted the Universal Declaration of Human Rights"],
    "12-12": ["1963 — Kenya gained independence from British rule (Jamhuri Day)"],
    "12-17": ["1903 — Wright Brothers made first powered airplane flight at Kitty Hawk"],
}

# ─────────────────────────────────────────────────────────────────────────────
# CORE FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def get_holidays_for_date(d: date, regions: list[str]) -> list[dict]:
    """Return all holidays that fall on a given date."""
    key = d.strftime("%m-%d")
    results = []
    if "INT" in regions and key in INT_HOLIDAYS:
        results.append({"name": INT_HOLIDAYS[key], "region": "INT", "type": "holiday"})
    if "KE" in regions and key in KE_HOLIDAYS:
        h = {"name": KE_HOLIDAYS[key], "region": "KE", "type": "holiday"}
        # Don't duplicate if same as INT
        if not any(r["name"] == h["name"] for r in results):
            results.append(h)
    return results


def get_history_for_date(d: date, limit: int = 3) -> list[str]:
    """Return today-in-history facts for a given month-day."""
    key = d.strftime("%m-%d")
    facts = TODAY_IN_HISTORY.get(key, [])
    return facts[:limit]


def load_calendar_data(cal_file: str) -> dict:
    """Load calendar.json, return empty structure on missing/corrupt."""
    try:
        with open(cal_file) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"birthdays": [], "custom_events": [], "settings": {}}


def save_calendar_data(cal_file: str, data: dict) -> None:
    os.makedirs(os.path.dirname(cal_file) or ".", exist_ok=True)
    with open(cal_file, "w") as f:
        json.dump(data, f, indent=2)


def get_upcoming_birthdays(birthdays: list[dict], today: date,
                           days_ahead: int = 30) -> list[dict]:
    """Return birthdays in the next days_ahead days, sorted by closeness."""
    upcoming = []
    for b in birthdays:
        raw_date = b.get("date", "")
        if not raw_date or "-" not in raw_date:
            continue
        parts = raw_date.split("-")
        if len(parts) == 2:
            month, day = int(parts[0]), int(parts[1])
        else:
            continue

        # Try this year's occurrence
        try:
            this_year = date(today.year, month, day)
        except ValueError:
            continue  # invalid date (e.g. Feb 29 on non-leap year)

        # If already passed this year, check next year
        if this_year < today:
            try:
                this_year = date(today.year + 1, month, day)
            except ValueError:
                continue

        days_until = (this_year - today).days
        if 0 <= days_until <= days_ahead:
            yob = b.get("year_of_birth")
            turning = (this_year.year - yob) if yob else None
            upcoming.append({
                "name": b.get("name", "Unknown"),
                "date": str(this_year),
                "date_fmt": this_year.strftime("%B %d"),
                "days_until": days_until,
                "turning": turning,
                "notes": b.get("notes", ""),
                "source": b.get("source", "manual"),
            })

    return sorted(upcoming, key=lambda x: x["days_until"])


def get_upcoming_events(custom_events: list[dict], today: date,
                        days_ahead: int = 30) -> list[dict]:
    """Return custom events in the next days_ahead days."""
    upcoming = []
    for ev in custom_events:
        raw_date = ev.get("date", "")
        if not raw_date:
            continue

        # Annual recurring: MM-DD
        if len(raw_date) == 5 and raw_date[2] == "-":
            parts = raw_date.split("-")
            try:
                this_year = date(today.year, int(parts[0]), int(parts[1]))
                if this_year < today:
                    this_year = date(today.year + 1, int(parts[0]), int(parts[1]))
            except ValueError:
                continue
        # One-time: YYYY-MM-DD
        else:
            try:
                this_year = date.fromisoformat(raw_date)
            except ValueError:
                continue
            if this_year < today:
                continue

        days_until = (this_year - today).days
        if 0 <= days_until <= days_ahead:
            upcoming.append({
                "title": ev.get("title", "Event"),
                "date": str(this_year),
                "date_fmt": this_year.strftime("%B %d"),
                "days_until": days_until,
                "category": ev.get("category", "personal"),
                "notes": ev.get("notes", ""),
            })

    return sorted(upcoming, key=lambda x: x["days_until"])


def check_journal_on_this_day(journal_dir: str, d: date) -> list[dict]:
    """Return journal entries from previous years on the same month-day."""
    month_day = d.strftime("%m%d")
    results = []
    if not os.path.isdir(journal_dir):
        return results
    for fname in sorted(os.listdir(journal_dir), reverse=True):
        if not fname.endswith(".md"):
            continue
        # Format: YYYYMMDD.md
        date_part = fname[:8]
        if len(date_part) == 8 and date_part[4:8] == month_day:
            year = int(date_part[:4])
            if year < d.year:
                full_path = os.path.join(journal_dir, fname)
                try:
                    with open(full_path) as f:
                        first_line = ""
                        for line in f:
                            stripped = line.strip()
                            if stripped and not stripped.startswith("#"):
                                first_line = stripped[:80]
                                break
                    results.append({
                        "date": f"{date_part[:4]}-{date_part[4:6]}-{date_part[6:8]}",
                        "year": year,
                        "years_ago": d.year - year,
                        "preview": first_line,
                    })
                except OSError:
                    pass
    return results[:3]  # max 3 past entries


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(description="iSconl calendar intelligence.")
    p.add_argument("--calendar-file", required=True, help="Path to calendar.json")
    p.add_argument("--journal-dir",   default="",   help="Path to journal/ directory")
    p.add_argument("--date",          default=str(date.today()), help="Target date YYYY-MM-DD")
    p.add_argument("--action", required=True,
                   choices=["today", "upcoming", "add-birthday", "add-event",
                             "list-birthdays", "list-events", "remove-birthday",
                             "remove-event", "month"],
                   help="Action to perform")
    # For add actions
    p.add_argument("--name",       default="")
    p.add_argument("--bday-date",  default="", help="MM-DD for birthday")
    p.add_argument("--year-born",  default="", help="YYYY year of birth (optional)")
    p.add_argument("--notes",      default="")
    p.add_argument("--event-title", default="")
    p.add_argument("--event-date", default="", help="YYYY-MM-DD or MM-DD for annual")
    p.add_argument("--category",   default="personal")
    p.add_argument("--regions",    default="KE,INT")
    p.add_argument("--days-ahead", type=int, default=30)
    p.add_argument("--history-limit", type=int, default=3)
    p.add_argument("--remove-index", type=int, default=-1)
    args = p.parse_args()

    d = date.fromisoformat(args.date)
    regions = [r.strip() for r in args.regions.split(",")]
    cal = load_calendar_data(args.calendar_file)

    if args.action == "today":
        output = {
            "date": str(d),
            "date_fmt": d.strftime("%A, %B %d, %Y"),
            "holidays": get_holidays_for_date(d, regions),
            "history": get_history_for_date(d, args.history_limit),
            "journal_on_this_day": check_journal_on_this_day(args.journal_dir, d) if args.journal_dir else [],
            "birthdays_today": [],
            "events_today": [],
        }
        # Check birthdays today
        for b in cal.get("birthdays", []):
            bdate = b.get("date", "")
            if bdate == d.strftime("%m-%d"):
                yob = b.get("year_of_birth")
                output["birthdays_today"].append({
                    "name": b["name"],
                    "turning": (d.year - yob) if yob else None,
                    "notes": b.get("notes", ""),
                })
        # Check custom events today
        for ev in cal.get("custom_events", []):
            ev_date = ev.get("date", "")
            if ev_date == str(d) or ev_date == d.strftime("%m-%d"):
                output["events_today"].append({
                    "title": ev["title"],
                    "category": ev.get("category", "personal"),
                })
        print(json.dumps(output, indent=2))

    elif args.action == "upcoming":
        output = {
            "date": str(d),
            "days_ahead": args.days_ahead,
            "birthdays": get_upcoming_birthdays(
                cal.get("birthdays", []), d, args.days_ahead),
            "events": get_upcoming_events(
                cal.get("custom_events", []), d, args.days_ahead),
        }
        # Add upcoming holidays
        upcoming_holidays = []
        for i in range(args.days_ahead + 1):
            check = d + timedelta(days=i)
            for h in get_holidays_for_date(check, regions):
                h["date"] = str(check)
                h["date_fmt"] = check.strftime("%B %d")
                h["days_until"] = i
                upcoming_holidays.append(h)
        output["holidays"] = upcoming_holidays
        print(json.dumps(output, indent=2))

    elif args.action == "list-birthdays":
        print(json.dumps(cal.get("birthdays", []), indent=2))

    elif args.action == "list-events":
        print(json.dumps(cal.get("custom_events", []), indent=2))

    elif args.action == "add-birthday":
        if not args.name or not args.bday_date:
            print("ERROR: --name and --bday-date required", file=sys.stderr)
            sys.exit(1)
        entry = {"name": args.name, "date": args.bday_date, "source": "manual"}
        if args.year_born:
            entry["year_of_birth"] = int(args.year_born)
        if args.notes:
            entry["notes"] = args.notes
        if "birthdays" not in cal:
            cal["birthdays"] = []
        cal["birthdays"].append(entry)
        save_calendar_data(args.calendar_file, cal)
        print(json.dumps({"ok": True, "entry": entry}))

    elif args.action == "add-event":
        if not args.event_title or not args.event_date:
            print("ERROR: --event-title and --event-date required", file=sys.stderr)
            sys.exit(1)
        entry = {
            "title": args.event_title,
            "date": args.event_date,
            "category": args.category,
        }
        if args.notes:
            entry["notes"] = args.notes
        if "custom_events" not in cal:
            cal["custom_events"] = []
        cal["custom_events"].append(entry)
        save_calendar_data(args.calendar_file, cal)
        print(json.dumps({"ok": True, "entry": entry}))

    elif args.action == "remove-birthday":
        idx = args.remove_index
        birthdays = cal.get("birthdays", [])
        if 0 <= idx < len(birthdays):
            removed = birthdays.pop(idx)
            save_calendar_data(args.calendar_file, cal)
            print(json.dumps({"ok": True, "removed": removed}))
        else:
            print(json.dumps({"ok": False, "error": "Invalid index"}))

    elif args.action == "remove-event":
        idx = args.remove_index
        events = cal.get("custom_events", [])
        if 0 <= idx < len(events):
            removed = events.pop(idx)
            save_calendar_data(args.calendar_file, cal)
            print(json.dumps({"ok": True, "removed": removed}))
        else:
            print(json.dumps({"ok": False, "error": "Invalid index"}))

    elif args.action == "month":
        # Return all events for the current month
        month_start = date(d.year, d.month, 1)
        # End of month
        if d.month == 12:
            month_end = date(d.year + 1, 1, 1) - timedelta(1)
        else:
            month_end = date(d.year, d.month + 1, 1) - timedelta(1)

        days_in_month = (month_end - month_start).days + 1
        month_data = []
        for i in range(days_in_month):
            day = month_start + timedelta(i)
            day_events = {
                "date": str(day),
                "day": day.day,
                "weekday": day.strftime("%a"),
                "is_today": (day == d),
                "holidays": get_holidays_for_date(day, regions),
                "birthdays": [],
                "events": [],
            }
            for b in cal.get("birthdays", []):
                if b.get("date", "") == day.strftime("%m-%d"):
                    day_events["birthdays"].append(b.get("name", "?"))
            for ev in cal.get("custom_events", []):
                ev_d = ev.get("date", "")
                if ev_d == str(day) or ev_d == day.strftime("%m-%d"):
                    day_events["events"].append(ev.get("title", "?"))
            month_data.append(day_events)

        print(json.dumps({
            "month": d.strftime("%B %Y"),
            "days": month_data,
        }, indent=2))


if __name__ == "__main__":
    main()