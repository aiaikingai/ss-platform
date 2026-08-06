from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from core.timewindow import production_day, production_shift

SHANGHAI = ZoneInfo("Asia/Shanghai")

CASES = [
    (datetime(2026, 3, 12, 7, 30), date(2026, 3, 11), "B"),
    (datetime(2026, 3, 12, 8, 0), date(2026, 3, 12), "A"),
    (datetime(2026, 3, 12, 8, 30), date(2026, 3, 12), "A"),
    (datetime(2026, 3, 12, 19, 30), date(2026, 3, 12), "A"),
    (datetime(2026, 3, 12, 20, 0), date(2026, 3, 12), "B"),
    (datetime(2026, 3, 12, 20, 30), date(2026, 3, 12), "B"),
    (datetime(2026, 3, 13, 7, 59), date(2026, 3, 12), "B"),
]


@pytest.mark.parametrize("ts, expected_day, expected_shift", CASES)
def test_production_day_naive(ts: datetime, expected_day: date, expected_shift: str) -> None:
    assert production_day(ts) == expected_day


@pytest.mark.parametrize("ts, expected_day, expected_shift", CASES)
def test_production_shift_naive(ts: datetime, expected_day: date, expected_shift: str) -> None:
    assert production_shift(ts) == expected_shift


@pytest.mark.parametrize("ts, expected_day, expected_shift", CASES)
def test_production_day_aware(ts: datetime, expected_day: date, expected_shift: str) -> None:
    aware = ts.replace(tzinfo=SHANGHAI)
    assert production_day(aware) == expected_day


@pytest.mark.parametrize("ts, expected_day, expected_shift", CASES)
def test_production_shift_aware(ts: datetime, expected_day: date, expected_shift: str) -> None:
    aware = ts.replace(tzinfo=SHANGHAI)
    assert production_shift(aware) == expected_shift


def test_naive_and_aware_agree() -> None:
    naive = datetime(2026, 3, 12, 8, 0)
    aware = naive.replace(tzinfo=SHANGHAI)

    assert production_day(naive) == production_day(aware)
    assert production_shift(naive) == production_shift(aware)
