from unittest.mock import patch, MagicMock
from gateway.alert_sender import send_alert


def test_send_alert_success():
    """Alert sends correctly and returns Feishu success response."""
    mock_response = MagicMock()
    mock_response.json.return_value = {"code": 0, "msg": "success"}

    with patch("gateway.alert_sender.requests.post", return_value=mock_response) as mock_post:
        result = send_alert("https://fake-webhook.url", "test message")

    mock_post.assert_called_once()
    assert result["code"] == 0


def test_send_alert_feishu_error():
    """RuntimeError raised when Feishu returns non-zero code."""
    mock_response = MagicMock()
    mock_response.json.return_value = {"code": 19002, "msg": "params error"}

    with patch("gateway.alert_sender.requests.post", return_value=mock_response):
        try:
            send_alert("https://fake-webhook.url", "test message")
            assert False, "Expected RuntimeError"
        except RuntimeError as e:
            assert "19002" in str(e)
