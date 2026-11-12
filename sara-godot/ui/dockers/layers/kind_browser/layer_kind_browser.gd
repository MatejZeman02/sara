## The filter browser an adjustment or an effect layer is added through: the
## filters its kind can hold, and a pick that makes the layer holding one,
## named for it, with the filter's settings open straight after.
##
## An adjustment or effect layer made empty would be a layer that does nothing
## with no sign of where it is set. Both kinds store nothing and are their
## filters run over an input, so the filter is the question the row asks before
## there is a layer.
##
## **The Filters browser, told a kind.** Its list, its search, its sections and
## its preview are [SaFilterBrowser], the control the Filters docker holds as
## well, and this answers the two things it does differently through that
## control's constructor: which filters are listed, `holds`, and what the pick
## does, `_add_picked`, which makes a layer where the docker invokes the
## filter's dialog. A window of its own rather than a mode of the docker,
## because the two can be open at once without either forgetting what it was
## asked, and because the question is asked once, before a layer exists, as a
## dialog asks it. The Filters browser is a docker and has no window, so what
## this window stands on is that control and not a window of the browser's.
##
## **An adjustment layer is made by `SaFilterConversion.add_holding`**, the
## Filter dialog's Layer way, so the two doors make one layer. It refuses a
## filter that reads the whole layer, and such a filter is left off the list
## rather than offered and refused. **An effect layer is built here** and
## handed to `SaLayerOps.commit_added` as one step, because `add_holding` makes
## the adjustment layer alone and `core/layers` is at its line budget. It reads
## the active layer it was made above, as one added bare does.
@tool
class_name SaLayerKindBrowser
extends SaDialogWindow

## The node the browser is put under its host as, and what `find_browser` looks
## for.
const HOME := "LayerKindBrowser"

## The list, the search, the detail and the button that adds the layer, beside
## each other because a window is wide.
var browser: SaFilterBrowser = null

## The kind the browser adds, the document it adds to and the registry the kind
## is registered in, all as the last `open_for` was given them.
var kind: SaLayerTypeDescriptor = null
var document: SaDocument = null
var layer_types: SaLayerTypeRegistry = null

## The layer the last pick made, or null when it was refused, which a suite and
## the door read.
var made: SaLayer = null

## Registry key -> whether the filter reads the whole layer, asked once an open.
var _whole: Dictionary[StringName, bool] = {}


## The browser in a dialog of its own, with Close before Add Layer, at the size
## and floor the Filters window opened at.
func _init() -> void:
    _init_dialog(HOME, tr("Filters"), Vector2i(720, 520), Vector2i(520, 380))
    # A Window is visible the moment it joins the tree, and this one is built
    # on its first use and only shown by `open_for`.
    visible = false

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margin.add_theme_constant_override(side, SaUI.px(12))
    content.add_child(margin)

    browser = SaFilterBrowser.new(true, _add_picked, holds)
    margin.add_child(browser)
    var close := Button.new()
    close.name = "BrowserCloseButton"
    close.text = tr("Close")
    close.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    close.pressed.connect(hide)
    browser.serve(self, close, tr("Add Layer"))


## Opens the browser for *holding_kind* under *host*, built there on first use
## and pointed at the host's registries, and answers it. The Layer menu's kind
## rows and the docker's arrow both come here through `SaLayerMenuRows.run`.
static func open_on(
    host: Node, in_document: SaDocument, holding_kind: SaLayerTypeDescriptor, types: SaLayerTypeRegistry
) -> SaLayerKindBrowser:
    if host == null or in_document == null or holding_kind == null:
        return null
    var window := host.get_node_or_null(NodePath(HOME)) as SaLayerKindBrowser
    if window == null:
        window = SaLayerKindBrowser.new()
        host.add_child(window)
        var registries := host.get("registries") as SaRegistries
        if registries != null:
            window.browser.watch(registries.filters, registries.commands)
    window.open_for(in_document, holding_kind, types)
    return window


## The browser under the current scene, or null. What the door's step reaches
## it by.
static func find_browser(tree: SceneTree) -> SaLayerKindBrowser:
    if tree == null:
        return null
    for node in tree.root.find_children(HOME, "Window", true, false):
        if node is SaLayerKindBrowser:
            return node
    return null


## Lists the filters *holding_kind* can hold for a layer in *in_document*, of a
## kind *types* registers, and shows the window when it has a tree to show in.
## A detached browser, which is how a suite holds one, is filled and left shut.
func open_for(in_document: SaDocument, holding_kind: SaLayerTypeDescriptor, types: SaLayerTypeRegistry) -> void:
    document = in_document
    kind = holding_kind
    layer_types = types
    made = null
    _whole.clear()
    retitle(_kind_title())
    # The search is left as the painter typed it, because a browser that
    # forgets the word between two openings is a browser that is searched twice.
    browser.refresh()
    if is_inside_tree():
        popup_centered()


## The browser's title for the kind it holds. A shipped kind's is a whole
## sentence, so a language with cases can decline its name, and a module's own
## kind reads the generic one with its name dropped in.
func _kind_title() -> String:
    if SaWholeSentences.LAYER_ADD.has(SaLayerMenuRows.kind_words(kind)):
        return tr(SaWholeSentences.LAYER_ADD[SaLayerMenuRows.kind_words(kind)])
    return tr("Add %s") % tr(SaLayerMenuRows.kind_words(kind))


## The title on the window and on its drag bar, which the bar was built with
## once and so is written again here.
func retitle(text: String) -> void:
    title = text
    var label := drag_handle.find_child("TitleLabel", true, false) as Label if drag_handle != null else null
    if label != null:
        label.text = text


## Whether the kind holds *key*'s filter. An effect layer runs every filter a
## paint layer does, over its input's pixels, and an adjustment layer every one
## but a filter that reads the whole layer, because it reads the backdrop a chunk
## at a time.
func holds(key: StringName) -> bool:
    if kind == null or kind.input != SaLayerTypeDescriptor.INPUT_BELOW:
        return true
    if not _whole.has(key):
        _whole[key] = _reads_whole(key)
    return not _whole[key]


## Whether *key*'s filter records a pass that reads the whole layer, asked by
## running it once in a preview context over the active layer, because a
## filter's reach is known from its run alone. The run records a pass and
## writes nothing, as the preview's does. A filter that cannot run is listed
## and dimmed, as the Filters browser lists it.
func _reads_whole(key: StringName) -> bool:
    var registry := browser.registry
    var filter := registry.get_filter(key) if registry != null else null
    var layer := document.active_layer if document != null else null
    if filter == null or layer == null or not filter.problem().is_empty():
        return false
    var ctx := SaFilterContext.new(document, layer, registry.owner_of(key), filter.title(), true)
    filter.run(ctx)
    return SaFilterBrowser.reads_whole(ctx)


## Presses Add Layer, which is the browser's Open, so a pick and the press go
## through the one path a hand takes.
func open_selected() -> void:
    browser.open_selected()


## The pick of *key*, which makes the layer rather than opening the filter's
## dialog, at the filter's defaults, which are the ones the preview ran.
## The filter's settings open on the new layer's record, where the Filter dialog
## would have opened on the layer the painter was on, told the layer is fresh,
## so that their Cancel takes the add back and no layer is left that the painter
## declined.
func _add_picked(key: StringName) -> void:
    var registry := browser.registry
    var filter := registry.get_filter(key) if registry != null else null
    if filter == null or kind == null or document == null:
        return
    hide()
    # The record the filter is filed as, which is another filter's for an entry
    # over its kernel, so the window opens on that one.
    var filed := SaFilterBrowser.filed_at_defaults(filter, key)
    if kind.id == SaBackdropLayer.TYPE_ID:
        made = SaFilterConversion.new(document).add_holding(filed.key, filed.parameters, layer_types, filter.translated_title())
    else:
        made = _add_reading(filed.key, filed.parameters, filter.translated_title())
    if made != null and not made.filters.is_empty() and is_inside_tree():
        SaFilterEditWindow.open_in(get_tree(), document, made.filters[0], made)


## A layer of the kind above the active layer, in its group, holding one record
## of *key* at *values* and named *wanted*, with a mask that hides nothing, as
## one step, Add Effect Layer in the
## history for an effect layer. An effect layer reads the active layer, which is
## what `SaEffectLayer.first_input` answers while that layer is still the active
## one.
func _add_reading(key: StringName, values: Dictionary, wanted: String) -> SaLayer:
    var active := document.active_layer
    var layer := SaLayer.new()
    layer.schema = SaFieldSpec.schema_for_space(document.color_space)
    if active == null or layer_types == null or not layer_types.apply_to(layer, kind.id, document.color_space):
        layer.free()
        return null
    layer.name = SaFilterConversion.new(document).layer_name_for(wanted)
    layer.group = SaLayerStack.parent_of(active)
    layer.filters.append(SaAttachedFilter.new(key, values))
    SaFilterConversion.give_bare_mask(layer)
    document.add_child(layer)
    document.move_child(layer, active.get_index() + 1)
    layer.source = SaEffectLayer.first_input(document, layer) if layer.is_effect() else null
    document.set_active_layer(layer)
    SaLayerOps.new(document).commit_added("Add %s" % SaLayerMenuRows.kind_words(kind), [layer])
    return layer


## The Filters browser's dump, with whether the window is open, where it and
## its buttons stand, the kind asked for and the layer made.
func describe() -> Dictionary:
    var out := browser.describe()
    var layout := browser.describe_layout()
    var needed := content_minimum_size() if drag_handle != null else Vector2i.ZERO
    layout["window"] = [position.x, position.y, size.x, size.y]
    layout["logical_min_size"] = [logical_min_size.x, logical_min_size.y]
    layout["content_minimum"] = [needed.x, needed.y]
    out["open"] = visible
    out["layout"] = layout
    out["kind"] = String(kind.id) if kind != null else ""
    var alive := made != null and is_instance_valid(made)
    out["made"] = String(made.name) if alive else ""
    out["holds"] = made.filters.map(func(record: SaAttachedFilter) -> String: return String(record.key)) if alive else []
    return out


## Drives the layer kind browser: `{"layer_kind_browser": {"select":
## "sara-base-modules.gaussian_blur"}}` picks a row the way a hand would,
## `{"search": "blur"}` types in the field, `"add"` presses Add Layer, `"close"`
## hides the window and `"describe"` prints what it says it is.
##
## A step of its own for the reason the Filters docker has one: this is an
## embedded subwindow, and its rows share a name a click could aim by.
static func capture_browser(tree: SceneTree, spec: Variant) -> String:
    var window := find_browser(tree)
    if window == null:
        return "SaCapture: no layer kind browser has opened"
    var options: Dictionary = spec if spec is Dictionary else {"do": String(spec)}
    if options.has("search"):
        window.browser.search_for(String(options["search"]))
        return "SaCapture: searched '%s', %s" % [options["search"], JSON.stringify(window.describe())]
    if options.has("select"):
        var key := StringName(String(options["select"]))
        if not window.browser.pick(key):
            return "SaCapture: the layer kind browser is not offering '%s'" % key
        return "SaCapture: picked '%s', %s" % [key, JSON.stringify(window.describe())]
    match String(options.get("do", "")):
        "add":
            window.open_selected()
            return "SaCapture: added from the layer kind browser, %s" % JSON.stringify(window.describe())
        "close":
            window.hide()
            return "SaCapture: the layer kind browser closed"
        "describe":
            return "SaCapture: the layer kind browser is %s" % JSON.stringify(window.describe())
    return "SaCapture: no layer kind browser command %s" % JSON.stringify(spec)
