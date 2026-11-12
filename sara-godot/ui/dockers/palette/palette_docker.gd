## The pop-up palette: the ten brush slots on a ring around the colour wheel,
## summoned under the pointer by its chord and gone when the pointer leaves.
##
## A docker registered like every other, on
## `DockerLayoutStore.HIDDEN_UNTIL_ASKED` so no profile opens it, and shown on
## its summon, Alt+Shift+W, and the Window menu like any docker. **It is special only
## in what it draws.** A docker rather than a widget with its own show and hide,
## which would need a second copy of the borrow, the leave and the chord.
##
## **A right click with a brush opens it** under the pointer when the painter
## chose it over Brush Presets on Preferences > Brushes, which
## `SaRightClickDocker` reads, and a second right click sends it back. It has no
## on and off switch, since a right click has to open one of the two and the
## choice says which.
##
## **The brush HUD sits under the ring**, `PaletteBrushHud`, the shown tool's
## Radius, Opacity and Flow. The docker is taller by the HUD's height, so the
## ring keeps the size its names are fitted to.
@tool
extends DockerWindow

class_name PaletteDocker

## What the HUD under the ring adds to the docker's height, its two rows and
## the column's gap above it, read off the running app's state dump.
const HUD_HEIGHT: int = 64

## What the docker opens at. Near square under the drag bar, because the ring
## is a circle and the shorter side is the one it is laid out to: the drag bar,
## the column's gap and the docker's foot take 53 of the height and the HUD
## [constant HUD_HEIGHT], so the ring is 360 by 331, which is the size its names
## are fitted to.
const DEFAULT_SIZE := Vector2i(360, 384 + HUD_HEIGHT)

## The ring of slots with the wheel inside it.
var ring: PaletteSlotRing

## The shown tool's Radius, Opacity and Flow, under the ring.
var hud: PaletteBrushHud

## The frame a right click with a brush opened this docker on, so the host's
## copy of that same press does not send it back.
var _opened_on_frame: int = -1

## True while this docker is the one telling the store about a colour, so the
## store's echo does not move the wheel under the gesture that moved it.
var _ignore_signal: bool = false


func _init() -> void:
    _init_docker(SaDockerIds.PALETTE, "Pop-up Palette", DEFAULT_SIZE, Vector2i(240, 260))
    # Where the Window menu opens it under a layout with no section for it, over
    # the middle of the canvas rather than over the menus. Every shipped layout
    # gives it a place clear of the other dockers, and a summon puts it under
    # the pointer and writes nothing.
    position = Vector2i(780, 340)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Pop-up Palette")
    vbox.add_child(drag_handle)

    ring = PaletteSlotRing.new(SaBrushSlotCommands.select)
    vbox.add_child(ring)
    ring.wheel.color_changed.connect(_on_wheel_color_changed)
    ring.wheel.color_committed.connect(_on_wheel_color_committed)
    hud = PaletteBrushHud.new()
    vbox.add_child(hud)
    _connect_once(SaSettings.changed, _on_setting_changed)
    # Here rather than in `_ready`, so a docker a suite shows outside a tree
    # catches up as the app's does.
    _connect_once(visibility_changed, _on_visibility_changed)


func _ready() -> void:
    _setup_docker_ready()
    SaUI.apply_ui_theme(ring)
    SaUI.apply_ui_theme(hud)
    _connect_once(EventBus.color_picked, _on_event_color_picked)
    _connect_once(visibility_changed, _on_visibility_changed)
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()
    _catch_up()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.PALETTE)


func _enter_tree() -> void:
    SaRightClickDocker.attach(SaRightClickDocker.PALETTE, toggle_at)
    _connect_once(window_input, _on_window_input)
    var host := get_parent().get_window() if get_parent() != null else null
    if host != null:
        _connect_once(host.window_input, _on_host_input)


func _exit_tree() -> void:
    SaRightClickDocker.detach(SaRightClickDocker.PALETTE, self)
    var host := get_parent().get_window() if get_parent() != null else null
    if host != null and host.window_input.is_connected(_on_host_input):
        host.window_input.disconnect(_on_host_input)


## Summons this docker centred on *point* when it is closed and sends it back
## when it is out, which a right click with a brush asks through
## `SaRightClickDocker`, and answers whether it did either. *point* is in the
## host window's visible space, as `SaCursorPolicy.pointer_in_window` gives it.
##
## Centred under the pointer as its chord shows it, because the ring is picked
## by moving out from its middle, unlike Brush Presets, which opens beside the
## pointer. So the second right click lands on the palette rather than the
## canvas, and [method _on_host_input] takes it there.
##
## With no docker manager, which is every suite that builds this docker on its
## own, it shows or hides itself in place.
func toggle_at(point: Vector2, dockers: MainDockers = null) -> bool:
    if dockers == null:
        dockers = _docker_manager()
    if dockers == null:
        if not visible:
            position = Vector2i(point - Vector2(size) * 0.5)
        visible = not visible
        return true
    var section := String(SaDockerIds.PALETTE)
    if dockers.summon.is_summoned(self):
        dockers.summon.send_back(section)
        return not dockers.layout_store.is_borrowed(section)
    var centre := point
    var host := get_parent().get_window() if get_parent() != null else null
    var seen := SaCursorPolicy.rect_in(host, self) if host != null and not is_embedded() else Rect2()
    if seen.has_area():
        centre = Vector2(position) + (point - seen.position) * Vector2(size) / seen.size
    _opened_on_frame = Engine.get_process_frames()
    dockers.summon_docker_by_id(SaDockerIds.PALETTE, false, Vector2i(centre))
    return dockers.layout_store.is_borrowed(section)


## A right press on the palette while it is out on a summon sends it back, as
## the right click that opened it would on the canvas. Unmodified only, because
## the Alt right drag that resizes a docker is the drag handle's.
##
## **Heard at the host window, for an embedded palette.** A summon leaves the
## subwindow focus where it was, and Godot hands a right press to the focused
## subwindow alone, so the palette's own input never sees it. The host's
## `window_input` sees every press first, as `MainCanvas` and `MainDockers` hear
## it there.
##
## **Sent back a frame later**, because the canvas hears the same press on the
## same signal and asks whether a docker covers the point. Gone already, the
## palette would leave the press to the canvas, whose tool would open it again.
## And the press that opened it is passed over, since the canvas may hear it
## first and the palette then finds itself under its own opening press.
func _on_host_input(raw: InputEvent) -> void:
    var host := get_parent().get_window() if get_parent() != null else null
    if host == null or not is_embedded() or not visible or not _is_plain_right_press(raw):
        return
    var at: Vector2 = host.get_final_transform().affine_inverse() * (raw as InputEventMouseButton).position
    if Rect2(Vector2(position), Vector2(size)).has_point(at) and Engine.get_process_frames() != _opened_on_frame:
        _send_back.call_deferred()


## The same press on a palette in a window of its own, which hears it itself.
func _on_window_input(event: InputEvent) -> void:
    if not is_embedded() and _is_plain_right_press(event):
        _send_back.call_deferred()


static func _is_plain_right_press(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
        return false
    return not (button.alt_pressed or button.ctrl_pressed or button.shift_pressed)


## Sends this docker back when it is still out on a summon, and leaves a
## docker the painter opened from the Window menu where it is.
func _send_back() -> void:
    var dockers := _docker_manager()
    if dockers != null and dockers.summon.is_summoned(self):
        dockers.summon.send_back(String(SaDockerIds.PALETTE))


## The main scene's docker manager, or null in a host that has none.
func _docker_manager() -> MainDockers:
    var tree := get_tree() if is_inside_tree() else null
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("dockers" in main_node):
        return null
    return main_node.dockers as MainDockers


## Whether Escape sends this docker back while it is out on a summon, which
## `ShortcutRouter` asks: always, because on a summon the palette is a pop-up and
## hides on Escape as the choice popups do. Opened from the Window menu it is a
## docker, and Escape closes no docker. Named for this door alone, for the reason
## a docker's method on the summon's path has: `has_method` is how the router
## finds it, and a common name would answer for classes that never meant to.
func goes_back_on_escape() -> bool:
    return true


## The ring and the wheel as they stand, for the state dump. Empty when the
## docker is not built.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script.
static func capture_state(root: Window) -> Dictionary:
    var docker: Variant = root.find_child(SaDockerIds.PALETTE, true, false)
    if docker == null:
        return {}
    var win := docker as Window
    var shown: Variant = docker.get("ring")
    var out := {
        "visible": win.visible,
        "position": [win.position.x, win.position.y],
        "size": [win.size.x, win.size.y],
    }
    if shown != null:
        out.merge((shown as Object).call("report", Vector2(win.position)))
    var hud_shown: Variant = docker.get("hud")
    if hud_shown != null:
        out["hud"] = (hud_shown as Object).call("report", Vector2(win.position))
    return out


## Brings the names, the wheel and the HUD up to date, which a hidden docker
## skips: it follows the slots, the colour and the tool only while it can be
## seen, and catches up each time it is shown.
func _catch_up() -> void:
    ring.refresh()
    hud.refresh()
    _ignore_signal = true
    ring.wheel.set_from_color(SaColors.foreground)
    _ignore_signal = false


func _on_visibility_changed() -> void:
    if visible:
        _catch_up()


func _on_setting_changed(property: StringName) -> void:
    if property == &"brush_slots":
        ring.refresh()


func _on_wheel_color_changed(new_color: Color) -> void:
    if _ignore_signal:
        return
    _ignore_signal = true
    EventBus.color_picked.emit(new_color)
    _ignore_signal = false


func _on_wheel_color_committed(new_color: Color) -> void:
    SaColors.note_used(new_color)


func _on_event_color_picked(picked_color: Color) -> void:
    if _ignore_signal or not visible:
        return
    if ring.wheel.color().is_equal_approx(picked_color):
        return
    _ignore_signal = true
    ring.wheel.set_from_color(picked_color)
    _ignore_signal = false


static func _connect_once(sig: Signal, callable: Callable) -> void:
    if not sig.is_connected(callable):
        sig.connect(callable)
