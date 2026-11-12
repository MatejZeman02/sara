## The View menu: the bar sections that can be hidden, the zoom, the rotation,
## and the view transforms, each kind under a submenu of its own so the menu is
## a few rows tall, with Isolate Active Layer and the grid beside them.
##
## The transforms come from the registry when one is bound, which main does
## once the registries exist: every mode as a row under Normal View, of which
## the one in force is the highlighted row, every toggle as a check item, and
## one row each for the display exposure and the relief's light. A detached bar, which is what a test
## builds, has no registry and shows the rolloff toggle alone, with the same
## id.
##
## **The exposure row opens Preferences rather than nudging**, because the
## setting is a slider there, and items moving it half a stop at a time would
## be a second, coarser front end to it.
class_name SaViewMenu
extends SaMenu

const ID_WINDOW_CONTROLS := 0
const ID_TOOL_OPTIONS := 1

## Named because it is read in three places: building the item, reacting to a
## click, and mirroring the setting when Preferences is the one that changed it.
const ID_TONEMAP := 2
## The second row of the top bar. A setting, so Preferences and this item are
## two front ends of one value and both follow it.
const ID_SECOND_ROW := 3

## The command rows: the zoom, the rotation, the mirrors and the grid, each a
## command of the registry, so its words, its chord, its sentence and its tick
## are the command's and a press runs the very handler the key runs. The chord
## is drawn as text rather than as a real accelerator, because a MenuBar fires
## an accelerator itself and the router would then fire it a second time.
const ID_ZOOM_IN := 10
const ID_ZOOM_OUT := 11
const ID_ZOOM_100 := 12
const ID_FIT := 13
const ID_CENTER := 14
## Fit to Window, past the grid rather than beside Fit, because every id from 15
## to 70 already means a row and the modes and the toggles count upwards.
const ID_FIT_WINDOW := 71
## Show Status Line, past Fit to Window for the reason that one is past the grid.
const ID_STATUS_LINE := 72
## Actual Pixels, beside Reset Zoom in the menu and past the others in number,
## for the same reason. Reset Zoom keeps `ID_ZOOM_100`, the id it had as Zoom to
## 100%, so a scenario that pressed that row presses this one.
const ID_ACTUAL_PIXELS := 73
## Relief Light..., under Show Impasto's toggle, past Actual Pixels in number for
## the same reason. It opens the small window that moves the document's light.
const ID_RELIEF_LIGHT := 74
## Isolate Active Layer, under Centre View, past Relief Light in number for the
## same reason.
const ID_ISOLATE := 75
const ID_ROTATE_LEFT := 15
const ID_ROTATE_RIGHT := 16
const ID_ROTATE_RESET := 17
## The mirrors are the same `SaView.flip_view` the Minimap docker's Flip H and
## Flip V press, and the grid is `SaSettings.show_grid`.
const ID_MIRROR_H := 18
const ID_MIRROR_V := 19

## The ordinary view, and the first registered mode's id. A mode's item id is
## its index in the registry's mode list plus ID_MODE_BASE.
const ID_NORMAL_VIEW := 20
const ID_MODE_BASE := 21
## A toggle's item id is its index plus this, except the rolloff, which keeps
## ID_TONEMAP because a test and Preferences reach it there.
const ID_TOGGLE_BASE := 40
## One row, which opens Preferences on the Display page. It keeps 60, the first
## of the three ids it replaced, so a profile or a layout that stored one of the
## others resolves to nothing rather than to a row that means something else
## now.
const ID_EXPOSURE := 60
## Past the exposure row rather than beside the mirrors, because
## `ID_MODE_BASE` counts upwards from 21 and a registry with ten modes in it
## would have reached a grid sitting at 30.
const ID_GRID := 70
## The drawing assistants' row, a module's command the menu names by id.
const ID_ASSISTANTS := 92

## The submenus' rows, past the rows above in number: the bars, the zoom, the
## rotation with the mirrors, the view modes and the display's toggles. The
## menu ran longer than a laptop's screen as one list, and every row under
## them keeps its id, so a scenario presses it by the number it always had.
const ID_BARS_GROUP := 80
const ID_ZOOM_GROUP := 81
const ID_TURN_GROUP := 82
const ID_MODE_GROUP := 83
const ID_DISPLAY_GROUP := 84
## Page Edges, its four modes and the two document switches beside it, which a
## fresh top bar hides, so the menu is where a painter finds them. Past the
## submenus in number for the reason those are past the rows above them.
const ID_PAGE_EDGES_GROUP := 85
const ID_PAGE_FIXED := 86
const ID_PAGE_GROWS := 87
const ID_PAGE_WRAPS_SIDES := 88
const ID_PAGE_WRAPS_ALL := 89
const ID_ENVIRONMENT := 90
const ID_DOUBLE_RESOLUTION := 91

const ROLLOFF_ID := &"highlight_rolloff"
## Read by `_command_for`, which has to leave this one mode's row bare.
const PROOF_ID := &"soft_proof"
const EXPOSURE_ID := &"display_exposure"
const RELIEF_ID := &"show_relief"

## The sixth registry, once main binds it. Null on a detached bar.
var view_transforms: SaViewTransformRegistry = null:
    set(value):
        if view_transforms != null and view_transforms.changed.is_connected(_on_transforms_changed):
            view_transforms.changed.disconnect(_on_transforms_changed)
        view_transforms = value
        if value != null and not value.changed.is_connected(_on_transforms_changed):
            value.changed.connect(_on_transforms_changed)
        populate()

## Item id -> transform id, rebuilt with the menu.
var _transform_ids: Dictionary = {}

## `func(section: String) -> bool` and `func(section: String, shown: bool)`, the
## bar's own answer to whether a section is shown and its own way of showing
## one. The two rows at the top of this menu are the only thing any menu asks of
## the bar that the tree does not answer, so they arrive as two calls rather
## than as the bar.
var _section_shown: Callable
var _show_section: Callable


func _init(menu_popup: SaChoicePopup, section_shown: Callable = Callable(), show_section: Callable = Callable()) -> void:
    super(menu_popup)
    _section_shown = section_shown
    _show_section = show_section


## Whether *section* of the bar is shown. A menu built with no bar behind it
## draws both rows ticked, which is what a fresh bar shows.
func _is_shown(section: String) -> bool:
    return bool(_section_shown.call(section)) if _section_shown.is_valid() else true


func _set_shown(section: String, shown: bool) -> void:
    if _show_section.is_valid():
        _show_section.call(section, shown)


func _add_items() -> void:
    begin_group(ID_BARS_GROUP, tr("Bars"), tr("Show or hide the bars around the canvas."))
    add_check_item(tr("Show Window Buttons"), ID_WINDOW_CONTROLS, _is_shown("window_controls"))
    explain(ID_WINDOW_CONTROLS, "Minimize, maximize and close, drawn by Sara at the end of the top bar.")

    add_check_item(tr("Show Tool Options Bar"), ID_TOOL_OPTIONS, _is_shown("tool_options"))
    explain(ID_TOOL_OPTIONS, "The active tool's own controls, along the top bar.")
    add_commands([[ID_SECOND_ROW, &"view_second_row"], [ID_STATUS_LINE, SaStatusLine.COMMAND]])
    end_group()
    add_separator()
    begin_group(ID_ZOOM_GROUP, tr("Zoom"), tr("Zoom the view in or out, or fit the painting to it."))
    add_commands(
        [
            [ID_ZOOM_IN, &"view_zoom_in"],
            [ID_ZOOM_OUT, &"view_zoom_out"],
            [ID_ZOOM_100, &"view_zoom_100"],
            [ID_ACTUAL_PIXELS, &"view_actual_pixels"],
            LINE,
            [ID_FIT, &"view_fit"],
            [ID_FIT_WINDOW, &"view_fit_window"],
            [ID_CENTER, &"view_center"],
        ]
    )
    end_group()
    begin_group(ID_TURN_GROUP, tr("Rotate and Flip"), tr("Turn or mirror the view. The pixels are not changed."))
    add_commands(
        [
            [ID_ROTATE_LEFT, &"view_rotate_left"],
            [ID_ROTATE_RIGHT, &"view_rotate_right"],
            [ID_ROTATE_RESET, &"view_rotate_reset"],
            LINE,
            [ID_MIRROR_H, &"view_mirror_horizontal"],
            [ID_MIRROR_V, &"view_mirror_vertical"],
        ]
    )
    end_group()
    add_commands([[ID_ISOLATE, SaIsolateActiveLayer.COMMAND], [ID_GRID, &"view_grid"], [ID_ASSISTANTS, &"view_assistants"]])
    add_separator()
    _add_page_items()
    # The second row is a setting Preferences writes as well, so its tick
    # follows the setting rather than the last press here.
    if not SaSettings.profile_changed.is_connected(sync_ticks):
        SaSettings.profile_changed.connect(sync_ticks)

    add_separator()
    _transform_ids.clear()
    if view_transforms == null:
        begin_group(ID_DISPLAY_GROUP, tr("Display"), tr("Change how the screen shows the painting. The pixels are not changed."))
        add_check_item(tr("Tonemap Highlights"), ID_TONEMAP, false, false)
        explain(ID_TONEMAP, "Compress values above 1.0 instead of clipping them. Changes what you see, never what is stored.")
        end_group()
    else:
        _add_transform_items()
    sync_tonemap_check(SaSettings.tonemap_highlights)

    # Preferences > Display carries the same toggle. Read once at startup, this
    # checkmark would go on showing the old state after a flip in Preferences,
    # and because a click here toggles *from what the menu shows*, the next
    # click would write back the value already set and look like a dead menu
    # item. One setting with two front ends needs both of them subscribed.
    if not EventBus.tonemap_changed.is_connected(sync_tonemap_check):
        EventBus.tonemap_changed.connect(sync_tonemap_check)


## Page Edges as a submenu of its four modes, each the command the top bar's
## icon runs, ticked by the document in front and dimmed on a panorama, then
## Environment View and Double Resolution as ticked rows beside it, each the
## command its bar button's press is. The menu is built before every open, so
## every tick is read off the document then.
func _add_page_items() -> void:
    begin_group(ID_PAGE_EDGES_GROUP, tr("Page Edges"), tr("Choose whether the page keeps its size, grows or wraps."))
    add_commands(
        [
            [ID_PAGE_FIXED, SaTopBarPageEdges.MODE_COMMANDS[SaTopBarPageEdges.Mode.FIXED]],
            [ID_PAGE_GROWS, SaTopBarPageEdges.MODE_COMMANDS[SaTopBarPageEdges.Mode.GROWS]],
            [ID_PAGE_WRAPS_SIDES, SaTopBarPageEdges.MODE_COMMANDS[SaTopBarPageEdges.Mode.WRAPS_SIDES]],
            [ID_PAGE_WRAPS_ALL, SaTopBarPageEdges.MODE_COMMANDS[SaTopBarPageEdges.Mode.WRAPS_ALL]],
        ]
    )
    end_group()
    add_commands([[ID_ENVIRONMENT, SaEnvironmentView.COMMAND], [ID_DOUBLE_RESOLUTION, SaTopBarDoubleResolution.COMMAND]])


## The registry's transforms as items: Normal View and every mode as plain rows
## of a one-of group, then every toggle as a check item, greyed with its reason
## while it would change nothing, then the exposure row and the relief's.
func _add_transform_items() -> void:
    # The name from the registry, the way the sentence below it already comes
    # from there, so the menu and the Display page's dropdown cannot call one
    # row two things.
    begin_group(ID_MODE_GROUP, tr("View Mode"), tr("Show the painting as it is, or through a check of its values."))
    add_item(tr(SaViewTransformRegistry.NORMAL_NAME), ID_NORMAL_VIEW)
    # The one row a painter keeps coming back to, and the only one here that
    # explained nothing. Its sentence comes from the registry, the way every
    # mode's does, so the menu and the Display page's dropdown cannot drift.
    set_item_tooltip(ID_NORMAL_VIEW, tr(SaViewTransformRegistry.NORMAL_TOOLTIP))
    var modes := view_transforms.list_modes()
    for i in modes.size():
        var descriptor := modes[i]
        var item_id := ID_MODE_BASE + i
        # A mode a chord can reach shows that chord, and one no chord reaches
        # shows its bare name as every mode row always did. The command's id is
        # the mode's under a `view_` prefix, which is a rule rather than a table
        # so a module's mode earns the same row by registering the command it
        # already has to register anyway. The Shape Check is the first mode to
        # have one. The chord goes in the chord column, as every other row's
        # does, and not inside the label, where "Shape Check (Ctrl+Shift+Q)"
        # was the one row of the menu that carried it.
        add_item(tr(descriptor.display_name), item_id, false, chord_of(_command_for(descriptor.id)))
        if not descriptor.tooltip.is_empty():
            set_item_tooltip(item_id, tr(descriptor.tooltip))
        _transform_ids[item_id] = descriptor.id
    end_group()
    begin_group(ID_DISPLAY_GROUP, tr("Display"), tr("Change how the screen shows the painting. The pixels are not changed."))
    var toggles := view_transforms.list_toggles()
    for i in toggles.size():
        var descriptor := toggles[i]
        var item_id := ID_TONEMAP if descriptor.id == ROLLOFF_ID else ID_TOGGLE_BASE + i
        # A toggle that would change nothing on screen is greyed with its
        # reason, the way File's No recent files is, because a painter who ticks
        # one to see what it does and sees nothing move takes it for broken.
        # Only the words are greyed. The box keeps its tick and its press, so a
        # painter can still put the warning on before the proof it waits for.
        var reason := _idle_reason(descriptor)
        add_check_item(tr(descriptor.display_name), item_id, false, not reason.is_empty())
        var sentence := tr(descriptor.tooltip)
        if not reason.is_empty():
            var why := tr(reason)
            sentence = why if sentence.is_empty() else "%s\n%s" % [why, sentence]
            popup.check_box(key(item_id)).tooltip_text = sentence
        if not sentence.is_empty():
            set_item_tooltip(item_id, sentence)
        _transform_ids[item_id] = descriptor.id
    if view_transforms.has(EXPOSURE_ID):
        add_item(tr("Exposure Stops..."), ID_EXPOSURE)
        explain(ID_EXPOSURE, "Set the exposure in Preferences > Canvas and colour. The pixels are not changed.")
    if view_transforms.has(RELIEF_ID):
        add_item(tr("Relief Light..."), ID_RELIEF_LIGHT)
        explain(
            ID_RELIEF_LIGHT,
            "Where the light on this document's impasto stands and how strong the relief looks. Saved with the document."
        )
    end_group()
    _sync_transform_checks()


## Why *descriptor*'s toggle changes nothing now, or "" for one that changes
## something and for one that never says. Asked on every build, and the menu is
## built before every open, so the row follows the state it reads.
static func _idle_reason(descriptor: SaViewTransformDescriptor) -> String:
    return String(descriptor.idle_reason.call()) if descriptor.idle_reason.is_valid() else ""


## The command id a mode's chord would be registered under, or "" for a mode
## whose row must not draw one.
##
## `view_` and the mode's own id, so nothing has to be kept in step: a mode with
## no such command is the ordinary case and `chord_of` leaves its column empty.
##
## **The soft proof is the one mode this rule cannot serve.** `view_soft_proof`
## exists and holds Ctrl+Y, but that chord puts on whatever the Canvas proof
## preference names rather than the soft proof, so a painter who points the
## preference at the Lightness Check would read Ctrl+Y off a row that does not
## do it. `chord_of` promises that a row cannot draw a chord that does not
## work, and one named exception keeps that promise where a wider rule would
## have broken it.
static func _command_for(transform_id: StringName) -> StringName:
    if transform_id == PROOF_ID:
        return &""
    return StringName("view_%s" % transform_id)


## The highlighted row and every check item show what the registry says. The
## modes are one choice, so one of them is highlighted and the rest carry
## nothing, while a toggle keeps its tick: several may be on at once.
## **Through `SaChoicePopup.set_current`, and `SaMenuChoice` is gone.** That
## class existed because a `PopupMenu` has no per-item colour, so the only way
## to draw a chosen row was to point the focused-item highlight at it and put it
## back on every open. A row is a `Button` now and the popup marks the chosen
## one itself, which is half the code.
func _sync_transform_checks() -> void:
    if view_transforms == null:
        return
    var active := view_transforms.mode
    var chosen := &""
    if active == SaViewTransformRegistry.NORMAL and has_item(ID_NORMAL_VIEW):
        chosen = key(ID_NORMAL_VIEW)
    # A filter that forms the picture leaves the roll-off nothing to do, so its
    # row shows unticked whatever the setting says. The setting is not written,
    # which is what makes the tick come back on when the filter goes.
    var covered := _rolloff_stands_aside()
    for item_id: int in _transform_ids:
        if not has_item(item_id):
            continue
        var transform_id: StringName = _transform_ids[item_id]
        var descriptor := view_transforms.get_descriptor(transform_id)
        if descriptor == null:
            continue
        if descriptor.kind == SaViewTransformDescriptor.Kind.MODE:
            if active == transform_id:
                chosen = key(item_id)
        else:
            var on := view_transforms.is_enabled(transform_id)
            set_item_checked(item_id, on and not (covered and transform_id == ROLLOFF_ID))
    _list_of(ID_NORMAL_VIEW).set_current(chosen)


func _on_transforms_changed() -> void:
    # A registration changes the list, a state change only the checks. Both
    # are cheap enough to rebuild for, and one path cannot go stale.
    populate()


func _pressed(id: int) -> void:
    if view_transforms != null and _press_transform(id):
        return

    var is_checked := not is_item_checked(id)
    set_item_checked(id, is_checked)

    if id == ID_WINDOW_CONTROLS:
        _set_shown("window_controls", is_checked)
    elif id == ID_TOOL_OPTIONS:
        _set_shown("tool_options", is_checked)
    elif id == ID_TONEMAP:
        SaSettings.tonemap_highlights = is_checked


## The registry answers a transform item. Returns false for an item that is
## not one, so the section toggles above keep their own handling.
func _press_transform(id: int) -> bool:
    if id == ID_NORMAL_VIEW:
        view_transforms.set_mode(SaViewTransformRegistry.NORMAL)
        return true
    if id == ID_EXPOSURE:
        # Deferred for the reason the Edit menu gives for Preferences: popping a
        # window while the menu that asked for it is still closing puts the two
        # in one frame and the popup keeps the focus.
        EventBus.display_page_requested.emit.call_deferred()
        return true
    if id == ID_RELIEF_LIGHT:
        EventBus.relief_light_requested.emit.call_deferred()
        return true
    if not _transform_ids.has(id):
        return false
    var transform_id: StringName = _transform_ids[id]
    var descriptor := view_transforms.get_descriptor(transform_id)
    if descriptor == null:
        return false
    if descriptor.kind == SaViewTransformDescriptor.Kind.MODE:
        view_transforms.set_mode(transform_id)
    else:
        view_transforms.set_enabled(transform_id, not view_transforms.is_enabled(transform_id))
    return true


## Mirrors `SaSettings.tonemap_highlights` onto the menu's checkmark.
##
## Public because it is what `EventBus.tonemap_changed` is connected to, and a
## test has to be able to ask whether the menu agrees with the setting.
func sync_tonemap_check(enabled: bool) -> void:
    set_item_checked(ID_TONEMAP, enabled and not _rolloff_stands_aside())
    _sync_transform_checks()


## Whether the roll-off is standing aside because a filter forms the picture.
##
## Read off the descriptor's own reason, so the tick, the dimming and the
## sentence all come from one answer rather than three asks of the document. A
## filter that forms the picture says so, and the descriptor says why the row
## is greyed, and neither names the Tonemap.
func _rolloff_stands_aside() -> bool:
    if view_transforms == null:
        return false
    var descriptor := view_transforms.get_descriptor(ROLLOFF_ID)
    return descriptor != null and not _idle_reason(descriptor).is_empty()
