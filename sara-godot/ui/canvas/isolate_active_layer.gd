## Isolate Active Layer as the painter meets it: the command on `/`, its row in
## the View menu and on the Keyboard Shortcuts page, and the sign on the canvas
## that says isolation is on. What the canvas leaves out and how the view is
## framed is [SaLocalView]'s, in `core`, because the compositor asks it.
##
## A toggle on `/` that hides everything else and frames the layer, as
## Blender's isolate does. Named as Krita names its own, Isolate Active Layer, and `/`
## leaves Switch to the Previous Preset, which keeps it in the Krita profile as
## Krita does and is a command any key can be bound to here.
##
## **The sign sits at the foot of the room between the dockers**, where the
## quick mask's strip at the top cannot cover it, both being able to stand at
## once. It names the layer shown and the way back, the chord the command has
## now rather than the one it shipped with. Polls once a frame, the way the
## quick mask's strip does, because the document under the view changes on
## File > New and File > Open.
##
## **The sign speaks for Edit Smart Layer Contents too**, the same view on one
## smart layer, `SaEditSmartLayerContents`, whose command this registers and
## whose grey, `SaContentsBackdrop`, this puts behind the canvas it watches.
class_name SaIsolateActiveLayer
extends PanelContainer

const NODE_NAME := "IsolateActiveLayer"
const COMMAND := &"view_isolate_active_layer"

var _canvas: SaCanvas = null
var _label: Label = null


## The canvas is a constructor argument, because a class writes its own members
## only. Defaulted so that `.new()` still works the way Godot expects of a
## Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas


## Puts the sign over *host*, the window-space control the main surface routes
## its input through, reading the document of *canvas*. The surface overlay
## factory.
static func attach_to(host: Control, canvas: SaCanvas) -> SaIsolateActiveLayer:
    var strip := SaIsolateActiveLayer.new(canvas)
    strip.name = NODE_NAME
    host.add_child(strip)
    SaContentsBackdrop.attach_to(canvas)
    return strip


## Registers the command against *ctx*, on `/` and the numpad's slash in Sara's
## own map. It acts on the primary easel's surface, the main canvas, whose view
## it frames.
static func register_command(ctx: SaContext) -> void:
    var reach := reach_of(ctx)
    var command := SaCommandDescriptor.create(COMMAND, "Isolate the active layer", func() -> bool: return _toggle(reach))
    command.label = "Isolate Active Layer"
    command.default_events = [SaShortcutStore.parse_chord("/"), SaShortcutStore.parse_chord("Numpad /")]
    command.category = &"view"
    command.sentence = (
        "Show the active layer alone, or the picked layers, framed to fill the view. Again shows every layer and"
        + " puts the view back. Nothing in the picture changes."
    )
    command.checked = func() -> bool: return SaLocalView.is_on(document_of(reach))
    ctx.register_command(command)
    # A document opened over the view is a new picture, which the view fits
    # whole, so isolation of the one it replaced ends with it.
    if not EventBus.document_loaded.is_connected(SaLocalView.forget):
        EventBus.document_loaded.connect(SaLocalView.forget)
    SaEditSmartLayerContents.register_command(ctx)


## A bare context with only *ctx*'s providers, which a command's callables
## hold in its place, because *ctx* holds the registry holding the command, a
## ring that leaked each registration after the first. The providers ask
## the app on each call, so the command lives as long as the app.
static func reach_of(ctx: SaContext) -> SaContext:
    return SaContext.new(ctx.easel_provider, ctx.surface_provider)


static func _toggle(ctx: SaContext) -> bool:
    var surface := surface_of(ctx)
    if surface == null or surface.view == null or surface.get_document() == null:
        return false
    var document := surface.get_document()
    # Turning it on posts no notice, because the sign says it where a notice
    # would sit and the two would cover each other.
    if not SaLocalView.toggle(document, surface.view, surface.view.get_free_rect()):
        SaMessage.notice(TranslationServer.translate("Every layer shown again"))
    return true


## The surface showing the primary easel, the main canvas, or the first one
## known when none does, which is a suite's.
static func surface_of(ctx: SaContext) -> SaSurface:
    var easel := ctx.get_easel()
    var surfaces := ctx.list_surfaces()
    for held: Variant in surfaces:
        var surface := held as SaSurface
        if surface != null and surface.easel == easel:
            return surface
    return surfaces[0] as SaSurface if not surfaces.is_empty() else null


static func document_of(ctx: SaContext) -> SaDocument:
    var surface := surface_of(ctx)
    return SaSurface.document_of(surface)


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    grow_horizontal = GROW_DIRECTION_BOTH
    grow_vertical = GROW_DIRECTION_BEGIN
    var style := StyleBoxFlat.new()
    style.set_content_margin_all(SaUI.pxf(6.0))
    style.content_margin_left = SaUI.pxf(12.0)
    style.content_margin_right = SaUI.pxf(12.0)
    style.set_corner_radius_all(SaUI.px(4))
    style.set_border_width_all(SaUI.px(1))
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag"})
    add_theme_stylebox_override("panel", style)
    _label = SaMake.label(self, "Text", "")
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


## Sits just over the foot of the room between the dockers, which is the room
## the view framed the layer in.
func _place() -> void:
    var parent := get_parent() as Control
    if _canvas == null or parent == null:
        return
    var room := SaCanvasView.for_canvas(_canvas).get_free_rect()
    var origin := parent.get_global_rect().position
    offset_bottom = room.end.y - origin.y - parent.size.y - SaUI.pxf(12.0)
    offset_top = offset_bottom - size.y
    var middle := room.get_center().x - origin.x - parent.size.x * 0.5
    offset_left = middle - size.x * 0.5
    offset_right = offset_left + size.x


## Whether the document under the view is isolated.
func is_on() -> bool:
    return _canvas != null and SaLocalView.is_on(_canvas.document)


## What the sign says: the layer shown, or how many, and the way back.
func message() -> String:
    var document := _canvas.document if _canvas != null else null
    var contents := SaLocalView.contents_of(document)
    if contents != null:
        return contents_message(contents)
    var shown := SaLocalView.shown(document)
    var named := ""
    if shown.size() > 1:
        named = tr_n("%d picked layer", "%d picked layers", shown.size()) % shown.size()
    elif shown.size() == 1:
        named = String(shown[0].name)
    var chord := ""
    if InputMap.has_action(COMMAND):
        chord = SaCommandRegistry.format_events(InputMap.action_get_events(COMMAND), 1)
    if chord.is_empty():
        return tr("Isolate Active Layer: only %s is shown. View > Isolate Active Layer shows every layer.") % named
    return tr("Isolate Active Layer: only %s is shown. %s shows every layer.") % [named, chord]


## What the sign says while *contents*, a smart layer, is open: that it is
## shown as painted over a grey that is not the picture's, and the way back.
func contents_message(contents: SaLayer) -> String:
    var command := SaEditSmartLayerContents.COMMAND
    var chord := ""
    if InputMap.has_action(command):
        chord = SaCommandRegistry.format_events(InputMap.action_get_events(command), 1)
    var way := chord if not chord.is_empty() else tr("Layer > Edit Smart Layer Contents")
    var line := "%s: '%s' is shown as it was painted, over a grey that is not part of the picture. %s closes it."
    return tr(line) % [tr(SaEditSmartLayerContents.NAME), contents.name, way]
