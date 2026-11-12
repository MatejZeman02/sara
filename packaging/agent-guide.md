# Driving Sara from a coding agent

This page travels with Sara's build as `AGENTS.md`, beside the program, so a
coding agent opened in this folder reads it without being told. It is all an
agent needs to paint in Sara, with nothing but a shell and `curl`: no
repository, no Python, no server of its own.

If you have a Python with numpy, `sara.py` sits beside the program, and
`import sara` then `sara.connect()` attaches to a Sara with its door open. It is
also a download of its own, `sara-python-...zip`. Python is not shipped.

Sara listens for steps on a door, a small HTTP server bound to 127.0.0.1 and
no other address, with a token in a file only you can read. A step is one JSON
object, `{"zoom": 2.0}` or a stroke, posted to `/step`, and the answer is one
JSON object saying what the step did. **Ask the door for its steps** before
anything else: it lists every step kind it knows, and describes each one
whole when asked by name. A `GET` on the door's root, or any request it
cannot run, says the same.

## Linux

Start Sara from the folder you unpacked it into, with its door open and its
shots going to `shots` beside it, and wait for it to say where the door is. A
Sara whose door listens writes the port and the token to `door.json` in its
user folder, and removes the file when it closes:

```bash
./sara.x86_64 -- --agent-door --capture-out="$PWD/shots" > sara.log 2>&1 &
DOOR_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Sara/door.json"
until [ -f "$DOOR_FILE" ]; do sleep 1; done
```

Read the port and the token out of the file, and define `door`, one POST of
its argument to `/step`. Every call below is `door` and a JSON body:

```bash
PORT=$(sed -n 's/.*"port": *\([0-9]*\).*/\1/p' "$DOOR_FILE")
TOKEN=$(sed -n 's/.*"token": *"\([^"]*\)".*/\1/p' "$DOOR_FILE")
door() { curl -sS -H "Authorization: Bearer $TOKEN" --data-binary "$1" "http://127.0.0.1:$PORT/step"; }
```

Ask the door for its steps, the ones to paint with whole and every other kind
by one line, then one kind with its whole description:

```bash
door '{"steps": true}'
door '{"steps": "stroke"}'
```

The answer is under ten thousand characters. Its `start` holds the kinds a
painting needs first, `stroke`, `colour`, `layer`, `look` and the rest, each
with a `name`, a `description` and an `inputSchema` that names the keys its
argument takes, the fields of an MCP tool. Its `steps` holds every other kind
by its name and one line, and `{"steps": "<name>"}` gives one of them whole.
A request the door cannot run, a body that is not
JSON, a kind it does not know or an argument of the wrong shape, answers
`ok: false` with a `help` field that names these two requests, and a guessed
kind with the kinds closest to it:

```bash
door '{"strok": {"from": [420, 400], "to": [1120, 400]}}'
```

Paint, look, and close:

```bash
door '{"stroke": {"from": [420, 400], "to": [1120, 400], "pressure": 1.0}}'
door '{"shot": "first-stroke"}'
door '{"quit": true}'
```

The answer to a shot names the PNG under `shot`, in the folder
`--capture-out` gave. Without that flag it names a `user://` path, which is
the folder `door.json` sits in.

To paint fast, send strokes as an array, each with its own `colour`. An array
of steps posted as one request runs them in order and answers an array of
answers, so it saves the round trips, and a stroke's `colour` (a hex code or
channels, as the `colour` step takes) is set before its press in the frame its
step runs, so a stroke in a new colour is one step and not two. The array does
not save frames: a stroke takes a frame for every waypoint, and about six more
for its press, its release and its settle, so count a frame for every
waypoint when planning a long piece:

```bash
door '[{"stroke": {"from": [420, 400], "to": [1120, 400], "colour": "#c04020"}},
       {"stroke": {"from": [420, 460], "to": [1120, 460], "colour": "#2040c0"}}]'
```

## Windows

These commands ran on a Windows machine on 2026-09-29, in Windows PowerShell
5.1 with `curl.exe` 8.21.0, and each was met.

Start Sara with `sara-with-door.cmd`, beside `sara.exe`, or in PowerShell with
its shots going to `shots` beside it:

```powershell
Start-Process .\sara.exe -ArgumentList '--', '--agent-door', "--capture-out=$PWD\shots"
$doorFile = "$env:APPDATA\Godot\app_userdata\Sara\door.json"
while (-not (Test-Path $doorFile)) { Start-Sleep 1 }
$door = Get-Content $doorFile | ConvertFrom-Json
```

Use `curl.exe` by its full name, since PowerShell's `curl` is another program,
and send the body from a file, since Windows PowerShell 5.1 strips the double
quotes out of a JSON argument it hands a program:

```powershell
'{"steps": true}' | Set-Content -Encoding ascii step.json
curl.exe -sS -H "Authorization: Bearer $($door.token)" --data-binary "@step.json" "http://127.0.0.1:$($door.port)/step"
```

## What an answer says

Every answer carries `ok`, the `verdicts` the step printed, `errors` and
`warnings` it raised, and `view`, one line on where the document sits in the
window. A step that went wrong says so in `errors` rather than failing the
request, so read them after every step. While a dialog stands over the
canvas every answer carries `dialogs` as well, each with its `title`, and a
question its `buttons`, the `step` that answers it and the button that step
`presses`. `{"state": "name", "dump": true}`
answers the whole state of the document as well, which is long, and
`{"errors": {"level": "warning"}}` lists every error of the session.

The door serves one client at a time. A Sara started with `--agent-door`
stays open when a client hangs up, for the next one, and closes at
`{"quit": true}`. `{"ping": true}` keeps a quiet session from timing out.
