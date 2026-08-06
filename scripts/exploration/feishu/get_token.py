import os
import requests

resp = requests.post(
    "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
    json={"app_id": os.environ["FEISHU_APP_ID"], "app_secret": os.environ["FEISHU_APP_SECRET"]},
    headers={"Content-Type": "application/json; charset=utf-8"},
)
data = resp.json()
if data["code"] != 0:
    raise RuntimeError(f"Token request failed: {data['msg']}")
tenant_token = data["tenant_access_token"]
print("code:", data["code"])
print("msg:", data["msg"])
print("token:", tenant_token)
