"""A look at the running app: a door Sara made to hold a frame prints its hitch or stall line with the main
thread's time on a core, and the whole process's, read by the trail's watcher thread.

    cd sara-godot
    python scenarios/a-hitch-or-a-stall-line-in-sara-s-log-says-whether-sara-had-a-core.py <out>

A large canvas filled and dumped holds the main thread past a tenth of a second, which is a hitch or a stall
in Sara's own work, so its line should read most of the frame on a core. `lines.txt` holds every `Sara hitch:`
and `Sara stall:` line the session printed.
"""
import sys
from pathlib import Path

sys.path.insert(0, "scripts")
from sara_door import SaraDoor  # noqa: E402

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
lines: list[str] = []
with SaraDoor(out_dir=out / "door") as door:
    def send(step: dict, dump: bool = False) -> dict:
        answer = door.send(step, dump=dump)
        lines.extend(line for line in answer.get("printed", []) if line.startswith(("Sara hitch:", "Sara stall:")))
        return answer

    send({"wait": 60})
    send({"canvas": [6144, 6144]})
    send({"fill": [0.6, 0.3, 0.2]})
    send({"wait": 30})
    send({"wait": 1}, dump=True)
    send({"wait": 30})
(out / "lines.txt").write_text("".join(line + "\n" for line in lines), encoding="utf-8")
print("".join(line + "\n" for line in lines) or "no hitch or stall line")
