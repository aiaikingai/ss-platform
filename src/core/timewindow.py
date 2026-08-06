"""
Production day / shift boundary logic.

Mirrors the SQL functions `production_day()` and `production_shift()` in
`db/migrations/001_sites_and_machines.sql`. If one side changes, both must
change — they are pinned to identical outputs by tests/test_timewindow.py.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

_EIGHT_HOURS = timedelta(hours=8)


def _localize(ts: datetime, tz: str) -> datetime:
    """Return ts as an aware datetime in tz.

    Naive input is assumed to already be local wall-clock time in tz
    (factory data is recorded in local time, not UTC).
    """
    zone = ZoneInfo(tz)
    if ts.tzinfo is None:
        return ts.replace(tzinfo=zone)
    return ts.astimezone(zone)


def production_day(ts: datetime, tz: str = "Asia/Shanghai") -> date:
    """A production day runs 08:00 -> 08:00 the next calendar day."""
    local = _localize(ts, tz)
    return (local - _EIGHT_HOURS).date()


def production_shift(ts: datetime, tz: str = "Asia/Shanghai") -> str:
    """Shift A = 早班 08:00-20:00. Shift B = 晚班 20:00-08:00."""
    local = _localize(ts, tz)
    hour = local.hour
    return "A" if 8 <= hour < 20 else "B"
