# The record pictures

One folder per scenario, and inside it one variant folder per GPU, named after
the GPU the pictures were drawn on, as `rtx-3090` or `rtx-3070-laptop`. A
variant holds one picture per `shot` step, named after it, and a
`record.json`. They are read by `scripts/shot_diff.py`, by
`scripts/check_shots.py` and by `scripts/test_shot_diff.py`, and by nothing
inside the app: the `.gdignore` beside this file keeps Godot from importing
them, because a record is a file on disk rather than a resource.

To read a fresh run against this machine's variant:

```bash
.conda/bin/python scripts/sara_shot.py --scenario scenarios/<name>.json --out /tmp/<name>
python scripts/shot_diff.py /tmp/<name> tests/shots/<name>/<variant>
```

Each `record.json` names the GPU, the display the recording found and the
commit:

```json
{"gpu": "NVIDIA GeForce RTX 3090", "display": {"resolution": "1280x1024", "aspect": "5:4"}, "taken": "1b85e1393", "repeats": true}
```

`check_shots.py`, the gate line that takes every scenario again, runs a
scenario only against the variant whose GPU this machine has, because another
GPU draws a text edge a level differently. The display is there for the reader
and is never matched: `sara_shot.py` draws offscreen in a headless weston at
the scenario's own size, with the interface scale and the layout pinned, so the
monitor never changes a picture. A scenario with no variant for this machine's
GPU prints a `REQUEST` line, which does not fail the run.

To record this machine's variant, of every scenario that lacks one or of those
named:

```bash
python scripts/check_shots.py --record [scenario ...]
python scripts/check_shots.py --record --all     # retake every scenario here
```

It runs the scenario twice, compares the two runs against each other first, and
copies one in only if they agree. A record taken from a scenario that does not
repeat is worse than no record: it fails for everyone with that GPU, forever.
A shot that never repeats is named in the variant's `"leaves_out"` and is left
out of every later recording too, as the README of the Info docker scenario explains.
