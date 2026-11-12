## The Minimap docker: the whole picture small, with the part the view shows
## drawn over it, and a click that takes the view there.
##
## Shows the easel's composited output through a second Texture2DRD, no
## readback, with the main canvas's own display material, so the rolloff, the
## exposure, the heatmap and the display profile all read the same here as on
## the picture. The view rectangle comes from the main canvas's view through
## SaView.screen_to_document, so a rotated view draws as the tilted
## quadrilateral it is.
##
## The two flip buttons flip the view and nothing else. The document is
## untouched, so a flip costs no dispatch and no undo entry, and the map mirrors
## with the canvas so that what the painter clicks here is what is under the
## same place there.
@tool
extends DockerWindow

class_name MinimapDocker

## The window a profile with no layout opens, in logical pixels. As wide as the
## column the shipped layouts put the docker in, 310, because at 280 the proof
## row cut "Display encoding off" by nine pixels. 250 tall, so that the one row
## of controls and the drag bar leave a 16:9 picture the docker's whole width.
const DEFAULT_SIZE := Vector2i(310, 250)

## The command the proof switch shares with Ctrl+Shift+Y, read for its chord.
const PROOF_COMMAND := &"view_minimap_proof"

## The `view_mode` number `shaders/canvas/tonemap.gdshader` branches on for a
## soft proof, the number the canvas's Ctrl+Y notice recognises one by.
const SOFT_PROOF_VIEW_MODE: int = 3

## The main canvas, set by Main the way the Info docker's is.
var target_canvas: SaCanvas

## The view transforms, set by Main beside `target_canvas`. Needed because the
## minimap chooses its own mode rather than following the canvas's.
var view_transforms: SaViewTransformRegistry = null:
    set(value):
        if view_transforms != null and view_transforms.changed.is_connected(_invalidate_material):
            view_transforms.changed.disconnect(_invalidate_material)
        view_transforms = value
        if value != null and not value.changed.is_connected(_invalidate_material):
            value.changed.connect(_invalidate_material)
        _material_dirty = true

var _picture: TextureRect
var _overlay: Control
## What the outline was last drawn from, so a still view draws nothing.
var _shown_view: Array = []
var _bound_rid: RID = RID()
## The smallest interval between two flushes of the canvas's backlog, and when
## the last one was, in the ticks of `Time.get_ticks_msec`.
const FLUSH_SECONDS := 0.25
var _flushed_msec: int = -1000000

## The two mirror buttons, and what they last showed. Toggles rather than
## momentary buttons, because a mirrored view is easy to forget you asked for
## and the pressed pair is the only thing on screen that says so.
var _flip_row: HBoxContainer
## The row the proof's mode stands in. It is shown only while the proof is on,
## so that a docker with the proof off spends its height on the picture.
var _proof_row: HBoxContainer
## Whether the painter left the Proof element shown, read beside the proof
## state every time the rows are synced, for the reason `_gamut_row_wanted` is.
var _proof_row_wanted: bool = true
## The row each element of the Minimap's Preferences page shows, hides and
## orders, by the element's stored name. The drag handle and the resizer are
## the base layout's and stay out of it.
var _element_rows: Dictionary[String, Control] = {}
var _flip_h_button: Button
var _flip_v_button: Button
var _shown_flip: Vector2 = Vector2.ONE

## The minimap's own proof, off until asked for. Separate from the canvas's, so
## the map can be a values check while the painting stays in colour.
## Whether the minimap is showing its own proof rather than the canvas's view.
var proof_on: bool = false

## Which mode the proof shows, chosen here as well as in Preferences.
##
## The choice sits on the Display page under Proofs as well, where a painter
## who finds the toggle may never find the mode. One setting, two doors, and
## this one is beside the feature.
var _proof_option: SaChoiceButton = null
## The switch that turns the proof on, beside the mode it shows, so the proof
## needs no chord to turn on and the dropdown does not stand alone, where it
## reads as a blend mode.
var _proof_button: Button = null
var _proof_ids: Array[StringName] = []
var _shown_proof_mode: String = ""
## The gamut a soft proof clips to, under the mode while the proof is on and
## the mode is a soft proof. On the Display page alone it left a painter who
## turned the proof on seeing nothing change and finding nothing to choose.
## Bound to `SaSettings.proof_profile`, the setting that page and Ctrl+Y read,
## for the reason the mode's comment gives.
##
## **A row of its own, under the proof row rather than in it.** Beside the mode
## at the docker's 310 pixels both dropdowns got 115 where "Soft Proof" needs
## 120 and "Display P3" 124, so the row would have cut the two words it exists
## to show. The row is shown and hidden whole, and its label names the gamut
## the way the Display page does.
var _gamut_row: HBoxContainer = null
## Whether the painter left the Proof Gamut element shown. The row needs a soft
## proof as well, and this is read beside it every time the gamut row is
## synced, so a soft proof turned on never brings back a row the painter hid.
var _gamut_row_wanted: bool = true
var _gamut_option: SaChoiceButton = null
var _shown_gamut: String = ""
## The gamut row's entries and what a pick writes, the presets, the saved
## spaces and Custom..., shared with the Display page's Proof gamut.
var _gamut_choice: SaColorSpaceRow = null

## The copy of the canvas material this docker paints with while its proof is
## on, and whether it has to be taken again. The canvas rewrites its own
## material in place rather than replacing it, so there is nothing to compare
## against: the copy is refreshed when one of the things that rewrites it says
## so. A miss shows a stale exposure on a small picture and nothing worse,
## which is why this is a flag rather than a copy per frame.
var _own_material: ShaderMaterial = null
var _material_dirty: bool = true
var _copied_from: ShaderMaterial = null
var _applied_mode: StringName = &""


## The overlay, which draws the view's outline and takes the click. An inner
## class so its `_draw` can reach the docker's geometry.
class ViewOverlay:
    extends Control

    var docker: MinimapDocker

    func _draw() -> void:
        if docker != null:
            docker.draw_view(self)

    func _gui_input(event: InputEvent) -> void:
        if docker != null:
            docker.overlay_input(event)


func _init() -> void:
    _init_docker(SaDockerIds.MINIMAP, "Minimap", DEFAULT_SIZE, Vector2i(140, 120))
    # Where a fresh profile finds it: under the toolbox, out of the picture's
    # way, until the layout store has a place of its own for it.
    position = Vector2i(2, 720)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    # Horizontal, like every other docker's. The vertical form expands to fill
    # whatever height is going, and in a VBox beside the picture that is half
    # the docker: the title band was 113 pixels of the default 260 and the map
    # got what was left.
    drag_handle = DockerUtils.make_drag_bar("Minimap")
    vbox.add_child(drag_handle)

    # Under the drag bar rather than under the picture, because the docker's
    # resize grip owns the bottom right corner and a button that shares it is a
    # button nobody can press. One row for the two flips and the proof switch,
    # so the controls cost one band and the picture gets the rest.
    _flip_row = SaMake.row(vbox, "FlipRow")
    _flip_h_button = _make_flip_button(true, tr("Flip H"), tr("Flip the view left to right. The picture is not changed."))
    _flip_v_button = _make_flip_button(false, tr("Flip V"), tr("Flip the view top to bottom. The picture is not changed."))
    _build_proof_row(vbox)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _element_rows = {"Flip Buttons": _flip_row, "Proof": _proof_row, "Proof Gamut": _gamut_row, "Map": margin}

    _picture = TextureRect.new()
    _picture.name = "Picture"
    _picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(_picture)

    _overlay = ViewOverlay.new()
    _overlay.name = "ViewOverlay"
    _overlay.docker = self
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    # The rim is a polyline through the view's corners, and a view zoomed out
    # far enough puts those corners outside the map. Godot clips nothing by
    # default, so the orange line ran up the docker and over the drag bar. It is
    # not a z-order problem: reordering the tree would only move which edge it
    # spills over. Clipping the overlay to the
    # picture stops it on every side at once.
    _overlay.clip_contents = true
    _picture.add_child(_overlay)


## The proof switch at the end of the flip row, and under that row the mode it
## shows with the whole width, a row that is there only while the proof is on.
##
## A row of its own because beside the switch the mode got what Flip H and Flip
## V left, and "Lightness Check" read "Lightn…" at the default width. Hidden
## while the proof is off because nobody chooses a mode for a proof they have
## not turned on, and the row was 34 of the docker's 220 pixels.
##
## The mode choice itself:
## The same modes the Display page's Proofs section lists, out of the same
## registry, writing the same `SaSettings.minimap_proof_mode`. Built here rather
## than duplicated as a second setting, because two controls with two settings
## is how two controls come to disagree, and one setting behind two doors is the
## shape that cannot disagree with itself.
##
## The list is filled in `_sync_proof_option` rather than here: `view_transforms`
## is set by Main after the docker is built, and a module may register a mode
## later still, so a list built once is a list that is wrong by the time anybody
## opens the docker.
func _build_proof_row(parent: Node) -> void:
    var proof_row := SaMake.row(parent, "ProofRow")
    _proof_row = proof_row
    proof_row.visible = false
    _proof_button = SaMake.button(_flip_row, "ProofSwitch", tr("Proof"), "")
    _proof_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _proof_button.toggle_mode = true
    SaTheme.make_toggle(_proof_button)
    _proof_button.focus_mode = Control.FOCUS_NONE
    _proof_button.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    _proof_button.pressed.connect(toggle_proof)
    # Named again on every hover rather than once, so a chord rebound on the
    # Shortcuts page is the chord the tooltip says.
    _proof_button.mouse_entered.connect(_name_proof_chord)
    _name_proof_chord()

    _proof_option = SaMake.choice(proof_row, "ProofMode")
    _proof_option.focus_mode = Control.FOCUS_NONE
    _proof_option.tooltip_text = tr("How the minimap shows colours outside the proof gamut.")
    _proof_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The row is the docker's width and cannot grow, so a mode's name longer
    # than what Proof leaves goes onto a second line.
    _proof_option.wrap_its_words()
    _proof_option.choice_picked.connect(_on_proof_mode_selected)
    _build_gamut_row(parent)


## The Proof gamut row under the proof row, hidden until a soft proof is on.
## The list is the Display page's own, every gamut `SaSettings.DISPLAY_PROFILES`
## names, the proof's profile file, the saved spaces and Custom..., and
## `SaColorSpaceRow` lists it again when a space is saved.
func _build_gamut_row(parent: Node) -> void:
    _gamut_row = SaMake.row(parent, "GamutRow")
    _gamut_row.visible = false
    var tip := tr("The gamut Soft Proof (Ctrl+Y) checks against, set in Preferences > Canvas and colour.")
    var label := SaMake.label(_gamut_row, "GamutLabel", tr("Proof gamut"))
    label.mouse_filter = Control.MOUSE_FILTER_PASS
    label.tooltip_text = tip
    var gamuts: Array = []
    for profile_id: String in SaSettings.DISPLAY_PROFILES:
        gamuts.append({"id": profile_id, "label": tr(SaColorSpace.display_name(StringName(profile_id)))})
    gamuts.append({"id": SaSettingsValues.PROOF_PROFILE_FILE, "label": tr("Profile file")})
    var option := SaMake.choice(_gamut_row, "ProofGamut")
    _gamut_choice = SaColorSpaceRow.new(&"proof_profile", &"proof_custom_space", gamuts)
    _gamut_choice.show_on(option)
    option.focus_mode = Control.FOCUS_NONE
    option.tooltip_text = tip
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    option.choice_picked.connect(_on_gamut_selected)
    _gamut_option = option


## Writes the switch's tooltip with the chord the shortcut profile gives the
## same command, or without one when the profile gives it none.
func _name_proof_chord() -> void:
    var chords := SaShortcutStore.chords_for(PROOF_COMMAND)
    var tip := tr("Show the minimap in the proof mode beside this switch. The painting is not changed.")
    if not chords.is_empty():
        tip += " " + tr("%s does the same.") % chords[0]
    _proof_button.tooltip_text = tip


## Fills the dropdown from the registry and puts the setting's own mode on it.
##
## Polled beside the flip, and for the same reason: nothing announces a change
## to `SaSettings.minimap_proof_mode`, so a mode chosen on the Display page has
## to be read back rather than heard about. Cheap, because the list is only
## rebuilt when the registry's contents differ from what is on the control.
func _sync_proof_option() -> void:
    if _proof_option == null:
        return
    var wanted: Array[StringName] = []
    if view_transforms != null:
        for descriptor in view_transforms.list_modes():
            wanted.append(descriptor.id)
    if wanted != _proof_ids:
        _proof_ids = wanted
        var rows: Array = []
        for id in _proof_ids:
            var descriptor := view_transforms.get_descriptor(id)
            rows.append({"id": String(id), "label": tr(descriptor.display_name)})
        _proof_option.set_choices(rows)
        _shown_proof_mode = ""
    _sync_gamut_option()
    var wanted_mode := SaSettings.minimap_proof_mode
    if wanted_mode == _shown_proof_mode:
        return
    _shown_proof_mode = wanted_mode
    # A mode the registry does not offer leaves the button on what it showed,
    # which is `SaChoiceButton`'s own answer to a value no row stands for and
    # reads better than the blank an `OptionButton.select(-1)` drew. The setting
    # itself refuses such an id, so this is the second line of two.
    _proof_option.select_value(wanted_mode)


## Shows the mode's row while the proof is on and the painter left the Proof
## element shown. Polled with the gamut for the same reason.
func _sync_mode_row() -> void:
    if _proof_row == null:
        return
    var wanted := _proof_row_wanted and proof_on
    if _proof_row.visible != wanted:
        _proof_row.visible = wanted


## Shows the gamut's row while it means something, and puts the setting's
## own gamut on it. Polled with the mode for the mode's reason: Preferences
## writes `SaSettings.proof_profile` without telling this docker.
func _sync_gamut_option() -> void:
    _sync_mode_row()
    if _gamut_option == null:
        return
    var wanted := _gamut_row_wanted and proof_on and _shows_soft_proof()
    if _gamut_row.visible != wanted:
        _gamut_row.visible = wanted
    if _gamut_choice.chosen != _shown_gamut:
        _shown_gamut = _gamut_choice.chosen
        _gamut_option.select_value(_shown_gamut)


## Whether the mode the Minimap proof preference names is a soft proof, known
## by the shader's number the way the Ctrl+Y notice knows it, so a module's own
## proof against that branch has a gamut to choose as well.
func _shows_soft_proof() -> bool:
    var descriptor := _proof_descriptor()
    return descriptor != null and descriptor.view_mode == SOFT_PROOF_VIEW_MODE


## Writes the gamut and says what the proof does with it, because a proof of a
## document already inside the gamut changes nothing on the map and the line is
## the only sign the choice arrived.
func _on_gamut_selected(profile_id: Variant) -> void:
    _shown_gamut = _gamut_choice.take(String(profile_id))
    # Custom... left the control on its own entry, so it is put back on the
    # setting's while the dialog is open.
    _gamut_option.select_value(_shown_gamut)
    if String(profile_id) != SaColorSpaceRow.ASK_ID:
        _say_proof()


## Puts the soft proof's line in the canvas corner, the words Ctrl+Y says for
## the canvas.
func _say_proof() -> void:
    var descriptor := _proof_descriptor()
    if descriptor == null:
        return
    var document := _shown_document()
    var space := document.color_space if document != null else SaColorSpace.unspecified()
    var proof := SaSettings.proof_profile_space().gamut()
    SaMessage.notice(proof.proof_line(tr(descriptor.display_name), space.gamut(), SaSettings.DISPLAY_PROFILES))


## What the gamut dropdown is showing, for a state dump.
func _gamut_option_report() -> Dictionary:
    if _gamut_option == null:
        return {}
    var option := _gamut_option
    var picked: Variant = option.selected_value()
    var rect := option.get_global_rect()
    return {
        "visible": _gamut_row.visible,
        "selected": String(picked) if picked != null else "",
        "shown": option.text,
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
    }


## Writes the setting the Display page writes, which is the whole of what this
## control does. `_sync_material` reads it back off the setting every frame, so
## nothing here has to touch the material. A soft proof chosen while the proof
## is on says its line, as one switched on does.
func _on_proof_mode_selected(mode_id: Variant) -> void:
    SaSettings.minimap_proof_mode = String(mode_id)
    _sync_gamut_option()
    if proof_on and _shows_soft_proof():
        _say_proof()


## What the dropdown is showing, for a state dump. The selected id rather than
## the index, because an index means nothing once a module registers a mode.
func _proof_option_report() -> Dictionary:
    if _proof_option == null:
        return {}
    var picked: Variant = _proof_option.selected_value()
    var chosen := String(picked) if picked != null else ""
    return {
        "visible": _proof_option.visible,
        "selected": chosen,
        "shown": _proof_option.text,
        "items": _proof_ids.size(),
    }


## Reads or sets the Minimap proof: `{"minimap": {}}` reports the control,
## `{"minimap": {"proof": "lightness_check"}}` chooses that mode on it and
## `{"minimap": {"gamut": "display_p3"}}` that gamut on the gamut dropdown.
##
## The choice goes through `_on_proof_mode_selected`, which is the method the
## control's own `choice_picked` calls, so a scenario proves the control rather
## than the setting behind it. An injected click cannot do that here: the list
## is a window of its own and a click pushed in from a script does not route
## into one, which is the trap `SaCaptureMenus.click_select_item` already
## exists for on two other lists.
##
## Untyped walk, for the reason `SaCaptureDump._minimap_state` gives one line
## further on: a cast to a `class_name` in a static function leaks the script.
static func capture_proof(tree: SceneTree, raw: Variant) -> String:
    var spec := raw as Dictionary
    var node := tree.root.find_child(SaDockerIds.MINIMAP, true, false)
    if node == null or not node.has_method("choose_proof_mode"):
        return "SaCapture: no Minimap docker"
    var lines: Array[String] = []
    if spec != null and spec.has("proof"):
        var wanted := String(spec["proof"])
        var took: bool = node.call("choose_proof_mode", wanted)
        lines.append("SaCapture: minimap proof mode %s %s" % [wanted, "chosen" if took else "NOT OFFERED"])
    if spec != null and spec.has("gamut"):
        var gamut := String(spec["gamut"])
        var shown: bool = node.call("choose_proof_gamut", gamut)
        lines.append("SaCapture: minimap proof gamut %s %s" % [gamut, "chosen" if shown else "NOT SHOWN"])
    var report: Dictionary = node.call("flip_report")
    var gamut_report := report.get("proof_gamut", {}) as Dictionary
    (
        lines
        . append(
            (
                "SaCapture: minimap proof is %s, mode %s, the control shows '%s' of %d, gamut %s"
                % [
                    "on" if report.get("proof_on", false) else "off",
                    report.get("proof_mode", ""),
                    (report.get("proof_option", {}) as Dictionary).get("shown", ""),
                    int((report.get("proof_option", {}) as Dictionary).get("items", 0)),
                    "'%s'" % gamut_report.get("shown", "") if gamut_report.get("visible", false) else "hidden",
                ]
            )
        )
    )
    return "\n".join(lines)


## Picks *mode* on the docker's own dropdown, answering false when the registry
## does not offer it. Public because the capture door and a test both need the
## control's path rather than the setting's.
func choose_proof_mode(mode_id: String) -> bool:
    _sync_proof_option()
    if not _proof_ids.has(StringName(mode_id)):
        return false
    _proof_option.select_value(mode_id)
    _on_proof_mode_selected(mode_id)
    return true


## Picks *profile_id* on the gamut dropdown, answering false while the dropdown
## is hidden or offers no such gamut, so a scenario cannot choose what a painter
## could not.
func choose_proof_gamut(profile_id: String) -> bool:
    _sync_gamut_option()
    if not _gamut_row.visible or not _gamut_option.choice_values().has(profile_id):
        return false
    _gamut_option.select_value(profile_id)
    _on_gamut_selected(profile_id)
    return true


## One mirror button, added to the row and wired to *horizontal*.
func _make_flip_button(horizontal: bool, label: String, tip: String) -> Button:
    var button := SaMake.button(_flip_row, "FlipHorizontal" if horizontal else "FlipVertical", label, tip)
    button.toggle_mode = true
    SaTheme.make_toggle(button)
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.pressed.connect(_on_flip_pressed.bind(horizontal))
    return button


## Mirrors the view about the middle of the canvas. The pressed state is not set
## here: `_process` reads it back off the view, so a flip that arrives from
## anywhere else shows on the buttons too.
func _on_flip_pressed(horizontal: bool) -> void:
    if target_canvas == null or not is_instance_valid(target_canvas):
        return
    SaCanvasView.for_canvas(target_canvas).flip_view(horizontal)
    target_canvas.request_composite()


## Which way round the view is, and where the buttons are, for a capture. The
## rects are in the docker's own window, which is what `origin` in the dump is
## added to.
func flip_report() -> Dictionary:
    var flip := _view_flip()
    return {
        "horizontal": flip.x < 0.0,
        "vertical": flip.y < 0.0,
        "picture_flip_h": _picture.flip_h,
        "picture_flip_v": _picture.flip_v,
        "flip_h": _button_report(_flip_h_button),
        "flip_v": _button_report(_flip_v_button),
        "proof_on": proof_on,
        "proof_mode": SaSettings.minimap_proof_mode,
        "proof_option": _proof_option_report(),
        "proof_gamut": _gamut_option_report(),
        "proof_switch": _button_report(_proof_button),
        "hide_button": _hide_button_report(),
        "rows": _rows_report(),
    }


## Each element's row, whether it is drawn and its height, so a dump says what
## the Minimap's Preferences page left of the docker.
func _rows_report() -> Dictionary:
    var out := {}
    for element: String in _element_rows:
        var row := _element_rows[element]
        out[element] = {"visible": row.visible, "height": row.size.y}
    return out


## Where this docker's own hide button is drawn, against the docker.
##
## `SaDockerWindowCapture.capture_hide` measures the same thing for all ten dockers and
## prints it, and `scripts/sara_shot.py` forwards only error lines from the app's
## stdout, so the one docker the defect was about could not be read back from a
## dump. It reads back from this one now. The rect is the button's own, in the
## docker's coordinates the way `capture_hide` reports it, `docker_width` is the
## window it has to fit inside, and `inside` is the whole claim.
func _hide_button_report() -> Dictionary:
    var button := get("hide_button") as Button
    if button == null:
        return {}
    var rect := button.get_global_rect()
    return {
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "visible": button.visible,
        "docker_width": float(size.x),
        "column_wants": DockerWindow.column_min_width(self),
        "inside": Rect2(Vector2.ZERO, Vector2(size)).encloses(rect),
    }


## Where a mirror button is and whether it is showing pressed.
static func _button_report(button: Button) -> Dictionary:
    if button == null:
        return {}
    var rect := button.get_global_rect()
    return {
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "pressed": button.button_pressed,
    }


## The view's mirror, or none when there is no canvas to ask.
func _view_flip() -> Vector2:
    if target_canvas == null or not is_instance_valid(target_canvas):
        return Vector2.ONE
    return SaCanvasView.for_canvas(target_canvas).get_flip()


## Mirrors a document point the way the map is mirrored, so the outline and the
## click land where the picture actually shows that point. Its own inverse.
static func mirror_point(point: Vector2, document_size: Vector2i, flip: Vector2) -> Vector2:
    var out := point
    if flip.x < 0.0:
        out.x = float(document_size.x) - out.x
    if flip.y < 0.0:
        out.y = float(document_size.y) - out.y
    return out


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    # Everything that makes the canvas rebuild its own material. The signals are
    # the canvas's own list in `sync_tonemap`, so the copy follows it.
    for signal_name: String in ["tonemap_changed", "document_loaded"]:
        if not EventBus.is_connected(signal_name, _invalidate_material):
            EventBus.connect(signal_name, _invalidate_material)
    if not EventBus.document_color_space_changed.is_connected(_on_document_space_changed):
        EventBus.document_color_space_changed.connect(_on_document_space_changed)
    apply_layout_settings()


## Says the copy of the canvas material is out of date. Takes an argument
## because the three signals it answers each carry one, and none of them
## matters here.
func _invalidate_material(_arg: Variant = null) -> void:
    _material_dirty = true


## The copy follows the space of the document it shows and no other, so a
## document behind another tab changing its space leaves the copy as it is.
func _on_document_space_changed(changed: SaDocument) -> void:
    var shown := _shown_document()
    if shown == null or changed == shown:
        _invalidate_material()


## The document the map is a picture of, null while no canvas is set or the
## one set has gone.
func _shown_document() -> SaDocument:
    return target_canvas.document if is_instance_valid(target_canvas) else null


## Shows and orders the rows from the Minimap's Preferences page, under the
## drag handle. A hidden row leaves its commands working: Ctrl+Shift+Y still
## turns the proof on and the view's flip still mirrors the map, because the
## rows are a way to reach those settings and never the settings themselves.
## The map is the one row that expands, so it takes whatever height a hidden
## row leaves.
func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.MINIMAP)
    var column := _flip_row.get_parent()
    var at: int = drag_handle.get_index() + 1 if drag_handle != null and drag_handle.get_parent() == column else 0
    for element: String in SaSettings.get_layout_order(SaDockerIds.MINIMAP):
        var row: Control = _element_rows.get(element)
        if row == null:
            continue
        column.move_child(row, at)
        at += 1
        if row != _gamut_row and row != _proof_row and row != _flip_row:
            row.visible = SaSettings.get_element_visible(SaDockerIds.MINIMAP, element)
    # The flip row holds the two flips and the proof switch, so each is shown by
    # its own element and the row stands while either is.
    var flips_wanted := SaSettings.get_element_visible(SaDockerIds.MINIMAP, "Flip Buttons")
    _proof_row_wanted = SaSettings.get_element_visible(SaDockerIds.MINIMAP, "Proof")
    _flip_h_button.visible = flips_wanted
    _flip_v_button.visible = flips_wanted
    _proof_button.visible = _proof_row_wanted
    _flip_row.visible = flips_wanted or _proof_row_wanted
    _gamut_row_wanted = SaSettings.get_element_visible(SaDockerIds.MINIMAP, "Proof Gamut")
    _sync_gamut_option()


## Follows the easel's output texture, which is replaced on a resize or a File
## New, and the canvas's material, which is rebuilt when the view transforms
## change. Polled rather than subscribed: two cheap comparisons a frame against
## three signals from two objects that both get swapped under this docker.
func _process(_delta: float) -> void:
    if not visible or target_canvas == null or not is_instance_valid(target_canvas):
        return
    var easel := target_canvas.easel
    _flush_now(easel)
    if easel != null and easel.output != null and easel.output.rid != _bound_rid:
        var shown := Texture2DRD.new()
        shown.texture_rd_rid = easel.output.rid
        _picture.texture = shown
        _bound_rid = easel.output.rid
    _sync_material()
    _sync_flip()
    _sync_proof_option()
    # The outline is the view's rectangle over the picture, so it is drawn again
    # when the view moved and not once a frame: a redraw a frame is a rendered
    # frame a frame, which is what kept the GPU busy while Sara sat idle. The
    # picture itself is the easel's texture and comes with the frame the canvas
    # asks for.
    var view_now := [
        target_canvas.get_global_transform_with_canvas(),
        target_canvas.get_viewport_rect().size,
        _overlay.size,
        easel.canvas_size if easel != null else Vector2i.ZERO,
    ]
    if view_now != _shown_view:
        _shown_view = view_now
        _overlay.queue_redraw()


## Composites what the canvas's window left unshown, because the map shows the
## whole picture. At most every `FLUSH_SECONDS`, the rate a
## layer's thumbnail redraws at, so a fill or an opacity drag while zoomed in is
## one whole composite a quarter second rather than one a frame, and the map is
## never further behind than that. Held while the painter's Thumbnails while
## painting asks for the pen to lift or the painter to stop first, and what
## the canvas's own window shows still reaches the map with every frame.
func _flush_now(easel: SaEasel) -> void:
    if easel == null or easel.backlog.is_empty():
        return
    if SaSettingsPerformance.holds_redraw(SaSettings.thumbnails_while_painting):
        return
    var now := Time.get_ticks_msec()
    if now - _flushed_msec < FLUSH_SECONDS * 1000.0:
        return
    _flushed_msec = now
    easel.flush()


## Keeps the map the same way round as the canvas. Polled beside the output
## texture and for the same reason: the view is turned by the wheel, the chords
## and the tools as well as by these two buttons, and none of them announces it.
func _sync_flip() -> void:
    var flip := _view_flip()
    if flip == _shown_flip and _picture.flip_h == (flip.x < 0.0) and _picture.flip_v == (flip.y < 0.0):
        return
    _shown_flip = flip
    _picture.flip_h = flip.x < 0.0
    _picture.flip_v = flip.y < 0.0
    if _flip_h_button != null:
        _flip_h_button.set_pressed_no_signal(flip.x < 0.0)
    if _flip_v_button != null:
        _flip_v_button.set_pressed_no_signal(flip.y < 0.0)


## What the picture is painted with: the canvas's own material while the proof
## is off, so the rolloff, the exposure and the display profile read the same
## here as on the painting, and a copy of it with one uniform changed while the
## proof is on.
func _sync_material() -> void:
    var canvas_material := target_canvas.material as ShaderMaterial
    var descriptor := _proof_descriptor() if proof_on else null
    if descriptor == null or canvas_material == null:
        _own_material = null
        _copied_from = null
        _applied_mode = &""
        if canvas_material != null and _picture.material != canvas_material:
            _picture.material = canvas_material
        return
    if _own_material == null or _material_dirty or _copied_from != canvas_material or _applied_mode != descriptor.id:
        _own_material = canvas_material.duplicate() as ShaderMaterial
        _copied_from = canvas_material
        _applied_mode = descriptor.id
        _material_dirty = false
        # A module's mode brings its own shader, exactly as it does on the
        # canvas. A built-in one is a number the canvas shader reads, and the
        # shader has to be put back when the canvas is running a module's.
        if descriptor.shader != null:
            _own_material.shader = descriptor.shader
            _own_material.set_shader_parameter("view_mode", 0)
        else:
            _own_material.shader = target_canvas.tonemap_shader
            _own_material.set_shader_parameter("view_mode", descriptor.view_mode)
    if _picture.material != _own_material:
        _picture.material = _own_material


## The mode the Minimap proof preference names, or null when it names something
## the registry does not hold or something that is not a mode. Read every frame
## rather than remembered, so a change in Preferences shows at once.
func _proof_descriptor() -> SaViewTransformDescriptor:
    if view_transforms == null:
        return null
    var descriptor := view_transforms.get_descriptor(StringName(SaSettings.minimap_proof_mode))
    if descriptor == null or descriptor.kind != SaViewTransformDescriptor.Kind.MODE:
        return null
    return descriptor


## Ctrl+Shift+Y and the Proof switch, which both land here so the switch shows
## pressed whichever of the two moved it. Answers whether the proof is on
## afterwards, which is what the test asserts and what a menu tick would read.
##
## A soft proof turned on says its line, as Ctrl+Y does for the canvas, and
## shows its gamut beside the mode at once rather than a frame later.
func toggle_proof() -> bool:
    proof_on = not proof_on
    _material_dirty = true
    if _proof_button != null:
        _proof_button.set_pressed_no_signal(proof_on)
    _sync_gamut_option()
    if proof_on and _shows_soft_proof():
        _say_proof()
    return proof_on


## Where the picture sits inside a box of *box_size* when a document of
## *document_size* is fitted into it, centred, aspect kept. The TextureRect's
## own arithmetic, written down so the overlay and the click agree with it.
static func picture_rect(box_size: Vector2, document_size: Vector2i) -> Rect2:
    if document_size.x <= 0 or document_size.y <= 0 or box_size.x <= 0.0 or box_size.y <= 0.0:
        return Rect2()
    var factor := minf(box_size.x / float(document_size.x), box_size.y / float(document_size.y))
    var shown := Vector2(document_size) * factor
    return Rect2((box_size - shown) * 0.5, shown)


## A document point onto the map, given where the picture sits.
static func document_to_map(point: Vector2, rect: Rect2, document_size: Vector2i) -> Vector2:
    if document_size.x <= 0 or document_size.y <= 0:
        return rect.position
    return rect.position + point / Vector2(document_size) * rect.size


## A map point back into the document, the inverse of document_to_map.
static func map_to_document(point: Vector2, rect: Rect2, document_size: Vector2i) -> Vector2:
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return Vector2.ZERO
    return (point - rect.position) / rect.size * Vector2(document_size)


## The four corners of what the view shows, in document pixels, clockwise from
## the top left of the screen. Through the view's own transform, so a rotated
## view comes back as the tilted quadrilateral it is.
static func view_corners(view: SaView) -> PackedVector2Array:
    var viewport := view.get_viewport_size()
    var corners := PackedVector2Array()
    for screen: Vector2 in [Vector2.ZERO, Vector2(viewport.x, 0.0), viewport, Vector2(0.0, viewport.y)]:
        corners.append(view.screen_to_document(screen))
    return corners


## Draws the view's outline on *overlay*.
func draw_view(overlay: Control) -> void:
    var document := _shown_document()
    if document == null:
        return
    var rect := picture_rect(overlay.size, document.canvas_size)
    var view := SaCanvasView.for_canvas(target_canvas)
    var flip := view.get_flip()
    var outline := PackedVector2Array()
    for corner in view_corners(view):
        outline.append(document_to_map(mirror_point(corner, document.canvas_size, flip), rect, document.canvas_size))
    outline.append(outline[0])
    overlay.draw_polyline(outline, Color(1.0, 0.55, 0.1, 0.95), 2.0, true)


## A press or a drag with the left button takes the view to that point.
func overlay_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    var motion := event as InputEventMouseMotion
    var pressed: bool = button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed
    var dragging: bool = motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
    if not (pressed or dragging):
        return
    var document := _shown_document()
    if document == null:
        return
    var rect := picture_rect(_overlay.size, document.canvas_size)
    var view := SaCanvasView.for_canvas(target_canvas)
    var target := map_to_document(event.position, rect, document.canvas_size)
    centre_view_on(view, mirror_point(target, document.canvas_size, view.get_flip()))


## Moves *view* so that *document_point* sits in the middle of it, at the zoom
## and rotation it has.
static func centre_view_on(view: SaView, document_point: Vector2) -> void:
    var middle := view.get_viewport_size() * 0.5
    view.set_pan(middle - view.view_offset(document_point))
