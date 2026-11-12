## "I'm coming from": a button for each program, Krita, Photoshop, Procreate
## and Clip Studio Paint, each setting in one press every preference the
## program a painter comes from has a meaning for.
## A painter who has used no painting program leaves the row as it is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What each program sets is [constant PROGRAMS], and nothing else is.** The
## shortcut profile, the colour theme, the docker layout, the colour picker's
## shape and what Ctrl+0 shows are the preferences where the programs differ from
## Sara and from each other. The UI scale is never among them: hard rule 7 leaves
## it to `SaUI.apply_to_window()` through `SaSettings.ui_scale`, and the layouts
## this row loads set no scale, so the press leaves the painter's own.
##
## **Sara's own values have no button.** They are [constant OWN_VALUES], a
## fresh profile's, in force while no program is, and a press on the button in
## force releases it and puts Sara's own values back. The pressed button is read,
## never remembered: [method in_force] compares the settings in force with each
## program's, so a painter who changes one of them sees no button pressed.
##
## **Each preference is written by the writer that already owns it**, so the
## row adds no second meaning to any of them: the shortcut profile as the
## Keyboard Shortcuts page switches it, the palette through
## `SaSettings.theme_name`, the layout through `DockerLayoutStore.load_preset`,
## the picker's shape through `SaSettings.color_picker_shape`, and what Ctrl+0
## shows through `SaSettings.reset_zoom`. A press never deletes anything: a
## painter's own profile, palette or layout fork stays on disk and listed.
##
## **A press is spread over the frames after it**, one writer a frame, so no
## frame of it holds Sara longer than a tenth of a second (one call of
## [method apply] took 3 s). The button shows pressed in the frame of the press,
## the shortcut map is applied in the next, what follows it in the one after, the
## palette in slices of [constant THEME_SLICE_USEC] a frame, then the layout, and
## last the picker with Ctrl+0's answer. A second press meanwhile waits for the
## first to end, so the last answer pressed is the one in force. A row out of the
## tree has no frames and applies at once.
##
## **A press asks first.** [method ask], what a button calls, puts up
## `SaComingFromQuestion`'s question naming the program and the five values now
## and after, and only its Overwrite writes, as [method press] does. A press that
## would change nothing asks nothing.
class_name SaComingFromRow
extends HBoxContainer

## A button was pressed and its program's settings are in force, so a surface
## showing any of them reads them again.
signal program_applied(program: String)

## The programs in the order the row shows them, each with what it sets.
##
## Read for Krita from its own defaults: the shortcut profile Sara ships as
## "Krita", the palette `krita_grey.tres` drawn after Krita's default dark grey,
## the `krita` layout after the default workspace with every docker in the right
## column, and the HSV triangle, since Krita's Advanced Colour Selector ships
## as `3|0|5|0`, a triangle inside a hue ring. For Photoshop: the shortcut profile "Photoshop",
## `photoshop_dark.tres`, the `photoshop` layout after the Essentials workspace,
## and the HSV square, Photoshop's Color Picker of a saturation and brightness
## square beside its hue. Ctrl+0 shows actual pixels under Krita, whose Reset
## Zoom is 100 per cent, and the whole picture under Sara and Photoshop, whose
## Ctrl+0 is Fit on Screen, and the whole picture stays Sara's default.
##
## For Procreate, from its handbook: the shortcut profile
## "Procreate" of its iPad keyboard shortcuts, `procreate_dark.tres` after its
## near black interface, the `procreate` layout with the fewest dockers open and
## the Brush Presets and Layers at the top right where its Brush Library and
## Layers buttons stand, and the HSV square, since Procreate's Colour Disc is a
## hue ring around a saturation and brightness area in plain RGB, which is that
## shape's ring and model. Its quick pinch and its Command and 0 both fit the
## canvas to the screen, so Ctrl+0 shows the whole picture. Its two-finger tap
## undoes and its three-finger tap redoes, which `SaTwoFingers` gives under
## every program.
##
## For Clip Studio Paint, from memory of its stock install: the shortcut profile
## "Clip Studio Paint", `clip_studio_dark.tres` after its default dark
## interface, the `clip_studio` layout after its default workspace, and the HSV
## square, since its Color Wheel palette ships as a hue ring around a saturation
## and value square. Its Ctrl+0 is Fit to Navigator, the whole picture. A later
## program is one more entry.
const PROGRAMS: Dictionary = {
    "krita":
    {"title": "Krita", "shortcuts": "Krita", "palette": "krita", "layout": "krita", "picker": "hsv_triangle", "zoom": "pixels"},
    "photoshop":
    {
        "title": "Photoshop",
        "shortcuts": "Photoshop",
        "palette": "photoshop",
        "layout": "photoshop",
        "picker": "hsv_square",
        "zoom": "whole",
    },
    "procreate":
    {
        "title": "Procreate",
        "shortcuts": "Procreate",
        "palette": "procreate",
        "layout": "procreate",
        "picker": "hsv_square",
        "zoom": "whole",
    },
    "clip_studio":
    {
        "title": "Clip Studio Paint",
        "shortcuts": "Clip Studio Paint",
        "palette": "clip_studio",
        "layout": "clip_studio",
        "picker": "hsv_square",
        "zoom": "whole",
    },
}

## The name [method apply] and a release take Sara's own values by, which no
## button carries.
const OWN: String = "sara"

## Sara's own values, a fresh profile's, in force while no program is.
const OWN_VALUES: Dictionary = {
    "shortcuts": "default",
    "palette": "default",
    "layout": "default",
    "picker": "wheel",
    "zoom": "whole",
}

## What the row's title explains, on Quick settings and on Preferences >
## Interface alike.
const HINT: String = "Shortcuts, theme, layout and colour picker as the program you know has them. Your own copies are kept."

## The names Sara's own shortcut map has had in a settings file, every one the
## same map: the empty one, the old "default" and the name the Keyboard
## Shortcuts page lists it under.
const SARA_SHORTCUTS: Array[String] = ["", "default", SaShortcutStore.DEFAULT_PROFILE]

## How long a frame the palette paints its bound boxes and font colours for,
## well under the tenth of a second a frame of the press may take, since the
## frame draws as well.
const THEME_SLICE_USEC: int = 30000

## The store the layout is loaded through, or null to find the one the main
## window holds when a button is pressed. Given by a suite, which builds a store
## of its own over a scratch file.
var _store: DockerLayoutStore = null

## The buttons, program id to its button, so a suite and a capture press
## and read them by the program's id.
var buttons: Dictionary[String, Button] = {}

## The presses not yet ended, the one under way first.
var _presses: Array[Press] = []

## The question a press put up, or null, read by a suite and a capture to
## answer it.
var question: SaMessage = null


func _init(store: DockerLayoutStore = null) -> void:
    name = "ComingFromRow"
    _store = store
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    for program: String in PROGRAMS:
        var button := SaMake.button(self, "ComingFrom_" + program, String(PROGRAMS[program]["title"]))
        button.toggle_mode = true
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.tooltip_text = _tooltip(program) + "\n\n" + _release_hint()
        button.pressed.connect(ask.bind(program))
        buttons[program] = button
    tooltip_text = _release_hint()
    SaSettings.changed.connect(_on_setting_changed)
    refresh()


func _ready() -> void:
    set_process(pressing())


## What a button's press does: asks first, naming the program and every
## preference the press would write over, and writes as [method press] does
## only on Overwrite. A press that would change nothing asks nothing and writes at once,
## and the button shows what is in force until the answer, so a Cancel leaves it
## as it was. A question already up is answered first rather than stacked on.
func ask(program: String) -> void:
    if not PROGRAMS.has(program):
        return
    refresh()
    if question != null and is_instance_valid(question) and question.visible:
        return
    var answer := OWN if program == _held() else program
    if SaComingFromQuestion.changes(answer, _layout_store()).is_empty():
        _write(answer)
        return
    question = SaComingFromQuestion.ask(self, answer, _layout_store(), _write.bind(answer))


## Sets *program*'s preferences, each through its own writer, and shows the
## button pressed, or, when *program* is the one in force or on its way to it,
## puts Sara's own values back and shows no button pressed. What Overwrite
## does, public so a suite and a capture write without the question.
func press(program: String) -> void:
    if not PROGRAMS.has(program):
        return
    _write(OWN if program == _held() else program)


## Starts writing *answer*'s values, a program's or [constant OWN], the one
## the question was asked about, so a setting changed while it was up does not
## turn an Overwrite into another answer.
func _write(answer: String) -> void:
    if not is_inside_tree():
        apply(answer, _layout_store())
        refresh()
        program_applied.emit(answer)
        return
    _presses.append(Press.new(answer, _layout_store(), get_tree()))
    refresh()
    set_process(true)


## Whether a press has writers still to run.
func pressing() -> bool:
    return not _presses.is_empty()


## Shows the program in force pressed and the others not, silently. While a
## press is under way, its program, which is what the settings are on their way
## to, and no button for a release.
func refresh() -> void:
    var held := _held()
    for program: String in buttons:
        buttons[program].set_pressed_no_signal(program == held)


## One writer of the press under way a frame, and the press ended once its last
## has run.
func _process(_delta: float) -> void:
    if not pressing():
        set_process(false)
        return
    var under_way: Press = _presses.front()
    if not under_way.step():
        return
    _presses.pop_front()
    if not pressing():
        set_process(false)
    refresh()
    program_applied.emit(under_way.program)


## A row freed with a press under way, the window closed in its frames, ends
## every press at once rather than leaving a program half set.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        for waiting: Press in _presses:
            apply(waiting.program, waiting.store if is_instance_valid(waiting.store) else null)
        _presses.clear()


## The answer the settings are in, or on their way to while a press is under
## way: a program, [constant OWN] for a release under way, or what
## [method in_force] reads.
func _held() -> String:
    return (_presses.back() as Press).program if pressing() else in_force(_layout_store())


## The values *answer* sets: a program's, Sara's own for [constant OWN], and
## none for a name the row does not know.
static func values_of(answer: String) -> Dictionary:
    if answer == OWN:
        return OWN_VALUES
    return PROGRAMS.get(answer, {})


## The layout in force, or "" when no store is to be found, which a capture
## reads beside the settings.
func layout_in_force() -> String:
    var store := _layout_store()
    return store.current_preset() if store != null else ""


## Writes every value *program* sets, [constant OWN] being Sara's own. A null
## *store* leaves the layout alone, which is a welcome window opened before
## the main window has one.
static func apply(program: String, store: DockerLayoutStore) -> void:
    var wanted := values_of(program)
    if wanted.is_empty():
        return
    var shortcuts := String(wanted["shortcuts"])
    if not _shortcuts_match(SaSettings.shortcuts_profile, shortcuts):
        SaSettings.shortcuts_profile = shortcuts
        SaShortcutStore.apply_profile(shortcuts)
        EventBus.shortcuts_changed.emit()
    if SaSettings.theme_name != String(wanted["palette"]):
        SaSettings.theme_name = String(wanted["palette"])
    if store != null and store.current_preset() != String(wanted["layout"]):
        store.load_preset(String(wanted["layout"]))
    if SaSettings.color_picker_shape != String(wanted["picker"]):
        SaSettings.color_picker_shape = String(wanted["picker"])
    if SaSettings.reset_zoom != String(wanted["zoom"]):
        SaSettings.reset_zoom = String(wanted["zoom"])


## The program in [constant PROGRAMS] whose every value is in force, or ""
## when the settings match none, Sara's own values among them. A null *store*
## leaves the layout out of the comparison.
static func in_force(store: DockerLayoutStore) -> String:
    for program: String in PROGRAMS:
        if holds(values_of(program), store):
            return program
    return ""


## Whether every one of *wanted*'s values is in force, the layout only when
## *store* is given.
static func holds(wanted: Dictionary, store: DockerLayoutStore) -> bool:
    if not _shortcuts_match(SaSettings.shortcuts_profile, String(wanted["shortcuts"])):
        return false
    if SaSettings.theme_name != String(wanted["palette"]):
        return false
    if store != null and store.current_preset() != String(wanted["layout"]):
        return false
    if SaSettings.color_picker_shape != String(wanted["picker"]):
        return false
    return SaSettings.reset_zoom == String(wanted["zoom"])


## Whether the profile *stored* is the one *wanted* names, every name of Sara's
## own map being one.
static func _shortcuts_match(stored: String, wanted: String) -> bool:
    if SARA_SHORTCUTS.has(wanted):
        return SARA_SHORTCUTS.has(stored)
    return stored == wanted


## The row on a surface, its buttons ahead of the rest: the store handed in, or
## the one `MainDockers` names, looked up the way the Layouts and dockers page
## does.
func _layout_store() -> DockerLayoutStore:
    if _store != null:
        return _store
    if not is_inside_tree():
        return null
    return get_tree().root.find_child("DockerLayoutStore", true, false) as DockerLayoutStore


## A setting this row reads changed somewhere else, so the pressed button is
## read again.
func _on_setting_changed(key: StringName) -> void:
    if key in [&"shortcuts_profile", &"theme_name", &"color_picker_shape", &"reset_zoom"]:
        refresh()


## What a button sets, in words, so a painter knows before pressing.
func _tooltip(program: String) -> String:
    match program:
        "krita":
            return tr(
                "Krita's shortcuts, Krita Grey, a layout like Krita's, the HSV triangle picker and Ctrl+0 at actual pixels."
            )
        "photoshop":
            return tr("Photoshop's shortcuts, Photoshop Dark, a layout like Photoshop's and the HSV square picker.")
        "procreate":
            return tr("Procreate's shortcuts, Procreate Dark, brushes and layers at the top right, and the HSV square picker.")
        "clip_studio":
            return tr(
                "Clip Studio Paint's shortcuts, Clip Studio Dark, a layout like Clip Studio Paint's and the HSV square picker."
            )
    return ""


## The row's hover, beside each button's own: how to go back, and what a
## painter who comes from no program does.
func _release_hint() -> String:
    return tr(
        "Press the lit button again for Sara's own settings, and if you have used no painting program, leave this row as it is."
    )


## One press of a program, its writers run one a frame from the frame after the
## press on, each through the writer [method SaComingFromRow.apply] calls.
class Press:
    extends RefCounted

    ## The program pressed, or [constant SaComingFromRow.OWN] for a release.
    var program: String
    ## The store its layout loads through, or null for none.
    var store: DockerLayoutStore
    var _tree: SceneTree
    ## How many more frames run no writer: the press's own at first, so the
    ## button shows pressed in it, and later the frame a spread writer ended in.
    ## Counted in calls of [method step], one a frame, rather than read off the
    ## engine, so a suite that calls the row's process is a frame each call.
    var _idle: int = 1
    var _next: int = 0
    var _shortcuts_applied: bool = false
    ## Whether the layout's spread load is under way.
    var _loading: bool = false

    func _init(pressed: String, layout_store: DockerLayoutStore, tree: SceneTree) -> void:
        program = pressed
        store = layout_store
        _tree = tree

    ## Runs the next writer, or waits, and answers whether the press has ended.
    func step() -> bool:
        if _loading or SaTheme.repainting():
            # The palette's last slice and the layout's announcement come on
            # the tree's frame signal, ahead of the process of the frame they
            # end in, which so runs no writer of its own.
            _idle = 1
            return false
        if _idle > 0:
            _idle -= 1
            return false
        var wanted := SaComingFromRow.values_of(program)
        match _next:
            0:
                var shortcuts := String(wanted["shortcuts"])
                if not SaComingFromRow._shortcuts_match(SaSettings.shortcuts_profile, shortcuts):
                    SaSettings.shortcuts_profile = shortcuts
                    SaShortcutStore.apply_profile(shortcuts)
                    _shortcuts_applied = true
            1:
                # A frame of its own, since every surface that shows a chord
                # follows it.
                if _shortcuts_applied:
                    EventBus.shortcuts_changed.emit()
            2:
                var palette := String(wanted["palette"])
                if SaSettings.theme_name != palette:
                    SaTheme.use_named_in_slices(palette, THEME_SLICE_USEC, _tree)
                    SaSettings.theme_name = palette
            3:
                var layout := String(wanted["layout"])
                if store != null and is_instance_valid(store) and store.current_preset() != layout:
                    _load(layout)
            4:
                if SaSettings.color_picker_shape != String(wanted["picker"]):
                    SaSettings.color_picker_shape = String(wanted["picker"])
                if SaSettings.reset_zoom != String(wanted["zoom"]):
                    SaSettings.reset_zoom = String(wanted["zoom"])
        _next += 1
        return _next > 4

    func _load(layout: String) -> void:
        _loading = true
        await store.load_preset_spread(layout, _tree)
        _loading = false
