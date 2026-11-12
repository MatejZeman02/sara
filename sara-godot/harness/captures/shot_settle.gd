## What a shot waits for before it draws: every layer thumbnail, every Brush
## Presets tile and a fold the main canvas owes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `SaCaptureRun.shoot` for the reason `SaLayerListCapture` is out of the
## layers list: the run owns where a shot lands and what is left to do, and what
## the docks need settled before they can be photographed is theirs to say. It
## is the one place the next picture that fills in over time gets added to.
##
## **A layer thumbnail** redraws at most every quarter second of wall clock, so a
## shot a `wait` after a stroke caught the active layer's picture with the stroke
## in one run and without it in the next. `SaLayerList.settle_thumbnails` is the
## list's own door for that.
##
## **A Brush Presets tile** is the same race. A scenario runs on a fresh
## profile, where no preset picture is cached, and the chooser draws its queue a
## slice of a frame so a cold start keeps its rate. How far the queue has got at
## a `shot` depends on how fast the frames come, so one shot can show a tile
## empty in one take and drawn in the next. The drain
## is the chooser's own `capture_finish`, which the menu driver's
## `preset_chooser` step already calls, and the harness only asks for it here.
##
## **The scan comes first.** A boot holds the preset store unread until a few
## frames after the window is up, so a shot in those frames finds a docker with
## no tile to draw a picture on. `scan` reads the store at once, once, and does
## nothing when it was released already.
##
## **An owed fold** is paid over the frames after its step, so a shot waits up
## to [member owed_frames_bound] frames for it, then is taken and says so.
class_name SaShotSettle
extends RefCounted

## Four seconds at low-processor mode's 144 frames a second. A suite dials it.
static var owed_frames_bound := 600
## The log line of the last shot taken with a fold owed, which a suite reads.
static var last_owed_line := ""
static var _owed_frames := 0


## Settles everything under *root* that fills in over time, the dockers that are
## windows of their own included. Answers whether it had to read the preset
## store, because the cells that builds are laid out at the end of the frame and
## `force_draw` runs before that: the shot has to be asked for again a frame
## later, which `SaCaptureRun.shoot` does. A layer thumbnail whose redraw is still
## queued is the same case, and after a crop it would be a white square in the
## shot.
static func settle(root: Node, label: String = "") -> bool:
    if root == null:
        return false
    var scanned := false
    var presets := ToolOptionsPresets.in_tree(root)
    if presets != null and presets.scan_held:
        presets.scan()
        scanned = true
    for found: Node in root.find_children("*", "SaBrushPresetsChooser", true, false):
        (found as SaBrushPresetsChooser).capture_finish()
    return _fold_owed(label) or SaLayerList.settle_thumbnails(root) or scanned


## Whether the shot waits a frame for the fold the front document owes.
##
## The front surface's rather than the canvas in *root*'s window, because the
## shot shows the document the painter is working on and that is the one whose
## fold is owed. Every tab will stand in the root window, so the window picks
## no document out.
static func _fold_owed(label: String) -> bool:
    var canvas := SaCanvasView.front_canvas()
    var document := canvas.document if canvas != null else null
    var owed := document != null and document.fold != null and document.fold.debt.is_owed()
    _owed_frames = _owed_frames + 1 if owed else 0
    if not owed or _owed_frames <= owed_frames_bound:
        return owed
    last_owed_line = "SaCapture: shot %s taken with a fold owed, after %d frames" % [label, owed_frames_bound]
    print(last_owed_line)
    _owed_frames = 0
    return false
