from collections import deque
from datetime import datetime, timedelta, timezone
from threading import Lock

from fastapi import HTTPException, status


class SlidingWindowRateLimiter:
    def __init__(self, *, limit_per_window: int, window_seconds: int, error_detail: str) -> None:
        self.limit_per_window = limit_per_window
        self.window_seconds = window_seconds
        self.error_detail = error_detail
        self._lock = Lock()
        self._timestamps: dict[str, deque[datetime]] = {}

    def reset(self) -> None:
        with self._lock:
            self._timestamps.clear()

    def enforce(self, keys: list[str], now: datetime | None = None) -> None:
        current_time = now or datetime.now(timezone.utc)
        window_start = current_time - timedelta(seconds=self.window_seconds)

        with self._lock:
            for key in keys:
                timestamps = self._timestamps.setdefault(key, deque())
                while timestamps and timestamps[0] <= window_start:
                    timestamps.popleft()

                if len(timestamps) >= self.limit_per_window:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail=self.error_detail,
                    )

            for key in keys:
                self._timestamps.setdefault(key, deque()).append(current_time)
