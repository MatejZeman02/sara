## A page of every kind, in a dialog window, so the page layer is proved on the
## running app rather than only offscreen.
##
## The page layer has no page of its own to be proved on, so this is the surface
## a scenario opens, and the one place where all ten row kinds, both rules, a
## bound row and an unbound one stand next to each other. It stays the layer's
## own proof beside the dialogs that use the layer.
##
## Reached from `{"page_demo": ...}` and from nothing a painter can press, the
## way `workspace_page_capture.gd` is reached.
@tool
class_name SaPageDemo
extends SaDialogWindow


## The demo's binding target: a resource whose setters say they changed, which
## is the half of the spec's answer that covers a value written behind the
## page's back. The other half, a page re-reading everything when it opens, does
## not need this.
class Knobs:
    extends Resource
    var rolloff: bool = true:
        set(value):
            rolloff = value
            emit_changed()
    var exposure: float = 0.0:
        set(value):
            exposure = value
            emit_changed()
    var frames: int = 24:
        set(value):
            frames = value
            emit_changed()
    var mode: int = 0:
        set(value):
            mode = value
            emit_changed()
    var folder: String = "~/pictures":
        set(value):
            folder = value
            emit_changed()
    var ink: Color = Color(0.2, 0.6, 0.9, 1.0):
        set(value):
            ink = value
            emit_changed()
    var library: String = "/usr/share/sara":
        set(value):
            library = value
            emit_changed()
    var knee: float = 0.5:
        set(value):
            knee = value
            emit_changed()
    var shoulder: float = 2.0:
        set(value):
            shoulder = value
            emit_changed()


var knobs := Knobs.new()
var page: SaPage = null

var _rows: VBoxContainer = null


func _init() -> void:
    _init_dialog("PageDemo", SaPage.translated("Every row kind"), Vector2i(660, 840), Vector2i(420, 360))

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margin.add_theme_constant_override(side, SaUI.px(12))
    content.add_child(margin)

    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)

    _rows = VBoxContainer.new()
    _rows.name = "DemoPage"
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_rows)

    page = SaPage.new(declare)
    page.declare_rows()
    page.realize(_rows)


## The declaration, which is the whole of what a page is: no control is made
## here and nothing is added to a tree.
func declare(ui: SaPage) -> void:
    var kinds := ui.section("Every kind")
    (
        kinds
        . toggle("Rolloff", knobs, ^"rolloff")
        . explain("Dims the Knee slider and takes Shoulder off the page.")
        . dims(&"knee")
        . hides(&"shoulder")
    )
    kinds.slider("Exposure", -5.0, 5.0, knobs, ^"exposure").step(0.1).decimals(1).explain("Stops above white.")
    kinds.number("Frames", 1.0, 120.0, knobs, ^"frames")
    kinds.choice("Mode", ["Normal", "Raw", "Heatmap"], knobs, ^"mode")
    kinds.text("Folder", knobs, ^"folder")
    kinds.colour("Ink", knobs, ^"ink")
    kinds.path("Library", knobs, ^"library")
    kinds.action("Reset the knobs", reset)
    kinds.note("A note belongs to no one control, so it has no binding and no value.")
    kinds.custom("Readout", _readout_control())
    # The student's row: no target, so it holds its own value and is read back
    # as `radius.value`, which is what a script's `ui.slider("Radius", 1, 20, 3)` is.
    kinds.slider("Radius", 1.0, 20.0).step(1.0).decimals(0).explain("Bound to itself, the way a filter's is.")

    var under := ui.section("Under the toggle")
    under.slider("Knee", 0.0, 1.0, knobs, ^"knee").explain("Dimmed and dead while Rolloff is off.")
    under.number("Shoulder", 0.0, 8.0, knobs, ^"shoulder").explain("Off the page while Rolloff is off.")


## What the action row's button does, so the scenario has something to press
## that moves more than one row.
func reset() -> void:
    knobs.rolloff = true
    knobs.exposure = 0.0
    knobs.knee = 0.5


## Opens the demo under Main, building it on the first call and keeping it, the
## way `MainDialogs` keeps every dialog it opens.
static func open(tree: SceneTree) -> SaPageDemo:
    var found := find_in(tree)
    if found == null:
        var host: Node = tree.current_scene if tree.current_scene != null else tree.root
        found = SaPageDemo.new()
        host.add_child(found)
    found.popup_centered()
    return found


## The open demo, or null.
static func find_in(tree: SceneTree) -> SaPageDemo:
    for node in tree.root.find_children("PageDemo", "Window", true, false):
        var demo := node as SaPageDemo
        if demo != null:
            return demo
    return null


## Opens or closes the demo page: `{"page_demo": "open"}` opens it and `"close"`
## closes it. `"rebuild"` runs the declaration from the top, `"describe"` prints
## what the page says it is, and `"reset"` presses the action row's button.
##
## `{"page_demo": {"row": "rolloff", "value": false}}` moves a control the way a
## hand would, because Preferences and this are embedded subwindows and an
## injected click does not route into one. `{"behind": "knee", "value": 0.9}`
## writes the binding instead, with no control touched, which is the change made
## behind the page's back that the page has to notice.
static func capture(tree: SceneTree, spec: Variant) -> String:
    if spec is String and String(spec) == "open":
        return "SaCapture: page demo open, %s" % JSON.stringify(open(tree).page.describe())
    var demo := find_in(tree)
    if demo == null:
        return "SaCapture: no page demo open"
    if spec is String:
        match String(spec):
            "close":
                demo.hide()
                return "SaCapture: page demo closed"
            "rebuild":
                demo.page.rebuild()
                return "SaCapture: page demo rebuilt, %s" % JSON.stringify(demo.page.describe())
            "describe":
                return "SaCapture: page demo is %s" % JSON.stringify(demo.page.describe())
            "reset":
                demo.reset()
                return "SaCapture: page demo reset"
        return "SaCapture: no page demo command '%s'" % spec
    var options: Dictionary = spec if spec is Dictionary else {}
    var key := StringName(String(options.get("row", options.get("behind", ""))))
    var row := demo.page.row(key)
    if row == null:
        return "SaCapture: page demo has no row '%s'" % String(key)
    var value: Variant = options.get("value", null)
    if options.has("behind"):
        row.target.set_indexed(row.property_path(), value)
        return "SaCapture: '%s' written behind the page, control now %s" % [String(key), row.reads()]
    row.drive(value)
    return "SaCapture: '%s' moved to %s, binding now %s" % [String(key), row.reads(), row.read()]


## The label with nothing declared behind it, which is what `custom` is for.
func _readout_control() -> Control:
    var label := Label.new()
    label.name = "DemoReadout"
    label.text = SaPage.translated("A control the page handed over.")
    return label
