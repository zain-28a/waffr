"""Error logging that keeps values out of the logs.

A database error's text quotes the values it refused (``Key (note)=(...)``),
and other exceptions can carry amounts or emails in their message. The log
gets the exception type and the stack (file, line, function), which is what
debugging needs, and never the message.
"""

import logging
import traceback

from starlette.responses import JSONResponse

logger = logging.getLogger("waffr.errors")


def describe(error: BaseException) -> str:
    """The exception's type chain and stack, without any message text."""
    parts = []
    seen = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        frames = "".join(traceback.format_tb(current.__traceback__))
        parts.append(f"{type(current).__module__}.{type(current).__qualname__}\n{frames}")
        current = current.__cause__ or current.__context__
    return "caused by ".join(parts)


def log_error(message: str, error: BaseException, *args) -> None:
    """Log [message] with [error]'s type and stack, never its text."""
    logger.error(message + "\n%s", *args, describe(error))


class SafeErrorMiddleware:
    """Unhandled errors become a plain 500, logged without their message."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def tracking_send(message):
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as error:  # noqa: BLE001 - the last line of defence
            log_error(
                "unhandled %s on %s %s",
                error,
                type(error).__name__,
                scope.get("method"),
                scope.get("path"),
            )
            if not started:
                response = JSONResponse({"detail": "Internal server error"}, status_code=500)
                await response(scope, receive, send)
