import requests


def send_alert(webhook_url: str, message: str) -> dict:
    """Send a plain-text alert message to a Feishu group via custom bot webhook.

    Args:
        webhook_url: the Feishu custom bot webhook URL.
        message: the text content to send.

    Returns:
        The parsed JSON response from Feishu.

    Raises:
        requests.HTTPError: if the HTTP request itself fails (network error,
            non-2xx status code).
        RuntimeError: if Feishu accepts the HTTP request but reports an
            application-level error (response "code" != 0).
    """
    payload = {
        "msg_type": "text",
        "content": {"text": message},
    }

    response = requests.post(webhook_url, json=payload, timeout=10)
    response.raise_for_status()

    result = response.json()
    if result.get("code") != 0:
        raise RuntimeError(f"Feishu rejected the message: {result}")

    return result
