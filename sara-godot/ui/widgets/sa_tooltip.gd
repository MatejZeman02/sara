## A tooltip long enough to explain something wraps instead of leaving the
## screen.
##
## **Godot draws a tooltip as one unwrapped line.** `Viewport._gui_show_tooltip_at`
## builds a `PopupPanel` under the theme type `TooltipPanel`, puts a plain
## `Label` under `TooltipLabel` inside it, sets the text and never touches
## `autowrap_mode`. Nothing in a theme can change that: wrapping is a property of
## the Label and not a theme item, there is no project setting for it, and the
## only door the engine leaves open is `Control._make_custom_tooltip`, which is a
## virtual on every single Control and so cannot be given to `Button`,
## `OptionButton` and the two dozen other built-ins Sara draws its interface out
## of. So a sentence of three hundred characters is drawn three hundred
## characters wide, and on a 1920 window it is cut off at both edges at once.
##
## **What this does instead.** The panel is added as a child of the control that
## carries the tooltip, `tooltip_owner.add_child(gui.tooltip_popup)`, which means
## the whole thing walks through `SceneTree.node_added` on its way in. One
## connection catches every tooltip in the application, the built-ins and a
## third-party module's alike, before the engine measures the panel: the sizing
## happens on the lines after that `add_child`, so a Label told to wrap here is
## already wrapped when `get_contents_minimum_size()` asks it how big it is.
##
## **A short tooltip is left exactly as it was.** Wrapping is turned on only for
## a label whose one line would be wider than the maximum, so the two hundred
## short tooltips already in the tree keep the shape the painter knows and only
## the long ones change.
class_name SaTooltip
extends RefCounted

## The widest a tooltip may draw before it wraps, in the tooltip panel's own
## units, which are the root window's logical units.
##
## Not through `SaUI.px`. The panel carries its own `content_scale_factor`, set
## to the root's scale by the engine on the line after the label is built, so a
## width in physical pixels would be scaled a second time and a 2x display would
## wrap at half the words.
const MAX_WIDTH: int = 420

## How much of the window a tooltip may take, whichever is the smaller of this
## and [constant MAX_WIDTH].
##
## Half, so there is room to place the panel beside the pointer on the side the
## pointer is not on, which is what the engine does when the tooltip would run
## off the right edge.
const MAX_WINDOW_FRACTION: float = 0.5


## Catches every tooltip this tree shows from here on.
##
## Called once, beside the global theme, since this is the tooltip's half of what
## the theme cannot say. Connecting twice would wrap twice, which is harmless and
## still worth not doing.
static func install(tree: SceneTree) -> void:
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)


## The width a tooltip in *root* may draw to before it wraps.
static func max_width_for(root: Window) -> float:
    if root == null:
        return float(MAX_WIDTH)
    var room := root.get_visible_rect().size.x * MAX_WINDOW_FRACTION
    return minf(float(MAX_WIDTH), maxf(1.0, room))


## Turns wrapping on for *label* when its one line would be wider than
## *max_width*, and answers whether it did.
##
## `custom_minimum_size` is what decides the wrap, in both directions. A Label
## with autowrap on reports a minimum width of one, so without the width the
## panel would shrink to the longest word and wrap the sentence into a column,
## and it reports the height of a single line until it has been shaped at a
## width, so without the height the engine places a panel one line tall and the
## eight lines that arrive after it hang off the bottom of the window.
##
## The width it is shaped at is the label's `custom_maximum_size`, not a `size.x`
## written here. `Label::_shape` wraps against `get_combined_maximum_size().x`
## when one is set and against the label's own width otherwise, and a full-rect
## label inside the engine's tooltip panel is nought wide until the panel is
## placed. So the cap is declared and the label shapes itself inside it, and the
## height that comes back is the height the panel needs on the first pass.
##
## Writing `size.x` instead asks the engine to reshape in the same breath, and works,
## but a full-rect control's width belongs to its parent: `Control::_set_size` warns
## on every wrapped tooltip that the size will be overridden after `_ready`, which a
## capture reports as a problem line of a run that shows one. The anchors were tried
## as the silence and moved the panel off the window, and `set_deferred` costs the
## height, so neither is used.
##
## Not called `wrap`, which is a GDScript built-in: a static method of that name
## parses, and every call to it anywhere in the tree then fails to, on the
## built-in's three arguments rather than on these two.
static func wrap_label(label: Label, max_width: float) -> bool:
    if label == null or label.autowrap_mode != TextServer.AUTOWRAP_OFF:
        return false
    if label.get_minimum_size().x <= max_width:
        return false
    label.custom_maximum_size = Vector2(max_width, label.custom_maximum_size.y)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size = Vector2(max_width, label.get_minimum_size().y)
    return true


## Every tooltip label on its way into the tree, with its key names taken out
## where `SaKeyLabels` says no key can be pressed, and wrapped if it is too wide.
##
## The theme type variation is the test, not the class: the engine sets
## `TooltipLabel` on the label it builds and on nothing else, so a Label Sara
## puts on screen for its own reasons is not touched.
static func _on_node_added(node: Node) -> void:
    var label := node as Label
    if label == null or label.theme_type_variation != &"TooltipLabel":
        return
    # A key nobody can press is taken out before the label is measured, so a
    # tablet with no keyboard is shown the sentence alone.
    label.text = SaKeyLabels.without_keys(label.text)
    var tree := label.get_tree()
    wrap_label(label, max_width_for(tree.root if tree != null else null))


## Sets a control's tooltip: it puts a sentence on the control, so a scenario can
## hover a tooltip of a stated length rather than depending on one the interface
## happens to carry, `{"tooltip": {"control": "OpenBtn", "text": "..."}}`.
##
## `{"tooltip": {"report": true}}` answers what the tooltip showing right now
## measured. The panel is a `Window`, so the `windows` block of the dump carries
## its rectangle as well, and this line is what names it among the others.
##
## `{"tooltip": {"look": "ColorPair"}}` answers what a tooltip on that control
## would be drawn in, from a panel built there the way the engine builds one and
## freed again. It exists because a capture cannot show a tooltip in the root
## window at all, so the top bar's half of a comparison has to be read without
## one on screen.
static func capture_tooltip(tree: SceneTree, spec: Variant) -> String:
    var wanted: Dictionary = spec if spec is Dictionary else {}
    if wanted.get("report", false):
        return _report(tree.root)
    if wanted.has("look"):
        return _look_on(tree.root, String(wanted["look"]))
    var control_name := String(wanted.get("control", ""))
    if control_name.is_empty():
        return "SaCapture: tooltip wants a control, or report"
    var control := tree.root.find_child(control_name, true, false) as Control
    if control == null:
        return "SaCapture: no control called '%s' to put a tooltip on" % control_name
    control.tooltip_text = String(wanted.get("text", ""))
    return (
        "SaCapture: tooltip of %d character(s) on %s at %s"
        % [control.tooltip_text.length(), control_name, control.get_screen_position()]
    )


## The tooltip on screen: its panel's rectangle, the label's lines and whether it
## sits inside the window. An empty answer when nothing is showing.
static func _report(root: Window) -> String:
    var label := _live_label(root)
    if label == null:
        return "SaCapture: no tooltip is showing, %s" % _nothing_showing_because(root)
    var panel := label.get_parent() as Window
    var rect := Rect2(Vector2(panel.position), Vector2(panel.size))
    var room := root.get_visible_rect()
    return (
        "SaCapture: tooltip %s, %d line(s), wrapped %s, inside the window %s, %s"
        % [
            rect,
            label.get_line_count(),
            label.autowrap_mode != TextServer.AUTOWRAP_OFF,
            room.encloses(rect),
            look(panel, label) + ", text '%s'" % label.text,
        ]
    )


## What *panel* and *label* are drawn in: where the panel's box comes from, its
## border and margin, the label's size and colour, the panel's scale and the
## node the theme is read from.
static func look(panel: Window, label: Label) -> String:
    var box := panel.get_theme_stylebox(&"panel")
    var flat := box as StyleBoxFlat
    return (
        "box %s border %d margin %d bg alpha %.2f, text %d %s, scale %.2f, theme from %s"
        % [
            box_source(box),
            flat.border_width_left if flat != null else -1,
            int(box.content_margin_left) if box != null else -1,
            flat.bg_color.a if flat != null else -1.0,
            label.get_theme_font_size(&"font_size"),
            label.get_theme_color(&"font_color").to_html(false),
            panel.content_scale_factor,
            _theme_holder(panel),
        ]
    )


static func _look_on(root: Window, control_name: String) -> String:
    var control := root.find_child(control_name, true, false) as Control
    if control == null:
        return "SaCapture: no control called '%s' to read a tooltip's look on" % control_name
    var panel := PopupPanel.new()
    panel.theme_type_variation = &"TooltipPanel"
    var label := Label.new()
    label.theme_type_variation = &"TooltipLabel"
    panel.add_child(label)
    control.add_child(panel)
    var answer := "SaCapture: tooltip look on %s in %s, %s" % [control_name, control.get_window().title, look(panel, label)]
    control.remove_child(panel)
    panel.free()
    return answer


## Which theme a box was read out of, by identity, since two boxes of the same
## class can only be told apart that way.
static func box_source(box: StyleBox) -> String:
    if box == null:
        return "none"
    if SaUI.shared_theme != null and box == SaUI.shared_theme.get_stylebox(&"panel", &"TooltipPanel"):
        return "shared"
    var project := ThemeDB.get_project_theme()
    if project != null and project.has_stylebox(&"panel", &"TooltipPanel"):
        if box == project.get_stylebox(&"panel", &"TooltipPanel"):
            return "project"
    if box == ThemeDB.get_default_theme().get_stylebox(&"panel", &"TooltipPanel"):
        return "engine"
    return "other"


## The nearest node above *node* that holds a theme, or where the chain was cut
## before one was found.
static func _theme_holder(node: Node) -> String:
    var at := node
    while at != null:
        var held: Theme = null
        if at is Control:
            held = (at as Control).theme
        elif at is Window:
            held = (at as Window).theme
        else:
            return "nothing, cut at %s" % at.name
        if held != null:
            return "%s (%s)" % [at.name, "shared" if held == SaUI.shared_theme else "another theme"]
        at = at.get_parent()
    return "nothing"


## What to look at when no tooltip is showing.
##
## The engine only starts its tooltip timer for a window that has focus, and a
## capture never gives one: `SaInputDriver` injects an `InputEventMouseMotion`
## and there is no window manager under the nested weston to hand the root
## window the focus a real desktop would. So a hover over a control in the root
## reports nothing at all, and a reader with "no tooltip is showing" and nothing
## else spends an hour deciding whether the tooltip, the hover or the report is
## at fault.
##
## Naming the window and its focus turns that into one line. A `click` on the
## docker first is what makes the difference, because a click is what grabs an
## embedded window's focus.
static func _nothing_showing_because(root: Window) -> String:
    var hovered := root.gui_get_hovered_control()
    var window := hovered.get_window() if hovered != null else null
    for child in root.find_children("*", "Window", true, false):
        var sub := child as Window
        if sub != null and sub.visible and sub.gui_get_hovered_control() != null:
            hovered = sub.gui_get_hovered_control()
            window = sub
            break
    if hovered == null:
        return "and nothing is hovered"
    return (
        "hovered %s in %s, focused %s, root focused %s"
        % [
            hovered.name,
            window.title if window != null else "<no window>",
            window.has_focus() if window != null else false,
            DisplayServer.window_is_focused(root.get_window_id()),
        ]
    )


## The tooltip label on screen, or null. Found by the variation the engine
## stamps on it, the same test `_on_node_added` makes.
static func _live_label(node: Node) -> Label:
    var label := node as Label
    if label != null and label.theme_type_variation == &"TooltipLabel":
        return label
    for child in node.get_children():
        var found := _live_label(child)
        if found != null:
            return found
    return null
