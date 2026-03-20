from typing import Any


def success(data: Any = None, message: str = "ok", trace_id: str = "local-dev") -> dict[str, Any]:
    return {
        "code": 0,
        "message": message,
        "data": data,
        "trace_id": trace_id,
    }
