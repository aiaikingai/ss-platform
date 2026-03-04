from __future__ import annotations

import hashlib
import re


def _short_hash(text: str, length: int = 6) -> str:
    """Stable short hash used for fallback method codes."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:length].upper()


def _safe_slug(text: str) -> str:
    """
    Convert text to a safe ASCII identifier:
    - uppercase
    - non [A-Z0-9] -> underscore
    - collapse multiple underscores
    - trim underscores
    """
    s = text.upper()
    s = re.sub(r"[^A-Z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s)
    s = s.strip("_")
    return s or "METHOD"


def _parse_temp_minutes(method_name: str) -> tuple[int, int] | None:
    """
    Try to parse (temp_c, minutes) from MethodName.

    Examples supported:
      - 195℃测试15分钟
      - 180℃ 测试 40分钟
      - 170C 10min
      - 165°C test 20 minutes
    """
    s = method_name.strip()

    temp_match = re.search(r"(\d{2,3})\s*(?:℃|°C|C)", s, flags=re.IGNORECASE)
    min_match = re.search(r"(\d{1,3})\s*(?:分钟|min|mins|minutes)", s, flags=re.IGNORECASE)

    if not temp_match or not min_match:
        return None

    return int(temp_match.group(1)), int(min_match.group(1))


def derive_method_code(method_name: str) -> str:
    """
    🔒 LOCKED RULES (do not drift)

    - If contains 焦烧 -> SCORCH
    - If contains 门尼 -> MOONEY
    - If temp+minutes parseable -> MDR-<temp>-<min>  (e.g., MDR-195-15)
    - Else fallback -> SAFE_SLUG + "_" + SHORT_HASH
    """
    if not method_name:
        return "METHOD_UNKNOWN"

    raw = method_name.strip()

    # Known Mooney terms
    if "焦烧" in raw:
        return "SCORCH"
    if "门尼" in raw:
        return "MOONEY"

    # MDR temp/min
    parsed = _parse_temp_minutes(raw)
    if parsed:
        temp_c, minutes = parsed
        return f"MDR-{temp_c}-{minutes}"

    # Fallback
    slug = _safe_slug(raw)
    suffix = _short_hash(raw, length=6)
    return f"{slug}_{suffix}"
