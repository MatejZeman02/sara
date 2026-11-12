## The one line on screen that says the quick mask is on.
##
## A painter can turn the quick mask on by a chord and then not be able to
## paint. Without this strip nothing on the canvas says the mode is on beyond
## the red tint, which over an empty selection tints everything and reads as a
## broken canvas rather than as a mode. Sara has no status bar, so this is a strip over the top of the main
## surface, in window space rather than document space so it neither zooms nor
## turns with the view, shown while `SaSelection.editing` is on and gone the
## frame it is off. It names the mode and the key that leaves it, because a
## painter who did not ask for a mode wants the way out more than the name.
##
## The same strip says when the brush paints a layer's mask, with the layer's
## name and the way back, and says it with words alone. The quick mask tints
## what the selection leaves out, and a layer mask hides the picture the painter
## is looking at, so a tint over it would hide the work.
##
## Polls the document once a frame, the way `SaCanvasOverlay` watches the
## symmetry: the document under the view changes on File > New and File > Open,
## and one comparison a frame is cheaper than following every swap.
class_name SaQuickMaskBanner
extends PanelContainer

const NODE_NAME := "QuickMaskBanner"

var _canvas: SaCanvas = null
var _label: Label = null


## The canvas is a constructor argument rather than an assignment, because a
## class writes its own members only. Defaulted so that `.new()` still works the
## way Godot expects of a Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas


## Puts a banner over *host*, the window-space control the main surface routes
## its input through, reading the document of *canvas*.
static func attach_to(host: Control, canvas: SaCanvas) -> SaQuickMaskBanner:
    var banner := SaQuickMaskBanner.new(canvas)
    banner.name = NODE_NAME
    host.add_child(banner)
    return banner


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_CENTER_TOP)
    grow_horizontal = GROW_DIRECTION_BOTH
    grow_vertical = GROW_DIRECTION_END
    var style := StyleBoxFlat.new()
    style.set_content_margin_all(SaUI.pxf(6.0))
    style.content_margin_left = SaUI.pxf(12.0)
    style.content_margin_right = SaUI.pxf(12.0)
    style.set_corner_radius_all(SaUI.px(4))
    style.set_border_width_all(SaUI.px(1))
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag"})
    add_theme_stylebox_override("panel", style)
    _label = SaMake.label(self, "Text", message())
    _label.mouse_filter = MOUSE_FILTER_IGNORE
    SaTheme.bind_font(_label, "text_primary")
    visible = false


func _process(_delta: float) -> void:
    var on := is_on()
    if on:
        var wanted := message()
        if _label.text != wanted:
            _label.text = wanted
        _place()
    visible = on


## Sits just under whatever covers the top of the canvas, the title bar with its
## rows, read off the same group the view fits the document into. The main
## surface spans the whole window under those covers, so a strip at the
## surface's own top edge would draw behind the bar and never be seen.
func _place() -> void:
    var parent := get_parent() as Control
    if _canvas == null or parent == null:
        return
    var uncovered := SaCanvasView.for_canvas(_canvas).get_visible_rect()
    offset_top = uncovered.position.y - parent.get_global_rect().position.y + SaUI.pxf(12.0)
    offset_bottom = offset_top + size.y


## Whether the document under the view is in the quick mask, or its brush
## paints a mask rather than a layer's colour.
func is_on() -> bool:
    var document := _document()
    if document == null:
        return false
    return (document.selection != null and document.selection.editing) or document.mask_target != null


## What the strip says. The quick mask first, because while it is on the brush
## paints the selection whatever the mask target is.
func message() -> String:
    var document := _document()
    if document == null or document.mask_target == null or (document.selection != null and document.selection.editing):
        return tr("Quick Mask: the brush paints the selection. Escape leaves it.")
    var named := _mask_owner(document)
    # A filter's mask belongs to no node and a filter has no thumbnail of its
    # own, so the layer's wording would send the painter to a thumbnail the row
    # does not have.
    if named.is_empty():
        return tr("Filter Mask: the brush paints where the filter works. Click a layer's thumbnail in Layers to paint it.")
    var text := tr("Layer Mask of %s: the brush paints the mask. Click the layer's thumbnail in Layers to paint the layer again.")
    return text % named


func _document() -> SaDocument:
    return _canvas.document if _canvas != null else null


## The name of the layer or group whose mask is under edit, found by asking each
## node rather than the mask, because a group's mask keeps chunks of its own and
## so has no layer to name. Empty for an attached filter's mask, which belongs
## to no node, and `tr()` is the caller's, a static function having none.
static func _mask_owner(document: SaDocument) -> String:
    var nodes: Array[Node] = [document]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        var layer := node as SaLayer
        if layer != null and layer.mask != null and layer.mask == document.mask_target:
            return str(layer.name)
        nodes.append_array(node.get_children())
    return ""
