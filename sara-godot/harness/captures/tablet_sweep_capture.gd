## What a scenario can do to the sweep dialog, out of `tablet_sweep_dialog.gd`
## because nothing in it runs while a painter uses the dialog. The vocabulary,
## all under `{"sweep": ...}`:
##
## - `{"strip": 0, "shape": 2.0, "part": 1.0}` sweeps a block from the dot,
##   scratching its coat or, in Try It, painting over it. *shape* is the
##   exponent of the faked hand, the pressure runs from *first* to *peak*, 0 and
##   1 unless named, *lift* drops it to nought at the far end as a slow hand
##   lifts in place, *wobble* sways the pen that many pixels off the middle, and
##   *part* under one leaves the sweep open for a mid-sweep capture.
## - `{"test": true}` moves on to Try It, `{"restart": true}` starts over.
## - `{"size": [420, 520]}` resizes the dialog, for a capture at its floor.
## - `{"report": "smallest"}` writes where each band landed and whether the
##   content fits to `sweep-geometry-smallest.txt` beside the shots, a file
##   because `sara_shot.py` keeps only printed lines that look like errors.
##
## A pen cannot be injected: an InputEventMouseMotion pushed at a strip never
## reaches its `gui_input`, so this starts where the recording starts. The
## dialog is reached untyped, because a cast to a script's own class inside its
## own static function leaves the script alive at exit.
@tool
class_name SaTabletSweepCapture
extends RefCounted


## Drives the sweep dialog: one `{"sweep": ...}` step against whatever sweep
## dialog is open.
static func run(tree: SceneTree, spec: Dictionary, out_dir: String = "") -> void:
    var node := tree.root.find_child("TabletSweepDialog", true, false)
    if node == null or not node.has_method("begin_sweep"):
        push_warning("SaCapture: no sweep dialog to scratch")
        return
    if bool(spec.get("restart", false)):
        node.restart()
        print("SaCapture: sweep restarted")
        return
    if bool(spec.get("test", false)):
        node.enter_test()
        print("SaCapture: sweep test pass")
        return
    if spec.has("size"):
        _resize(node, spec["size"] as Array)
        return
    if spec.has("report"):
        _report_geometry(node, String(spec["report"]), out_dir)
        return
    _scratch(node, spec)


static func _scratch(node: Node, spec: Dictionary) -> void:
    var index := int(spec.get("strip", 0))
    var shape := float(spec.get("shape", 2.0))
    var part := clampf(float(spec.get("part", 1.0)), 0.0, 1.0)
    var readings := int(spec.get("readings", 40))
    var first := float(spec.get("first", 0.0))
    var peak := float(spec.get("peak", 1.0))
    var wobble := float(spec.get("wobble", 0.0))
    var lift := bool(spec.get("lift", false))
    # At least one step between two readings, so a sweep of one reading or
    # none feeds nought and one rather than a division by nought.
    var last := maxi(readings - 1, 1)
    node.begin_sweep(index)
    var fed := maxi(int(round(float(readings) * part)), 2)
    for i in range(fed):
        var t := float(i) / float(last)
        var pressure := lerpf(first, peak, pow(t, shape))
        node.feed(index, t, pressure, sin(t * TAU * 1.5) * wobble)
    if lift and part >= 1.0:
        for i in range(1, 9):
            node.feed(index, 1.0, lerpf(peak, 0.0, float(i) / 8.0))
    if part >= 1.0:
        node.end_sweep(index)
    print("SaCapture: sweep strip %d, shape %.2f, %d%% of it" % [index, shape, int(round(part * 100.0))])


static func _resize(node: Node, wanted: Array) -> void:
    var window := node as Window
    if window == null or wanted == null or wanted.size() < 2:
        return
    window.size = Vector2i(int(wanted[0]), int(wanted[1]))
    print(
        (
            "SaCapture: sweep dialog sized to %d x %d, floor %d x %d"
            % [window.size.x, window.size.y, window.min_size.x, window.min_size.y]
        )
    )


## Where each band ended up, and whether the dialog still holds its content.
##
## A rotation and a fit are claims about geometry, and reading them back off
## the running dialog is the only proof of either that a screenshot cannot
## quietly disagree with. The heading is the unit vector the band's own left to
## right points along on screen, so (0, 1) is straight down and (0.71, -0.71)
## is the diagonal.
static func _report_geometry(node: Node, label: String, out_dir: String) -> void:
    var lines := PackedStringArray()
    for index in range(SaTabletSweep.SWEEP_COUNT):
        var slot := node.find_child("Strip%dSlot" % index, true, false) as Control
        var strip := node.find_child("Strip%d" % index, true, false) as Control
        if slot == null or strip == null:
            continue
        var heading := Vector2.RIGHT.rotated(strip.rotation)
        (
            lines
            . append(
                (
                    "strip %d  angle=%+.0fdeg  heading=(%+.2f, %+.2f)  band=%.0fx%.0f  slot=%.0fx%.0f at (%.0f, %.0f)"
                    % [
                        index,
                        strip.rotation_degrees,
                        heading.x,
                        heading.y,
                        strip.size.x,
                        strip.size.y,
                        slot.size.x,
                        slot.size.y,
                        slot.global_position.x,
                        slot.global_position.y,
                    ]
                )
            )
        )

    var window := node as Window
    var margin := node.find_child("Margin", true, false) as Control
    var content_control := node.get("content") as Control
    if window != null and margin != null and content_control != null:
        var needed := margin.get_combined_minimum_size()
        var room := content_control.size
        (
            lines
            . append(
                (
                    "dialog %dx%d  floor %dx%d  content %.0fx%.0f  content needs %.0fx%.0f  fits=%s"
                    % [
                        window.size.x,
                        window.size.y,
                        window.min_size.x,
                        window.min_size.y,
                        room.x,
                        room.y,
                        needed.x,
                        needed.y,
                        str(needed.x <= room.x and needed.y <= room.y),
                    ]
                )
            )
        )

    var text := "\n".join(lines)
    print("SaCapture: sweep geometry %s\n%s" % [label, text])
    if out_dir == "":
        return
    var file := FileAccess.open(out_dir.path_join("sweep-geometry-%s.txt" % label), FileAccess.WRITE)
    if file == null:
        push_warning("SaCapture: could not write the sweep geometry beside the shots")
        return
    file.store_string(text + "\n")
