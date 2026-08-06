from domains.lab import build_unique_key, derive_method_code


def test_cn_mooney_terms():
    assert derive_method_code("焦烧") == "SCORCH"
    assert derive_method_code("焦烧测试") == "SCORCH"
    assert derive_method_code("门尼") == "MOONEY"
    assert derive_method_code("门尼粘度") == "MOONEY"


def test_mdr_temp_minutes_cn():
    assert derive_method_code("195℃测试15分钟") == "MDR-195-15"
    assert derive_method_code("180℃ 测试 40分钟") == "MDR-180-40"


def test_unique_key_locked_format():
    row = {
        "MethodName": "195℃测试15分钟",
        "ID": "17",
        "TestDate": "2026/1/1 0:00",
        "TestTime": "01:42:12",
    }
    assert build_unique_key(row, "MDR_PC_A") == "MDR_PC_A:MDR-195-15:17"