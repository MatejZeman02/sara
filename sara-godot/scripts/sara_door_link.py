"""The connection `sara_door.py` holds to Sara's door, HTTP/1.1 on one socket.

The door answers `POST /step` on the Unix socket and on the loopback port
alike, the token in `Authorization: Bearer` on both. This is
the client end of that wire and nothing else: `http.client` over `AF_UNIX`
through `UnixConnection`, over TCP as it ships, and `DoorLink`, which keeps one
connection open for a session and posts a step or a batch on it. What an
answer means, its `printed` and its findings, stays with `SaraDoor`.
"""

from __future__ import annotations

import http.client
import json
import socket

## How long one step may take before the client gives up on the answer. A load
## or an export is seconds, so this is generous rather than tight.
REPLY_TIMEOUT_S = 120
## The only address the TCP way in listens on, and so the only one to connect to.
LOOPBACK = "127.0.0.1"


class DoorError(RuntimeError):
    """The session could not be opened, or died with a step outstanding."""


class UnixConnection(http.client.HTTPConnection):
    """`http.client` over a Unix socket. The host is only what the `Host`
    header says, and the connect opens `AF_UNIX` on the socket's path."""

    def __init__(self, socket_path: str, timeout: float = REPLY_TIMEOUT_S) -> None:
        super().__init__("sara", timeout=timeout)
        self.socket_path = socket_path

    def connect(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(self.socket_path)
        except OSError:
            sock.close()
            raise
        self.sock = sock


class DoorLink:
    """One HTTP connection to the door, kept open for the whole session, and
    the token every request carries in its `Authorization` header. A step is
    posted as a JSON object and answered by one, a batch as an array and
    answered by an array."""

    def __init__(self, conn: http.client.HTTPConnection, token: str) -> None:
        self.conn = conn
        self.token = token

    @classmethod
    def unix(cls, socket_path: str, token: str) -> "DoorLink":
        return cls(UnixConnection(socket_path), token)

    @classmethod
    def tcp(cls, port: int, token: str) -> "DoorLink":
        return cls(http.client.HTTPConnection(LOOPBACK, port, timeout=REPLY_TIMEOUT_S), token)

    def open(self) -> "DoorLink":
        """Connects now rather than on the first request, so a door that is not
        listening yet says so to the caller waiting for it."""
        self.conn.connect()
        return self

    def post(self, body: dict | list) -> dict | list:
        """Posts *body* to `/step` and answers the door's JSON, raising
        `DoorError` for a connection that went or for any status but 200."""
        headers = {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"}
        try:
            self.conn.request("POST", "/step", body=json.dumps(body).encode(), headers=headers)
            response = self.conn.getresponse()
            data = response.read()
        except (http.client.HTTPException, OSError) as failed:
            raise DoorError(f"Sara closed the connection with a step outstanding ({failed!r})") from None
        try:
            answer = json.loads(data.decode())
        except ValueError:
            raise DoorError(f"the door answered {response.status} with no JSON: {data[:200]!r}") from None
        if response.status != 200:
            said = answer.get("error") if isinstance(answer, dict) else answer
            raise DoorError(f"the door answered {response.status}: {said}")
        return answer

    def close(self) -> None:
        self.conn.close()
