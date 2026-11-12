## What a capture can ask the Workspace page, split out of the page itself.
##
## Its own file because everything here exists so a scenario can drive and
## measure the page, and nothing here runs when a person uses it. The page keeps
## the geometry accessors, because its own scale correction needs the same
## numbers.
##
## The entry point is `capture_sliders` here rather than a static and a forward
## on the page, so `ui` never names the harness for the sake of a detour.
class_name SaWorkspaceCapture
extends RefCounted

var _page: SaWorkspacePage = null

## Where a capture last marked a slider's track, in physical screen pixels, so a
## later step can print how far it travelled and how much it stretched.
var _marks: Dictionary = {}

## Where the page's scroll last stood, so a wheel step can be measured against
## it rather than against a number a reader has to remember.
var _scroll_mark: float = -1.0

## One capture per open page, so a scenario's steps share the marks between
## them: a scenario marks a track in one step and measures it in the next, and a fresh
## object each time would answer nothing.
##
## The page sits behind a `WeakRef` beside its capture. A page is a `Node` rather
## than a `RefCounted`, so a Preferences window that closed leaves a null here
## and its entry is dropped on the next step rather than kept for the run.
static var _live: Array[Dictionary] = []


func _init(page: SaWorkspacePage) -> void:
    _page = page


## Drives the Interface sliders: `{"workspace": {...}}`, with `{"pointer":
## true}` for the rows of the pointer dropdown and `{"lead": true}` for the
## cursor lead's, both read off an open Pen and tablet page.
##
## Through the page rather than through SaSettings, because the whole claim is
## about where the page's own control ends up, and a setting written from outside
## it proves nothing about that. The two report steps are answered by the page
## that holds the two rows, because what they read back is its own rows. That is
## the Pen and tablet page, where the rows sit beside the pen, and the step
## keeps the name it had while they were Workspace's so an older scenario still
## reads.
##
## **`{"welcome": true}` drives the welcome window's Quick settings pane**,
## which carries the same scale slider this page does and finds it the same way.
## The spec says which of the two surfaces it means, so neither the search below
## nor any other scenario's spec has to change.
static func capture_sliders(tree: SceneTree, spec: Dictionary) -> String:
    if spec.has("welcome"):
        return WelcomeQuickSettingsPane.capture_pane(tree.root, spec)
    if spec.has("pointer") or spec.has("lead"):
        var tablet := _open_page(tree, "SaTabletPage") as SaTabletPage
        if tablet == null:
            return "SaCapture: no open Pen and tablet page, where the pointer and cursor lead rows are"
        return "SaCapture: %s" % (tablet.pointer_report() if spec.has("pointer") else tablet.lead_report())
    var page := _open_page(tree, "SaWorkspacePage") as SaWorkspacePage
    if page == null:
        return "SaCapture: no open Interface page, whose Workspace part this drives"
    return _capture_for(page).drive(spec)


## The open settings page whose class is *page_class*, or null. Every `Window`
## that shows pages is searched and then the page under it, which is the shape
## the search had while it lived on the Workspace page itself.
static func _open_page(tree: SceneTree, page_class: String) -> SaSettingsPage:
    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("show_page"):
            continue
        for candidate in node.find_children("*", "VBoxContainer", true, false):
            var page := candidate as SaSettingsPage
            if page != null and (page.get_script() as Script).get_global_name() == page_class:
                return page
    return null


## The capture *page* is driven through, made once and reused, with the entries
## whose page has gone dropped on the way past.
static func _capture_for(page: SaWorkspacePage) -> SaWorkspaceCapture:
    var answer: SaWorkspaceCapture = null
    for i in range(_live.size() - 1, -1, -1):
        var held: Variant = (_live[i]["page"] as WeakRef).get_ref()
        if held == null:
            _live.remove_at(i)
        elif held == page:
            answer = _live[i]["capture"]
    if answer == null:
        answer = SaWorkspaceCapture.new(page)
        _live.append({"page": weakref(page), "capture": answer})
    return answer


## `{"mark": "ui_scale"}` remembers where the grip is, `{"slider": "ui_scale",
## "value": 1.4}` moves it the way the hand does, and `{"measure": "ui_scale"}`
## prints how far the grip travelled since the mark. Zero is the whole claim.
##
## `{"fonts": true}` and `{"scroll": ...}` are two more measurements: which face
## each part of the window is drawn in, and how far one wheel notch moves the
## page.
func drive(spec: Dictionary) -> String:
    if spec.has("fonts"):
        return font_report()

    if spec.has("scroll"):
        return _scroll(spec)

    if spec.has("mark"):
        var marked := _page.slider_named(String(spec["mark"]))
        if marked == null:
            return "SaCapture: the Workspace page has no '%s' slider" % spec["mark"]
        var rect := _page.track_screen_rect(marked)
        _marks[String(spec["mark"])] = rect
        return (
            "SaCapture: marked '%s' track at (%.1f, %.1f) %.1f by %.1f"
            % [spec["mark"], rect.position.x, rect.position.y, rect.size.x, rect.size.y]
        )

    if spec.has("measure"):
        return _measure(String(spec["measure"]))

    if spec.has("press") or spec.has("release"):
        return _grab(String(spec.get("press", spec.get("release", ""))), spec.has("press"))

    var key := String(spec.get("slider", "ui_scale"))
    var slider := _page.slider_named(key)
    if slider == null:
        return "SaCapture: the Workspace page has no '%s' slider" % key
    if spec.has("value"):
        slider.value = float(spec["value"])
    return (
        "SaCapture: '%s' = %.2f (min %.2f, step %.3f), held %s, ui scale %.2f, font %d px"
        % [
            key,
            slider.value,
            slider.min_value,
            slider.step,
            "yes" if _page.held == slider else "no",
            SaUI.scale(),
            SaUI.get_font_size()
        ]
    )


## How far the track moved and how much it stretched since the mark. Both zero
## is the whole claim: the pointer still means the same value it did.
func _measure(key: String) -> String:
    var measured := _page.slider_named(key)
    if measured == null or not _marks.has(key):
        return "SaCapture: nothing marked on '%s'" % key
    var was: Rect2 = _marks[key]
    var now := _page.track_screen_rect(measured)
    var residual := _page.residual
    return (
        (
            "SaCapture: '%s' track (%.1f, %.1f) %.1f wide -> (%.1f, %.1f) %.1f wide, moved (%.1f, %.1f), "
            + "stretched %.1f, grip left behind (%.1f, %.1f), held %s, ui scale %.2f, font %d px"
        )
        % [
            key,
            was.position.x,
            was.position.y,
            was.size.x,
            now.position.x,
            now.position.y,
            now.size.x,
            now.position.x - was.position.x,
            now.position.y - was.position.y,
            now.size.x - was.size.x,
            residual.x,
            residual.y,
            "yes" if _page.held == measured else "no",
            SaUI.scale(),
            SaUI.get_font_size(),
        ]
    )


## A real press or release on the grabber, so the drag path under test is the
## one a hand takes: `drag_started` and `drag_ended` are what defer the write,
## and a capture that set the value alone would never reach either.
##
## An injected motion never arrives at a Control's `gui_input`, so the value in
## between is written directly, which is the same call the motion would make.
func _grab(key: String, pressed: bool) -> String:
    var slider := _page.slider_named(key)
    var tree := _page.get_tree()
    if slider == null or tree == null:
        return "SaCapture: the Workspace page has no '%s' slider" % key
    var at := _page.grip_screen_point(slider)
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    Input.parse_input_event(event)
    return (
        "SaCapture: %s '%s' at (%.1f, %.1f), held %s"
        % ["pressed" if pressed else "released", key, at.x, at.y, "yes" if _page.held == slider else "no"]
    )


## `{"scroll": {"mark": true}}` remembers where the page stands and
## `{"scroll": {"measure": true}}` says how far it moved since, so a real
## `{"wheel": ...}` step in between is what is being measured rather than a
## number this file made up. A slider that seems to slide too fast under the
## wheel is the scroll container moving rather than either slider, so what a
## reader needs is pixels of page per notch of wheel and how much of the page
## that is.
func _scroll(spec: Dictionary) -> String:
    var scroll := _page.page_scroll()
    if scroll == null:
        return "SaCapture: the Workspace page is not in a scroll container"
    var inner: Variant = spec["scroll"]
    var wanted: Dictionary = inner if inner is Dictionary else {}
    var bar := scroll.get_v_scroll_bar()
    var reach: float = maxf(1.0, bar.max_value - bar.page)
    if wanted.get("mark", false):
        _scroll_mark = float(scroll.scroll_vertical)
        return (
            "SaCapture: page scroll marked at %.0f, %.0f px of travel, custom step %.1f" % [_scroll_mark, reach, bar.custom_step]
        )

    var moved: float = float(scroll.scroll_vertical) - _scroll_mark
    var notches: float = maxf(1.0, float(wanted.get("notches", 1)))
    return (
        "SaCapture: page scroll %.0f -> %.0f, moved %.0f px over %.0f notch(es), %.0f per notch, %.1f%% of its %.0f px"
        % [_scroll_mark, float(scroll.scroll_vertical), moved, notches, moved / notches, moved / notches / reach * 100.0, reach]
    )


## Which face and which size each part of Preferences is drawn at.
##
## Both are printed, because a face that looks wrong is as often a size: two sans faces at one size are not something a
## reader can tell apart in a PNG, and one face at two sizes reads as two faces.
func font_report() -> String:
    var window := _page.get_window()
    # The page buttons rather than the list's children, which hold a heading
    # per group as well.
    var buttons: Array = window.get("category_buttons") if window != null else []
    var out := PackedStringArray()
    out.append("SaCapture: interface font is %s, theme size %d px" % [SaSettings.ui_font, SaUI.get_font_size()])
    var shared := SaUI.shared_theme
    out.append("  shared theme font: %s" % _face(shared.default_font if shared != null else null))
    if not buttons.is_empty():
        var button := buttons[0] as Button
        out.append("  category '%s': %s" % [button.text, _drawn(button)])
    for label in _first_labels(_page.get_parent(), 4):
        out.append("  page '%s': %s" % [label.text.substr(0, 20), _drawn(label)])
    return "\n".join(out)


## A control's face and the size it is actually drawn at, which is its own
## override when it has one and the theme's otherwise.
static func _drawn(control: Control) -> String:
    return "%s at %d px" % [_face(control.get_theme_font("font")), control.get_theme_font_size("font_size")]


## The resource path behind a face, or the engine's own when there is no file.
static func _face(font: Font) -> String:
    if font == null:
        return "<none>"
    var path := font.resource_path
    return path if not path.is_empty() else "the engine's built-in font"


## The first few labels of the page, in the order they are drawn.
static func _first_labels(node: Node, want: int, out: Array[Label] = []) -> Array[Label]:
    for child in node.get_children():
        if out.size() >= want:
            return out
        if child is Label:
            out.append(child)
        _first_labels(child, want, out)
    return out
