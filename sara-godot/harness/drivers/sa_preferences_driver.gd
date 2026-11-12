## The Preferences window: its pages, its search, its shortcut rows and the
## swatches on its Colour Themes page.
##
## **One class because Preferences is one window**, an embedded subwindow an
## injected click does not route into, with Wayland refusing to place the
## pointer over it. Without a way in that is not the mouse every page after the
## first is unphotographable, and a page nobody has looked at can ship with a
## button off its bottom.
##
## The Colour Themes swatch is here and not beside the filter dialogs, although
## both are "the Filter menu and a docker", because it is a Preferences page: it
## needs Preferences open on that page and it touches nothing else.
##
## Reached by path from the step table rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaPreferencesDriver
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for its tree.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Selects a Preferences page: with Preferences already open.
func show_page(title: String) -> void:
    var tree := _run.tree()
    for node in tree.root.find_children("*", "Window", true, false):
        var settings := node as SaSettingsWindow
        if settings != null and settings.show_page(title):
            return
    push_warning("SaCapture: no open Preferences page called '%s'" % title)


## Moves a page row's control: on any open page, Preferences' most often, as a
## hand would, `{"page_row": {"row": "popup_palette", "value": true}}`, and
## without `"value"` only reads it. What it answers, and what an optional
## `"page"` picks, is [method SaPageDrive.capture]'s.
##
## A row no open page holds ends a scenario there, with an error naming the row
## and the pages it looked on, rather than printing one line and carrying on,
## because a scenario that asks the wrong page for a row that moved would go on
## to shoot steps of a setting never switched on. A door session has no steps to skip and only hears the error.
func page_row(spec: Variant) -> void:
    var said := SaPageDrive.capture(_run.tree(), spec)
    if not said.begins_with(SaPageDrive.MISS):
        print(said)
        return
    push_error(said)
    _run.step_index = _run.steps.size()


## Searches Preferences: with Preferences already open, `{"prefs_search":
## "pressure"}`, and `{"prefs_search": ""}` clears it. Through the window rather
## than through the field, for the reason `show_page` gives.
func search_preferences(text: String) -> String:
    var tree := _run.tree()
    for node in tree.root.find_children("*", "Window", true, false):
        var settings := node as SaSettingsWindow
        if settings != null:
            settings.search.apply(text)
            return "SaCapture: Preferences searched for '%s'" % text
    return "SaCapture: no open Preferences to search"


## Rebinds a shortcut: on the open Keyboard Shortcuts page, `{"shortcut":
## {"action": "edit_redo", "chord": "Ctrl+Z", "search": "do"}}`. `start_again`
## presses the button that goes back to the shipped profile, and the reply ends on
## the line under the row it shows, and `{"press": "Reset_layer_clear"}` presses
## the row's Reset or Clear.
##
## Through the page rather than through the store, because what a capture is
## for is the page's own answer: the row it repaints and the rows it marks.
## `search` filters first, so a conflict below the fold is in the picture.
## `focus` gives the page's search field the keyboard, the way a click on it
## does, so a dump reads where the keyboard is before and after a switch.
func rebind_shortcut(spec: Dictionary) -> String:
    var editor := open_shortcuts_page()
    if editor == null:
        return "SaCapture: no open Keyboard Shortcuts page to rebind on"
    if spec.has("search"):
        editor.filter(String(spec["search"]))
    if bool(spec.get("focus", false)):
        editor.search.grab_focus()
    # `listen` puts a row into the state a click on its chord button leaves it
    # in, so the next injected key is read as the new chord.
    if spec.has("listen"):
        editor.begin_capture(StringName(String(spec["listen"])))
    if spec.has("action"):
        editor.rebind(StringName(String(spec["action"])), String(spec.get("chord", "")))
    if bool(spec.get("start_again", false)):
        editor.start_again()
    # `press` presses a row's button by its name, `Reset_<action>` or
    # `Clear_<action>`, the way a click would, for the reason `listen` is here.
    if spec.has("press"):
        var button := editor.find_child(String(spec["press"]), true, false) as Button
        if button == null or button.disabled:
            return "SaCapture: no lit button called '%s' to press" % spec["press"]
        button.pressed.emit()
    # `show` reads a row back without touching it, which is how a capture says
    # what the key it just sent did to the row that was listening.
    var shown := String(spec.get("show", spec.get("action", spec.get("listen", ""))))
    return (
        "SaCapture: shortcut '%s' -> '%s', showing '%s', row '%s' reads '%s', listening '%s', conflicts %s, line '%s'"
        % [
            spec.get("action", ""),
            spec.get("chord", ""),
            spec.get("search", ""),
            shown,
            editor.chord_shown(StringName(shown)),
            String(editor.listening),
            str(editor.conflicting_actions()),
            editor.clash_line(StringName(shown)),
        ]
    )


## Switches the shortcut profile: the open Keyboard Shortcuts page goes to a
## shipped or saved profile the way its dropdown would, so a capture can show what
## each one answers to without a popup a headless run cannot open,
## `{"shortcut_profile": "Krita"}`.
func select_shortcut_profile(profile: String) -> String:
    var editor := open_shortcuts_page()
    if editor == null:
        return "SaCapture: no open Keyboard Shortcuts page to switch profile on"
    editor.select_profile(profile)
    return "SaCapture: profile -> '%s'" % profile


## Imports Krita shortcuts: a `.shortcuts` file, the way choosing it in the file
## picker would, since a native file dialog is as unreachable from a scenario as
## any other embedded window, `{"krita_import": "<path>"}`.
func import_krita_file(path: String) -> String:
    var editor := open_shortcuts_page()
    if editor == null:
        return "SaCapture: no open Keyboard Shortcuts page to import into"
    editor.import_krita_file(path)
    return "SaCapture: imported '%s'" % path


## The Keyboard Shortcuts page inside whichever Preferences window is open, or
## null. Found through its rows host, because the page itself has no name a
## `find_child` would match and the window rebuilds it on every page switch.
func open_shortcuts_page() -> SaShortcutsPage:
    var tree := _run.tree()
    for node in tree.root.find_children("*", "Window", true, false):
        var settings := node as SaSettingsWindow
        if settings == null:
            continue
        var rows := settings.find_child("ShortcutRows", true, false)
        if rows == null:
            continue
        var editor := rows.get_parent() as SaShortcutsPage
        if editor != null:
            return editor
    return null


## Changes one theme colour: on the open theme colours page, which forks a
## shipped palette first, `{"swatch": {"key": "accent_primary", "color":
## "#3060ff"}}`. `{"swatch": {"delete": true}}` deletes the active custom
## palette by pressing the page's Delete button. Preferences has to be open there.
func swatch(spec: Dictionary) -> void:
    var tree := _run.tree()
    var page: SaColorThemesPage = null
    for node in tree.root.find_children("*", "SaColorThemesPage", true, false):
        if not node.is_queued_for_deletion():
            page = node
    if page == null:
        push_warning("SaCapture: no Colour Themes page is open")
        return
    if spec.get("delete", false):
        var was := SaTheme.palette_id
        page.delete_button.pressed.emit()
        print("SaCapture: swatch deleted %s, now %s" % [was, SaTheme.palette_id])
        return
    var key := String(spec.get("key", "accent_primary"))
    var color := Color(String(spec.get("color", "#ffffff")))
    page.set_swatch(key, color)
    print("SaCapture: swatch %s = %s on %s" % [key, color.to_html(), SaTheme.palette_id])


## Sets Preferences, `{"prefs": {"autosave_interval_minutes": 0.05}}`, so a scenario
## can shorten a timer it would otherwise wait two minutes for. The value is written
## to the settings file the run is using, which for an offscreen run is the checkout's
## own under scratch/, and not the person's.
##
## Here rather than on the runner because it asks nothing of a run and
## everything of `SaSettings`, which is this driver's subject.
func set_prefs(spec: Dictionary) -> void:
    for key: String in spec:
        SaSettings.set(key, spec[key])
        print("SaCapture: prefs %s = %s" % [key, str(SaSettings.get(key))])
