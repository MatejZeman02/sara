## The brush presets docker: the presets chooser in a docker of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The grid and the thumbnails are one control built with two hosts in mind, the
## tool options bar and this docker, and this host is deliberately thin:
## a `DockerWindow` around `SaBrushPresetsChooser` and nothing else.
##
## **It asks the bar for the store and for the settings, rather than making its
## own.** A second `SaPresetStore` would read the same directory and a second
## settings source would answer the same resource, so the two hosts would agree
## until the day they did not. The bar's group is found by
## `ToolOptionsPresets.in_tree`, and applying from here goes through its
## `load_preset`, which is the same call the bar's own popup made:
## the settings resource is written once, the bar's dropdown and name field
## follow, and `EventBus.preset_loaded` fires so the History docker records it.
## One settings object, held by construction rather than by two paths being
## kept in step.
##
## **The grid is here and not in a popup under the bar's button**, so the
## Presets button opens this docker. Save as... and Delete are here too,
## because a painter who can see the presets is the one who wants them.
@tool
extends DockerWindow

class_name BrushPresetsDocker

const DockerColumnScroll := preload("res://ui/dockers/docker_column_scroll.gd")
const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")
const PresetPickAfter := preload("res://ui/dockers/presets/preset_pick_after.gd")
const PresetsCapture := preload("res://ui/dockers/presets/brush_presets_capture.gd")
const PresetsPlacement := preload("res://ui/dockers/presets/brush_presets_placement.gd")

## What it opens at, the size the shipped layout gives it: two
## columns of the default icon with every shipped name whole under its picture,
## and two full rows of them above the fold.
const DEFAULT_SIZE := Vector2i(310, 370)
const MIN_SIZE := Vector2i(200, 200)

## The two answers to the delete question, in the order the buttons stand in.
## Cancel first, so the safe one is also the default and what Escape does.
const DELETE_CANCEL: int = 0
const DELETE_CONFIRM: int = 1

var chooser: SaBrushPresetsChooser = null

## The two actions under the grid. Delete presses the bar's own handler by id,
## the programmatic door opened for exactly this, and Save as... saves through
## the bar's own call.
##
## **Pinned under the scroll, not at the foot of it.** As the last rows of the
## column the scroll holds, with the 52 presets a fresh profile ships, they
## would stand 3,400 pixels below the docker's top, and a click meant for them
## would land on whatever the screen shows at that height.
var save_button: Button = null
var delete_button: Button = null

## Save as...'s name field, over the two buttons, hidden until Save as... is
## pressed. Return writes the preset, and Escape or a press anywhere else puts
## it away. No Save button beside it: the field closes when it loses the
## keyboard, the bar field's rule, and a press that took the keyboard to such a
## button would hide it under the pointer.
var name_row: HBoxContainer = null
var name_field: LineEdit = null

## One dimmed line over the buttons that says what the last of the three did:
## the preset saved, the preset deleted, or the defaults put on the brush. Each
## press is answered where it was made, because the grid's mark alone is a
## cell that may be scrolled out of sight. Emptied, and hidden, by the next preset loaded.
var said_line: Label = null

## The entry that answers "what are the defaults" without a fork.
##
## Under the grid rather than in it, on a row of its own above Save as... and
## Delete. Without it a new preset can only be forked from an existing one, so
## the defaults are unreachable, and a cell in the grid would have to be a
## preset that is not on disk: a name the search filters, the
## tag row hides and the thumbnail queue tries to render. A button beside the
## other two is the same reach with none of that.
##
## **It opens New preset...**, the dialog the cell menu's first row opens,
## rather than putting the engine in hand's defaults on the brush with no preset
## loaded. The engine is chosen in a dialog because a painter who has deleted
## every preset has nothing to fork, and the defaults of an engine not in hand
## are reached by no other door.
var new_button: Button = null

## Which engine each cell's preset was written for, and the dimming of the ones
## the tool in front of the painter will not take.
var engine_marks: PresetEngineMarks = null

## The engines the cells were last dimmed against, so a tool switch that keeps
## the cells redims them only when the new tool takes other engines.
var _dimmed_for: Array[StringName] = []

## The redim a tool switch leaves for the frame after it, so the frame a preset
## of another engine is picked in is not also the frame every cell is marked
## again in, 7 to 13 ms of it on the factory grid.
var after_pick: PresetPickAfter = PresetPickAfter.new()

## The bar's preset group as `_presets` last found it, null until then and
## after it left the tree.
var _held_presets: ToolOptionsPresets = null

## Where the loaded preset came from and under what licence, on one dimmed line
## under the grid. It owns its own text and the hiding of an empty row.
var provenance_line: ProvenanceLine = null

## The floor of the scroll the chooser sits in, one row of its grid.
var grid_floor: GridFloor = null


func _init() -> void:
    _init_docker(SaDockerIds.BRUSH_PRESETS, "Brush Presets", DEFAULT_SIZE, MIN_SIZE)
    # Where a fresh profile finds it: under the History docker on the left, the
    # two being the same question asked of different lists.
    position = Vector2i(2, 340)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Brush Presets")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(null, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    chooser = SaBrushPresetsChooser.new(true, vbox)
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    chooser.size_flags_vertical = Control.SIZE_EXPAND_FILL
    chooser.preset_chosen.connect(_on_preset_chosen)
    engine_marks = PresetEngineMarks.new(chooser, _preset_store, tool_engines)

    var column := SaMake.column(margin, "ChooserColumn", 6)
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(chooser)

    provenance_line = ProvenanceLine.new(_preset_store, _loaded_preset)
    column.add_child(provenance_line)

    grid_floor = GridFloor.new(chooser, DockerColumnScroll.wrap(vbox, margin), margin)
    margin.minimum_size_changed.connect(floor_the_grid)

    # The actions, under the scroll so a grid of any length leaves them on screen. Two rows
    # cost a row of cells at 370 high, one being wider than 310. Random stands by New.
    var footer := SaMake.margin(vbox, "ChooserFooter", SaUI.BASE_MARGIN)
    footer.add_theme_constant_override("margin_top", 0)
    var below := SaMake.column(footer, "ChooserBelow", 6)

    # The line and the field go in above the row of Save as... and Delete, so
    # what they show grows the footer upwards and the button just pressed stays
    # under the pointer. Under it, Delete moved a row up as the line came.
    # One line whatever the name, cut with the mark, so a long name costs the
    # grid no second row and asks the docker for no width.
    said_line = SaMake.label(below, "ChooserSaid")
    said_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    said_line.clip_text = true
    said_line.text_overrun_behavior = SaTheme.TEXT_CUT
    said_line.visible = false
    SaTheme.bind_font(said_line, "text_muted")

    var new_tip := tr("Make a preset from the defaults of an engine you pick")
    var new_row := SaMake.row(below, "ChooserNewRow", 6)
    new_button = SaMake.button(new_row, "ChooserNew", tr("New Preset..."), new_tip)
    new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    new_button.focus_mode = Control.FOCUS_NONE
    new_button.pressed.connect(_on_new_pressed)
    SaRandomPresetButton.new(self, new_row)

    name_row = SaMake.row(below, "ChooserNameRow", 6)
    name_row.visible = false
    name_field = SaMake.line_edit(name_row, "ChooserName", "", tr("Name"))
    name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_field.tooltip_text = tr("Press Enter to save, Escape to cancel.")
    name_field.text_submitted.connect(_on_name_submitted)
    name_field.focus_exited.connect(close_name_field)
    name_field.gui_input.connect(_on_name_gui_input)

    var actions := SaMake.row(below, "ChooserActions", 6)

    save_button = SaMake.button(actions, "ChooserSave", tr("Save As..."))
    save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_button.focus_mode = Control.FOCUS_NONE
    save_button.pressed.connect(_on_save_pressed)

    delete_button = SaMake.button(actions, "ChooserDelete", tr("Delete"))
    delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    delete_button.focus_mode = Control.FOCUS_NONE
    delete_button.pressed.connect(_on_delete_pressed)


func _enter_tree() -> void:
    SaRightClickDocker.attach(SaRightClickDocker.PRESETS, toggle_at)


func _exit_tree() -> void:
    SaRightClickDocker.detach(SaRightClickDocker.PRESETS, self)


func _ready() -> void:
    _setup_docker_ready()
    floor_the_grid.call_deferred()
    if not EventBus.tool_changed.is_connected(_on_tool_changed):
        EventBus.tool_changed.connect(_on_tool_changed)
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    if not EventBus.preset_store_changed.is_connected(_on_preset_store_changed):
        EventBus.preset_store_changed.connect(_on_preset_store_changed)
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    # A preset saved from the bar tells nobody: `save_current_as_preset` rebuilds
    # the bar's own dropdown and stops there. So the grid is rebuilt every time
    # the docker is shown, which is when a painter would notice it was stale, and
    # a save made while it is open is the gap that leaves.
    if not visibility_changed.is_connected(_on_visibility_changed):
        visibility_changed.connect(_on_visibility_changed)
    apply_layout_settings()
    rebind()


## Floors the scroll at one row of the grid and the window at the column that
## makes. Runs again whenever what the scroll holds changes size, a grid
## rebuilt, an icon size or a font.
func floor_the_grid() -> void:
    grid_floor.hold()
    enforce_column_minimum()


## The column's whole minimum and the grip's corner under it, which the floored
## scroll makes one row of presets tall. The one docker that floors its height,
## and the reason the others do not is `reserve_grip_corner`'s. Nought outside
## the tree, where the window's scale cannot be asked.
func column_height_floor() -> int:
    var column := content_column()
    if column == null or not is_inside_tree():
        return 0
    return SaUI.window_size_for(self, Vector2i(0, column_min_height(self) - int(column.offset_bottom))).y


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.BRUSH_PRESETS)


## Points the chooser at the bar's store, the bar's tool and the bar's settings
## source, and rebuilds the grid. Answers false when there is no bar to ask,
## which is what a test with a detached docker gets.
##
## Reached from every show through `follow_tool`, because the tool the bar is
## on decides which script draws a thumbnail, and a docker opened after the
## painter switched tools would otherwise draw the last one's. A tool change
## takes `follow_tool` too, which builds no cell the grid already holds.
func rebind() -> bool:
    var presets := _presets()
    if presets == null or chooser == null:
        return false
    # A boot that has not scanned the store yet leaves the grid empty and binds
    # when the scan lands, rather than listing the directory in a boot frame.
    if presets.scan_held:
        if not presets.scanned.is_connected(rebind):
            presets.scanned.connect(rebind, CONNECT_ONE_SHOT)
        return true
    chooser.bind_store(
        presets.preset_store,
        _painter_script(presets),
        presets.settings_source,
        func() -> String: return presets.selected_preset,
        _engine_painters(presets)
    )
    # The rebuild marked every cell against the tool in hand, so a redim still
    # waiting has nothing left to do.
    after_pick.settle(&"redim")
    _dimmed_for = tool_engines()
    sync_actions()
    provenance_line.sync()
    return true


## The script of the tool the bar shows, which is what draws a thumbnail, or
## null when the bar shows none.
static func _painter_script(presets: ToolOptionsPresets) -> Script:
    var painter := presets.tool_source.call() as ToolState if presets.tool_source.is_valid() else null
    return painter.get_script() as Script if painter != null else null


## The script that draws each engine's presets, by engine, off the tools the bar
## says the shown tool paints with. The Brush's shelf holds both engines' presets,
## and a noise preset drawn by the stamp's script is a stamp stroke under a
## noise preset's name.
static func _engine_painters(presets: ToolOptionsPresets) -> Dictionary:
    var out: Dictionary = {}
    var engines: Variant = presets.engines_source.call() if presets.engines_source.is_valid() else null
    if not (engines is Dictionary):
        return out
    for engine: Variant in engines as Dictionary:
        var painter := (engines as Dictionary)[engine] as ToolState
        if painter != null:
            out[engine] = painter.get_script()
    return out


## Shows this docker, puts it in front and gives it the keyboard, opening it
## beside *at* when it was closed. Where it opens and the door it is shown by
## are `brush_presets_placement.gd`'s, [method PresetsPlacement.reveal].
func reveal(at: Variant = null) -> bool:
    return PresetsPlacement.reveal(self, at)


## Hides it again through the door [method reveal] opens it by, and answers
## whether it ended up hidden.
func conceal() -> bool:
    return PresetsPlacement.conceal(self)


## Lends this docker to the brush's right press at *point*, or sends it home,
## [method PresetsPlacement.toggle_at]. Answers whether the press moved it.
func toggle_at(point: Vector2, dockers: MainDockers = null) -> bool:
    return PresetsPlacement.toggle_at(self, point, dockers)


## Save as..., answered here. It pressed the bar's id, which swapped a field in
## for the bar's preset button, so nothing showed where the press was made and
## nothing at all with that button hidden or in the bar's overflow. The bar's
## field stays the one a host with no docker asks in.
func _on_save_pressed() -> void:
    open_name_field()


## Opens the name field over the buttons, prefilled with the loaded preset's
## name so saving over it is a press and a Return, and gives it the keyboard.
## Answers false with the docker shut or a tool that takes no presets.
func open_name_field() -> bool:
    var presets := _presets()
    if name_row == null or presets == null or not visible:
        return false
    if not presets.action_available(ToolOptionsPresets.PRESET_ID_SAVE):
        return false
    name_field.text = presets.selected_preset
    name_row.visible = true
    if name_field.is_inside_tree():
        name_field.grab_focus()
        name_field.select_all()
    return true


## Puts the field away, which is also what its losing the keyboard does: the
## router's Escape lets go of a focused text box before the box hears the key,
## so the close has to follow the focus rather than the key.
func close_name_field() -> void:
    if name_row == null:
        return
    name_row.visible = false
    if name_field.has_focus():
        name_field.release_focus()


func _on_name_submitted(typed: String) -> void:
    save_named(typed)


## Writes the brush under *typed* through `save_current_as_preset`, which is what
## the bar's field does, and says so over the buttons. Answers the name it was
## stored under, or "" when nothing was written.
##
## A name that comes out empty once it is made fit for a file name keeps the
## field open and asks for one, rather than closing on a save that never was.
func save_named(typed: String) -> String:
    var presets := _presets()
    if presets == null:
        return ""
    if SaPresetStore.sanitize_name(typed).is_empty():
        _say(tr("A preset needs a name."))
        return ""
    close_name_field()
    var stored := presets.save_current_as_preset(typed)
    if stored.is_empty():
        _say(tr("'%s' could not be saved.") % typed)
    else:
        _say(tr("Saved '%s'.") % stored)
    return stored


## Escape puts the field away and stops there, for a host with no router in
## front of the field, which is every suite that builds this docker.
func _on_name_gui_input(event: InputEvent) -> void:
    if not SaShortcutKeys.is_escape(event):
        return
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo():
        return
    close_name_field()
    name_field.accept_event()


## Puts *text* on the line over the buttons, or hides the line for "".
func _say(text: String) -> void:
    if said_line == null:
        return
    said_line.text = text
    said_line.visible = not text.is_empty()


## Asks before deleting, and deletes only on the answer.
##
## There is a Confirm dialog on the delete click for safety, and safety is the
## whole of it: `delete_loaded_preset` removes the
## file and there is no undo anywhere near a preset. The name goes in the
## sentence rather than in the title, because "Delete this preset?" over a grid
## of forty thumbnails does not say which one the button was under.
##
## Cancel is both the default and the cancel index, so Enter and Escape both
## leave the preset alone. `SaMessage.confirm` frees the window on the answer.
func _on_delete_pressed() -> void:
    var presets := _presets()
    if presets == null or presets.selected_preset.is_empty():
        return
    var doomed := presets.selected_preset
    # Hosted on the bar's presets group rather than on the root or on this
    # docker: `menus/file_menu.gd` hosts its own question on the bar for the same
    # reason, a node that outlives the answer and is never the one mid-`_ready`.
    # The root is exactly that node in a test suite, which runs inside `_ready`,
    # and `add_child` on a busy parent is refused outright with the child left
    # orphaned.
    SaMessage.confirm(
        presets,
        tr("Delete preset"),
        tr("Delete '%s'? This cannot be undone.") % doomed,
        PackedStringArray([tr("Cancel"), tr("Delete")]),
        _on_delete_answered.bind(doomed),
        DELETE_CANCEL,
        DELETE_CANCEL
    )


## The answer to the question above: index 1 is Delete and everything else,
## Escape included, is Cancel.
##
## *doomed* is bound rather than read again, because the answer arrives on a
## later frame and a preset applied in between would otherwise be the one that
## went. It is loaded first for the same reason `delete_loaded_preset` is what
## deletes: the bar's dropdown, the docker's grid and the History docker all
## follow that one call, and a store delete behind their backs leaves three
## lists showing a preset that is not there.
func _on_delete_answered(index: int, doomed: String) -> void:
    if index != DELETE_CONFIRM:
        return
    var presets := _presets()
    if presets == null:
        return
    if presets.selected_preset != doomed:
        presets.load_preset(doomed)
    # The delete takes whatever is loaded, so a preset that would not load, one
    # already deleted elsewhere while the question stood, must stop it here, or
    # the preset loaded before goes in its place.
    if presets.selected_preset != doomed:
        return
    presets.press_action(ToolOptionsPresets.PRESET_ID_DELETE)
    if presets.preset_store.has_preset(doomed):
        _say(tr("'%s' could not be deleted") % doomed)
    else:
        _say(tr("Deleted '%s'") % doomed)


## New preset..., which opens the dialog the cell menu's first row opens. The
## answer is the dialog, and then the new preset loaded, marked and named on the
## bar.
func _on_new_pressed() -> void:
    SaNewPresetDialog.open_from(self)


## The bar's preset group's own answer to which preset the brush is on, for the
## line under the grid: a `Callable`, so the line asks at the moment it draws.
func _loaded_preset() -> String:
    var presets := _presets()
    return presets.selected_preset if presets != null else ""


## Whether each action can be pressed, which follows what the bar holds, and a
## tooltip that says what a press will do or why it cannot: with no preset loaded
## there is nothing to delete, and a tool that takes no presets has none to save.
func sync_actions() -> void:
    var presets := _presets()
    if save_button == null or delete_button == null:
        return
    var loaded := presets.selected_preset if presets != null else ""
    save_button.disabled = presets == null or not presets.action_available(ToolOptionsPresets.PRESET_ID_SAVE)
    save_button.tooltip_text = (
        tr("Save the brush as a new preset, or over this one under its name.")
        if not save_button.disabled
        else tr("This tool has no presets.")
    )
    delete_button.disabled = presets == null or not presets.action_available(ToolOptionsPresets.PRESET_ID_DELETE)
    delete_button.tooltip_text = (
        tr("Delete '%s' for good.") % loaded
        if not loaded.is_empty()
        else tr("No preset is loaded, so there is nothing to delete. Select one in the grid first.")
    )
    if new_button != null:
        new_button.disabled = presets == null
    if save_button.disabled:
        close_name_field()


## The chooser's own report, for a scenario and a test: what it is showing and
## what it is bound to.
func capture_state() -> Dictionary:
    return {
        "open": visible,
        "focused": has_focus(),
        "position": {"x": position.x, "y": position.y},
        "size": {"x": size.x, "y": size.y},
        "bound": chooser != null and chooser.store != null,
        # Out on a lend, and the head a lent docker shows, its title and its close.
        "lent": lent,
        "head": {"shown": drag_handle.is_visible_in_tree(), "close": hide_button != null and hide_button.is_visible_in_tree()},
        # The two actions that came with the grid, because whether Delete is
        # offered is the claim `test_brush_presets.gd` makes and a screenshot of
        # a dimmed button is a shape rather than a state.
        "save_disabled": save_button.disabled if save_button != null else true,
        "delete_disabled": delete_button.disabled if delete_button != null else true,
        "new_disabled": new_button.disabled if new_button != null else true,
        # What each press would say and what the last one did say, with the
        # preset in hand and the bar's button beside them, so one dump holds
        # both ends of "New preset leaves the bar on Canvas Brush".
        "loaded": _loaded_preset(),
        "bar_button": _bar_button_text(),
        # The tooltip beside the label, because the label is the word Presets
        # whatever is loaded and the preset in hand is read on the hover, which
        # a screenshot cannot show.
        "bar_tooltip": _bar_button_tip(),
        "save_tip": save_button.tooltip_text if save_button != null else "",
        "delete_tip": delete_button.tooltip_text if delete_button != null else "",
        "naming": name_row != null and name_row.visible,
        "name_text": name_field.text if name_field != null else "",
        "name_focused": name_field != null and name_field.has_focus(),
        "said": said_line.text if said_line != null and said_line.visible else "",
        # New preset..., the dialog behind the button and the menu's head.
        "new_dialog": new_dialog_report(),
        # Whether the three buttons are inside the docker rather than under its
        # fold, which a screenshot of a scrolled grid does not settle.
        "actions_in_view": _actions_in_view(),
        # The bundle and licence of the loaded preset, which is a sentence rather
        # than a shape and so is read here rather than argued about from a
        # screenshot. Empty when the loaded preset's own file says nothing.
        "provenance": provenance_line.text if provenance_line != null else "",
        # The chooser's own report, whole rather than picked over, so this docker
        # and the bar's popup are read the same way in a dump.
        "chooser": chooser.chooser_report() if chooser != null else {},
    }


## What New preset... reports, or nothing while it has never been opened.
func new_dialog_report() -> Dictionary:
    var presets := _presets()
    var dialog := presets.get_node_or_null(SaNewPresetDialog.NODE_NAME) as SaNewPresetDialog if presets != null else null
    return dialog.dialog_report() if dialog != null else {}


## What the bar's preset button reads, or "" in a host with no bar.
func _bar_button_text() -> String:
    var presets := _presets()
    return presets.preset_menu.text if presets != null and presets.preset_menu != null else ""


## What the bar's preset button says on a hover, the preset in hand and the job,
## or "" in a host with no bar.
func _bar_button_tip() -> String:
    var presets := _presets()
    return presets.preset_menu.tooltip_text if presets != null and presets.preset_menu != null else ""


## Whether New, Save as... and Delete all lie inside the docker's own rectangle.
func _actions_in_view() -> bool:
    var room := Rect2(Vector2.ZERO, Vector2(size))
    for button: Button in [new_button, save_button, delete_button]:
        if button == null or not button.is_visible_in_tree() or not room.encloses(button.get_global_rect()):
            return false
    return true


## Drives the presets docker: the docker's own half of the capture door, so a
## scenario can press a cell without an injected click, which does not route
## into a docker's window. What each spec does is `brush_presets_capture.gd`'s,
## and this is the one name the step table calls.
static func capture_docker(tree: SceneTree, spec: Variant) -> String:
    return PresetsCapture.capture(tree, spec)


## Applies *preset_name* the way a click on its cell does. Public so the door and
## a test press the same path a painter does.
func apply_preset(preset_name: String) -> bool:
    var presets := _presets()
    return presets.load_preset(preset_name) if presets != null else false


## A press on a cell, which the usage tally counts as a pick here, where the
## door's step and a suite call [method apply_preset] and count none.
func _on_preset_chosen(preset_name: String) -> void:
    SaUsageTally.preset_picked(SaUsageTally.BRUSH_PRESETS)
    apply_preset(preset_name)


## A preset applied anywhere marks the cell, shown and scrolled to.
func _on_preset_loaded(preset_name: String) -> void:
    # Its tip starts loading off the stroke, whichever door loaded the preset,
    # so the first press finds the picture on the card.
    SaTipCache.load_ahead(_presets().settings_source.call() if _presets() != null else null)
    if chooser != null:
        chooser.follow_load()
    # The line is about the loaded preset, so a load anywhere is what moves it.
    provenance_line.sync()
    # A preset picked is an answer the grid and the bar give, and what the last
    # press here did is not what is in the hand any more. New announces "" and has
    # its own line to keep.
    if not preset_name.is_empty():
        _say("")


## A preset written or removed anywhere rebuilds the grid, so the docker holds
## what is on disk without being shown again.
##
## `rebind` rather than `chooser.refresh`, because a save writes a file the
## chooser's store has not listed and a delete removes one it has, and rebinding
## is what re-reads the store. `_on_preset_loaded` gets away with the cheaper
## call because a load changes which cell is marked and not which cells exist.
func _on_preset_store_changed(_preset_name: String, _saved: bool) -> void:
    rebind()


## A tool switch rebuilds the grid only when the grid would come out different,
## and redims the cells it holds when the new tool takes another engine.
##
## Rather than a `rebind`, which rebuilds every cell while the bar's own handler
## rebuilds them a second time in the same frame, a cost a transform's commit
## frame feels. A switch changes the store,
## the tag and the search not at all, so what it can change is the loaded preset,
## which `refresh_if_changed` sees, and the engine the cells are dimmed against,
## which is the one thing a cell built for the last tool has wrong.
##
## The redim waits for the frame after the switch, as `after_pick` says.
func _on_tool_changed(_tool_name: String) -> void:
    follow_tool(false)


## Points the chooser at the tool the bar is on and brings the grid up to date
## with the fewest cells built, which is none when only the tool moved. Answers
## false when there is no bar to ask, as `rebind` does. With *at_once* false the
## kept cells are redimmed in the frame after this one.
func follow_tool(at_once: bool = true) -> bool:
    var presets := _presets()
    if presets == null or chooser == null:
        return false
    if not chooser.follow_tool(presets.preset_store, _painter_script(presets), _engine_painters(presets)):
        return rebind()
    # A cell built by the follow is marked already, and marking it again is the
    # same tooltip and the same dim, so the kept and the new are one loop.
    if at_once:
        after_pick.settle(&"redim")
        _redim()
    elif tool_engines() != _dimmed_for:
        after_pick.ask(&"redim", _redim, get_tree() if is_inside_tree() else null)
    sync_actions()
    provenance_line.sync()
    return true


## Marks the kept cells again when the tool in hand takes other engines than
## they were dimmed against.
func _redim() -> void:
    var engines := tool_engines()
    if engines != _dimmed_for:
        for cell: Node in chooser.grid.get_children():
            engine_marks.mark(cell)
    _dimmed_for = engines


## A show brings the grid up to the tool the bar is on through `follow_tool`,
## which rebinds only when the grid would come out different. A rebind on every
## show rebuilt every cell, 63 ms of the frame a layout load opened the docker
## in, and a store change rebinds while the docker is hidden anyway.
func _on_visibility_changed() -> void:
    if visible:
        follow_tool()
    else:
        close_name_field()


## The engines whose presets the tool the bar shows takes, which is the bar's own
## reading of them, so the docker's dim and the bar's load cannot answer
## differently. Every engine of the Brush while the Brush is shown, so a noise
## preset on its shelf is live rather than dimmed.
##
## Empty in a host with no bar, and empty for a tool that declares no engine,
## which is a tool that takes no presets and so dims nothing: a class name read as
## an engine is what dimmed every cell with the gradient picked.
func tool_engines() -> Array[StringName]:
    var presets := _presets()
    return presets.preset_engines() if presets != null else [] as Array[StringName]


## The bar's preset group, found once and held, or null in a host with no bar.
##
## `ToolOptionsPresets.in_tree` searches the whole tree, and a tool switch asks
## for the group three times here, from the follow, the dim and the action
## buttons. Held from the first search that finds the group, forgotten
## when it leaves the tree, and searched for again while there is none, since a
## bar can arrive after the docker.
func _presets() -> ToolOptionsPresets:
    if is_instance_valid(_held_presets) and _held_presets.is_inside_tree() and is_inside_tree():
        return _held_presets
    _held_presets = ToolOptionsPresets.in_tree(self)
    if _held_presets != null and not _held_presets.tree_exiting.is_connected(_forget_presets):
        _held_presets.tree_exiting.connect(_forget_presets)
    return _held_presets


func _forget_presets() -> void:
    _held_presets = null


func _preset_store() -> SaPresetStore:
    var presets := _presets()
    return presets.preset_store if presets != null else null


## The dimmed line under the presets grid: where the loaded preset came from and
## under what licence.
##
## The ask: "Every bundle Sara ships carries its own licence, the way a
## Krita bundle does, and the chooser shows it." A cell's tooltip carries it for
## the preset under the pointer, and this is the same sentence about the preset
## the brush is actually holding, which is the one a painter would ship a picture
## painted with. It sits under the grid rather than in it because it is about the
## loaded brush and not about any of the pictures.
##
## A class of its own, because it owns one thing, the line, and the two facts it
## needs arrive as `Callable`s the way the chooser takes its settings: the store
## to read and the name of the loaded preset, both asked at the moment it draws
## so a host that has just replaced its session is never a frame behind. An
## inner class, where it had been a file of fifty lines with this docker for its
## only user.
class ProvenanceLine:
    extends Label

    ## Answers the `SaPresetStore` the grid lists, or null in a host with no bar.
    var _store: Callable = Callable()

    ## Answers the name of the preset the brush is on, empty when it is on none.
    var _loaded: Callable = Callable()

    func _init(store: Callable, loaded: Callable) -> void:
        _store = store
        _loaded = loaded
        name = "ChooserProvenance"
        horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        # **Wrapping rather than clipped**, so a long bundle and licence reads
        # whole where the engine line under a cell is cut off, and **one pixel
        # of minimum width** for the reason the cell's name wraps: a label that
        # asks for its text's width would set the column's and the grid's with
        # it.
        autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        max_lines_visible = 2
        SaTheme.bind_font(self, "text_muted")
        SaOnLanguage.follow(self, sync)

    ## Puts the loaded preset's line up, and hides the row when there is nothing
    ## to say.
    ##
    ## Hidden rather than blank, because a preset a painter saved themselves
    ## carries no bundle and no source, and an empty row under a grid of forty
    ## pictures is a gap with no reason in it.
    func sync() -> void:
        var store := _store.call() as SaPresetStore if _store.is_valid() else null
        var loaded := String(_loaded.call()) if _loaded.is_valid() else ""
        var line := store.provenance_for(loaded) if store != null and not loaded.is_empty() else ""
        text = line
        visible = not line.is_empty()


## Keeps a row of presets in sight at the docker's smallest.
##
## The scroll declared no height, so the floor was the 200 the docker declared,
## and a grip shrink to it left the search box, the tag row and the three
## buttons with every preset scrolled out of sight. The scroll's floor is now
## what stands above the grid and one row of cells. It is not the scroll's whole
## content less the other rows: that counts the provenance
## line, and it sits under the last row, so the floor came out at 392 against
## the 370 the docker opens at and showed a row and a half.
##
## An inner class because it holds the three things the floor is measured
## from, and because the rows above the grid are the chooser's: the docker
## already reads nine things off the chooser, and a tenth makes it a piece of
## the chooser's class by the structure suite's count.
class GridFloor:
    extends RefCounted

    var _chooser: SaBrushPresetsChooser = null
    var _scroll: ScrollContainer = null

    ## The margin the scroll holds, whose top is above the grid as well.
    var _scrolled: Control = null

    func _init(chooser: SaBrushPresetsChooser, scroll: ScrollContainer, scrolled: Control) -> void:
        _chooser = chooser
        _scroll = scroll
        _scrolled = scrolled

    ## Sets the scroll's floor and answers it.
    func hold() -> float:
        var grid := _chooser.grid
        var gap := float(_chooser.get_theme_constant(&"separation"))
        var above := float(_scrolled.get_theme_constant(&"margin_top"))
        for child in _chooser.get_children():
            if child == grid:
                break
            var control := child as Control
            if control != null and control.visible:
                above += control.get_combined_minimum_size().y + gap
        var first := grid.get_child(0) as Control if grid.get_child_count() > 0 else null
        var row := first.get_combined_minimum_size().y if first != null else 0.0
        _scroll.custom_minimum_size.y = ceilf(above + row)
        return _scroll.custom_minimum_size.y
