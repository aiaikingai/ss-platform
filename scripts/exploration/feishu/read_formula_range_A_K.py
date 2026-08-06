import os
import csv
from pathlib import Path

import requests


spreadsheet_token = os.environ["FEISHU_WAIZHU_SPREADSHEET_TOKEN"]

token_resp = requests.post(
    "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
    json={"app_id": os.environ["FEISHU_APP_ID"], "app_secret": os.environ["FEISHU_APP_SECRET"]},
    headers={"Content-Type": "application/json; charset=utf-8"},
)
token_data = token_resp.json()
if token_data["code"] != 0:
    raise RuntimeError(f"Token request failed: {token_data['msg']}")
tenant_token = token_data["tenant_access_token"]
sheet_id = "c43cb0"

range_str = f"{sheet_id}!A1:M19000"

url = (
    "https://open.feishu.cn/open-apis/sheets/v2/spreadsheets/"
    f"{spreadsheet_token}/values/{range_str}"
    "?valueRenderOption=Formula"
)

response = requests.get(
    url,
    headers={"Authorization": f"Bearer {tenant_token}"},
    timeout=60,
)

response.raise_for_status()
data = response.json()

if data.get("code") != 0:
    raise RuntimeError(
        f"Feishu read failed. "
        f"Code: {data.get('code')}, "
        f"Message: {data.get('msg')}"
    )

rows = data["data"]["valueRange"].get("values", [])

# Ensure every row has exactly 13 columns: A through M
column_count = 13
normalized_rows = []

for row in rows:
    normalized_row = list(row[:column_count])

    if len(normalized_row) < column_count:
        normalized_row.extend([""] * (column_count - len(normalized_row)))

    normalized_rows.append(normalized_row)

# Export location: Mac Desktop
desktop_path = Path.home() / "Desktop"
output_path = desktop_path / "feishu_sheet_export.csv"

desktop_path.mkdir(parents=True, exist_ok=True)

with output_path.open(
    mode="w",
    newline="",
    encoding="utf-8-sig",
) as csv_file:
    writer = csv.writer(csv_file)
    writer.writerows(normalized_rows)

print(f"Export completed: {output_path}")
print(f"Rows exported: {len(normalized_rows)}")