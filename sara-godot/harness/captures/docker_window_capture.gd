## The `hide` and `docker_corners` steps and the state report's `docker_grips`: what
## the docker windows draw, read the way a painter would meet it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The three steps and the helpers only they reach lived in `docker_window.gd`,
## about 330 lines nothing but a scenario calls, and came here so that every
## docker's base class has lines to give. The class reads a docker
## through the public statics of `DockerWindow` and through the properties each
## one carries, and a docker is recognised by the method `apply_hide_button`
## rather than by a cast, which in a static function leaks the script.
class_name SaDockerWindowCapture
extends RefCounted


## Presses a hide button: lists them with `{"hide": ""}`, and clicks the one on
## the docker with that title with `{"hide": "Layers"}`.
##
## **The maximise button is on the same line**, because the two are one piece of
## chrome to a painter and a shot of a drag bar cannot say which of the two
## icons is which. The word after it says whether that docker is filling its
## host, which is the state the chord toggles and the one a screenshot of a
## docker the size of the window cannot be told from a docker somebody dragged
## that large.
##
## The walk is untyped on purpose: a cast to the docker's own `class_name` inside
## a static function leaks the script and its live objects, so a docker is recognised by the method it carries.
static func capture_hide(tree: SceneTree, raw: Variant) -> String:
    var wanted := String(raw)
    var switch_state := "on" if SaSettings.docker_hide_button else "off"
    var lines: Array[String] = ["SaCapture: docker hide buttons, the switch is %s" % switch_state]
    var target_at := Vector2.ZERO
    var found_target := false

    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("apply_hide_button"):
            continue
        var window := node as Window
        var button := node.get("hide_button") as Button
        var where := "no button"
        if button != null:
            # An embedded docker measures its controls from its own corner, so
            # the window's position is what puts the point in the root's units.
            var local := button.get_global_rect()
            var centre := Vector2(window.position) + local.get_center()
            # The block reports the whole rect against the docker's own, not the
            # centre alone. A centre inside a docker whose button hangs over the
            # edge reads as correct, which is how a clipped button was measured
            # as a number 37 units out rather than as a button drawn nowhere.
            var docker_rect := Rect2(Vector2.ZERO, Vector2(window.size))
            var inside := docker_rect.encloses(local)
            where = (
                "%s at (%4d, %4d) rect (%4d, %3d, %3d, %2d) in a docker %3d wide, column wants %3d, %s"
                % [
                    "shown" if button.visible else "hidden",
                    centre.x,
                    centre.y,
                    local.position.x,
                    local.position.y,
                    local.size.x,
                    local.size.y,
                    window.size.x,
                    DockerWindow.column_min_width(window),
                    "inside" if inside else "OUTSIDE",
                ]
            )
            if wanted != "" and window.title == wanted:
                target_at = centre
                found_target = true
        var maximise := node.get("maximise_button") as Button
        var maximise_state := "no maximise button"
        if maximise != null:
            maximise_state = "maximise %s" % ("shown" if maximise.visible else "hidden")
            if SaDockerMaximise.is_maximised(window):
                maximise_state += ", filling its host"
        lines.append(
            "  %-16s docker %-6s  %s  %s" % [window.title, "open" if window.visible else "closed", where, maximise_state]
        )

    if wanted == "":
        return "\n".join(lines)
    if not found_target:
        lines.append("  no docker titled '%s' has a hide button" % wanted)
        return "\n".join(lines)
    _send_click(tree, target_at)
    lines.append("  clicked the hide button of '%s' at (%d, %d)" % [wanted, target_at.x, target_at.y])
    return "\n".join(lines)


## Every open docker's resize grip, and whatever a painter could press that is
## drawn underneath it.
##
## The grip is pinned to the window's bottom right corner and sits on top of
## whatever the content put there, so a press in that square resizes the window
## instead of doing what the control under it says. The layers docker was
## measured doing that and held the corner open with a spacer of its own, which
## left every other docker with the same trap.
##
## A control counts as pressable when it answers the mouse and is one of the
## kinds a painter clicks. The walk is untyped for the reason `capture_hide`
## gives: a cast to the docker's own `class_name` inside a static function leaks
## the script.
static func capture_grip_state(root: Window) -> Array:
    var out: Array = []
    for node in root.find_children("*", "Window", true, false):
        if not node.has_method("apply_hide_button"):
            continue
        var window := node as Window
        var grip := node.get("resizer") as Control
        var entry := {
            "docker": window.title,
            "open": window.visible,
            "size": {"x": float(window.size.x), "y": float(window.size.y)},
            "min_size": {"x": float(window.min_size.x), "y": float(window.min_size.y)},
            "grip": {},
            "column_wants": {"x": DockerWindow.column_min_width(window), "y": DockerWindow.column_min_height(window)},
            # What the column needs to show every row, reaching through a
            # scroll. `column_wants.y` is the column's own minimum and answers
            # 41 for a docker whose rows are all inside a `ScrollContainer`.
            "content_height": DockerWindow.column_content_height(window),
            "content_cap": DockerWindow.content_height_cap(window),
            "scrolls": DockerWindow.column_has_scroll(window),
            "cut_words": SaDockerFontGrowth.cut_words(window),
            "corner_control": {},
            "under_the_grip": [],
        }
        if grip != null and grip.visible:
            var grip_rect := grip.get_global_rect()
            entry["grip"] = {
                "x": grip_rect.position.x,
                "y": grip_rect.position.y,
                "w": grip_rect.size.x,
                "h": grip_rect.size.y,
            }
            var nearest := _corner_control(window)
            if nearest != null:
                var near := _drawn_rect_of(nearest)
                entry["corner_control"] = {
                    "name": String(nearest.name),
                    "x": near.position.x,
                    "y": near.position.y,
                    "w": near.size.x,
                    "h": near.size.y,
                }
            for control: Control in _pressable_under(window, grip_rect):
                var rect: Rect2 = control.get_global_rect()
                (
                    entry["under_the_grip"]
                    . append(
                        {
                            "name": String(control.name),
                            "x": rect.position.x,
                            "y": rect.position.y,
                            "w": rect.size.x,
                            "h": rect.size.y,
                        }
                    )
                )
        out.append(entry)
    return out


## Every control in *window* a painter could press whose rect meets *area*.
##
## `BaseButton`, `Range`, `LineEdit` and `ItemList` between them are everything
## a docker puts at the end of a row, and a control that ignores the mouse
## cannot be pressed however it is drawn.
static func _pressable_under(window: Window, area: Rect2) -> Array[Control]:
    var out: Array[Control] = []
    for node in window.find_children("*", "Control", true, false):
        var control := node as Control
        if control == null or not control.is_visible_in_tree():
            continue
        if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
            continue
        var pressable := control is BaseButton or control is Range or control is LineEdit or control is ItemList
        if pressable and _drawn_rect_of(control).intersects(area):
            out.append(control)
    return out


## The pressable control closest to the docker's bottom right corner, which is
## the one where a press has to open that button rather than start a window
## resize. A scenario reads its rect
## to know where to click, and the dump then says the click landed on it.
static func _corner_control(window: Window) -> Control:
    var best: Control = null
    var best_corner := -INF
    for control: Control in _pressable_under(window, Rect2(Vector2.ZERO, Vector2(window.size))):
        # A `ScrollContainer` puts its own scroll bar at the right edge of every
        # docker that has one, and it is bottom-rightmost in five of them. The
        # note is about a button, and a scenario that wants somewhere to click
        # wants the thing that answers a click with something it can read back.
        if control is Range and not control is SpinBox:
            continue
        var rect := _drawn_rect_of(control)
        var corner := rect.position.x + rect.size.x + rect.position.y + rect.size.y
        if corner > best_corner:
            best_corner = corner
            best = control
    return best


## What of *control* is actually on screen, which is its own rect cut down by
## every ancestor that clips.
##
## A row scrolled out of a `ScrollContainer` still reports a rect where it would
## have been drawn, and that rect can sit over the grip while the row itself is
## clipped away and cannot be pressed at all. Measuring the uncut rect said the
## Colour Picker and the History docker each still had a control under the grip
## when neither did.
static func _drawn_rect_of(control: Control) -> Rect2:
    var rect := control.get_global_rect()
    var parent := control.get_parent() as Control
    while parent != null:
        if parent.clip_contents:
            rect = rect.intersection(parent.get_global_rect())
        parent = parent.get_parent() as Control
    return rect


## One press and release at a point in the root window's logical units.
##
## Pre-multiplied by the root's final transform, because an event pushed in from
## a script is not scaled on the way in and a 2x display would otherwise halve
## every coordinate.
static func _send_click(tree: SceneTree, at: Vector2) -> void:
    var physical: Vector2 = tree.root.get_final_transform() * at
    var motion := InputEventMouseMotion.new()
    motion.position = physical
    motion.global_position = physical
    Input.parse_input_event(motion)
    for pressed: bool in [true, false]:
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = pressed
        click.position = physical
        click.global_position = physical
        Input.parse_input_event(click)


## Reads a docker's corners: what is drawn just outside each of the four, read
## off the viewport texel by texel, `{"docker_corners": "Colour Picker"}`.
##
## A rounded docker wants a corner with nothing creeping back behind it, and
## nothing else in a run can say whether that is true. A screenshot shows it to a person
## and a state dump carries geometry, not pixels, so the wedge a rounded radius
## leaves between the panel and the square window is invisible to every other
## check.
##
## **The diagonal out of a corner texel is entirely outside the panel**, for any
## radius over about two and a half: the corner texel sits `sqrt(2) * radius`
## from the arc's centre and the arc is `radius`, so no geometry is needed beyond
## saying so. Every texel along it therefore has to be whatever the docker is
## drawn over. The first texel that is not, walking back in, is the docker's own
## edge, and its colour is reported so a reader sees the rim.
##
## An empty name reads every docker. Only embedded dockers, because a docker in
## an OS window of its own is not in this image at all. The walk is untyped for
## the reason `capture_hide` gives: a cast to the docker's `class_name` inside a
## static function leaks the script.
static func capture_corners(tree: SceneTree, raw: Variant) -> String:
    var wanted := String(raw)
    var image := tree.root.get_texture().get_image() if tree.root != null else null
    if image == null:
        return "SaCapture: docker_corners has no viewport image to read"
    # An embedded window's geometry is in the root viewport's logical units and
    # the image is texels, so the factor is the root's own content scale. Reading
    # `SaUI.window_scale` here would answer 1.0 for every embedded docker and a
    # run at a UI scale of two would sample half the rectangle on screen.
    var factor: float = tree.root.content_scale_factor
    var lines: Array[String] = [
        "SaCapture: docker corners, viewport %d x %d at scale %.2f" % [image.get_width(), image.get_height(), factor]
    ]
    var seen := 0

    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("apply_hide_button"):
            continue
        var window := node as Window
        if not window.visible or not window.is_embedded():
            continue
        if wanted != "" and window.title != wanted:
            continue
        seen += 1
        lines.append_array(_corner_lines(window, image, factor))
    if seen == 0:
        return "SaCapture: docker_corners found no embedded docker called '%s'" % wanted
    return "\n".join(lines)


## How far out from a corner texel the walk goes, and how far out it samples the
## thing the docker is drawn over. Twelve is over twice the five-unit radius and
## twenty-four is well clear of the rounded silhouette at any scale this runs at.
const CORNER_WALK: int = 12
const CORNER_BEHIND: int = 24


static func _corner_lines(window: Window, image: Image, factor: float) -> Array[String]:
    var rect := Rect2i(Vector2i(Vector2(window.position) * factor), Vector2i(Vector2(window.size) * factor))
    var lines: Array[String] = [
        "  %-16s at (%4d, %4d) %3d x %3d texels" % [window.title, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
    ]
    var corners := {
        "top-left": [Vector2i(rect.position.x, rect.position.y), Vector2i(-1, -1)],
        "top-right": [Vector2i(rect.end.x - 1, rect.position.y), Vector2i(1, -1)],
        "bottom-left": [Vector2i(rect.position.x, rect.end.y - 1), Vector2i(-1, 1)],
        "bottom-right": [Vector2i(rect.end.x - 1, rect.end.y - 1), Vector2i(1, 1)],
    }
    for corner: String in corners:
        var at: Vector2i = corners[corner][0]
        var away: Vector2i = corners[corner][1]
        var behind := _texel(image, at + away * CORNER_BEHIND)
        var strays: Array[String] = []
        for step in range(CORNER_WALK, -1, -1):
            var texel := _texel(image, at + away * step)
            if not _alike(texel, behind):
                strays.append("%s at %d out" % [texel.to_html(false), step])
        var edge := "nothing"
        for step in range(1, CORNER_WALK + 1):
            var texel := _texel(image, at - away * step)
            if not _alike(texel, behind):
                edge = "%s at %d in" % [texel.to_html(false), step]
                break
        var verdict := "clean" if strays.is_empty() else "%d stray: %s" % [strays.size(), ", ".join(strays)]
        lines.append(
            (
                "    %-13s sits on %s, %2d texels out are it, edge %-14s %s"
                % [corner, behind.to_html(false), CORNER_WALK + 1, edge, verdict]
            )
        )
    return lines


## Whether two texels are the same colour to the eye. A fiftieth per channel,
## because a rounded edge is drawn antialiased and the texel either side of the
## curve is a blend rather than either colour.
static func _alike(texel: Color, against: Color) -> bool:
    return absf(texel.r - against.r) < 0.02 and absf(texel.g - against.g) < 0.02 and absf(texel.b - against.b) < 0.02


static func _texel(image: Image, at: Vector2i) -> Color:
    var x := clampi(at.x, 0, image.get_width() - 1)
    var y := clampi(at.y, 0, image.get_height() - 1)
    return image.get_pixel(x, y)
