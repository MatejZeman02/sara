## The Filters docker's parameters part: the widgets of the record the painter
## last picked, under the browser's Open, edited live.
##
## **What it shows.** The docker holds "the parameters of the selected
## filter layer" beside the list. The record is the attached filter whose row
## was picked in a Layers docker, and with none picked it is the active layer's
## own record when that layer is an adjustment layer, the record a press on its
## row opens. Nothing else picked, the part says so in a sentence.
##
## **The same panel the tool options show.** The widgets are an [SaFilterPanel],
## so a change writes through `SaFilterOps.set_parameters`, redraws the canvas
## and is one Edit Filter step, a drag folding into one, exactly as in Tool
## Options, which keeps its own. Both panels follow one record: a write by
## either moves the record, and the other draws its widgets again from it,
## which is what the panel already does after an undo. So a slider moved in
## one stands at the same value in the other, and one undo puts both back.
##
## **How it hears the pick.** A Layers docker's pick reaches it through
## `FiltersDocker.follow_pick`, which the list keeper's `show_filter` calls
## beside the tool options. The active layer is heard from the document, so a
## press on an adjustment layer's row, a shortcut that selects one and an undo
## that makes one active all show its record. The panel is built only while the
## docker is shown: a hidden docker keeps the pick and builds nothing, so the
## filter's one instance holds no second page nobody sees.
##
## **Narrower than Tool Options.** The docker's place in the shipped layouts
## is a strip 160 wide. A row whose caption is inside its slider has an empty
## label column, which is dropped here, a titled row's column is narrowed and
## its title wraps, and a slider asks for a floor rather than its widest text,
## as Tool Options' sliders do, and writes a whole number without its zeros. A
## module's own page wider than that, Levels and Curves, scrolls sideways.
@tool
extends VBoxContainer

## The node name, which a scenario's `control` step finds the part under.
const NODE_NAME := "FilterParameters"

## The label column of a titled row here, in logical pixels, where Tool
## Options gives it 124. A slider with its caption inside takes none.
const LABEL_WIDTH := 56

## What a slider here asks for at least, logical, where its widest text would
## ask more than the docker is wide.
const SLIDER_FLOOR := 72

## What the part says with nothing to show.
const NOTHING_PICKED := "No filter selected. Select a filter or an adjustment layer to edit its settings."

## The panel of the record shown, or null with nothing picked or the docker
## shut.
var panel: SaFilterPanel = null

## The canvas whose document the part follows, or null for `Main`'s, which is
## what the running app has. Set by a suite, as the browser's is.
var target_canvas: SaCanvas = null

## Where a record's filter is looked up, Main's, handed in by the docker.
var registry: SaFilterRegistry = null

## The attached record whose row was picked last, or null when a layer's row
## took the pick back.
var _picked: SaAttachedFilter = null

## The document whose signals the part hears.
var _heard: SaDocument = null

var _sentence: Label = null
var _body: VBoxContainer = null


func _init() -> void:
    name = NODE_NAME
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(6))

    SaMake.separator(self, "ParametersRule")
    var heading := SaMake.label(self, "ParametersHeading", tr("Parameters"))
    # Wrapped, so a longer language's heading never widens the detail column
    # past the docker's edge.
    heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaSettingsRows.embolden(heading)

    var scroll := SaMake.scroll(self, "ParametersScroll")
    # Sideways only, because a module's own page can be wider than the docker,
    # Levels 362 against a strip of 160, and would otherwise widen it. Down, the
    # part asks for the height its rows need, its sentence's alone with nothing
    # picked, and the docker's own scroll takes a column taller than the docker.
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    _body = SaMake.column(scroll, "ParametersBody")
    _body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _sentence = SaMake.label(_body, "ParametersSentence")
    _sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sentence.text = tr(NOTHING_PICKED)

    visibility_changed.connect(refresh)
    tree_entered.connect(refresh)


func _enter_tree() -> void:
    if not Engine.is_editor_hint() and not EventBus.document_loaded.is_connected(_on_document_loaded):
        EventBus.document_loaded.connect(_on_document_loaded)
    # Another document brought forward is shown the way a loaded one is.
    if not Engine.is_editor_hint() and not EventBus.active_document_changed.is_connected(_on_document_loaded):
        EventBus.active_document_changed.connect(_on_document_loaded)


## Takes *record* as the pick, or none for null, and shows what follows from it.
func pick(record: SaAttachedFilter) -> void:
    _picked = record
    refresh()


## The record the part shows: the picked one while it still hangs in the
## document, else the active layer's own when it is an adjustment layer, else
## null.
func shown_record() -> SaAttachedFilter:
    var doc := _document()
    if doc == null:
        return null
    if _picked != null and _attached(doc, _picked):
        return _picked
    return SaBackdropLayer.own_filter(doc.active_layer)


## Builds the panel of the record [method shown_record] answers, or the sentence
## when there is none or the docker is shut. A panel already showing that record
## on that document is kept, so a write from the other panel, which redraws its
## widgets, does not cost a second page.
func refresh() -> void:
    var doc := _document()
    _listen_to(doc)
    var record := shown_record() if is_visible_in_tree() else null
    if panel != null and is_instance_valid(panel) and panel.record == record and record != null:
        return
    _drop_panel()
    _sentence.visible = record == null
    if record == null:
        return
    var filter := registry.get_filter(record.key) if registry != null else null
    panel = DockerPanel.new(record, filter, doc)
    _body.add_child(panel)
    SaUI.apply_ui_theme(panel)
    _sentence.visible = false


## What the part shows, for the state dump: the record picked, the panel's own
## dump and the value of each of its sliders by name, or the sentence.
func describe() -> Dictionary:
    var shown := panel != null and is_instance_valid(panel)
    var sliders := {}
    if shown:
        for node in DockerPanel.made_under(panel, "FactorSlider"):
            sliders[String(node.name)] = (node as FactorSlider).value
    return {
        "picked": String(_picked.key) if _picked != null else "",
        "showing": panel.describe() if shown else {},
        "sliders": sliders,
        "sentence": _sentence.text if _sentence.visible else "",
    }


func _document() -> SaDocument:
    var canvas := target_canvas
    if canvas == null and is_inside_tree():
        canvas = SaCanvasView.front_canvas()
    return canvas.document if canvas != null and is_instance_valid(canvas) else null


## Hears *doc*'s active layer and its changes, and lets go of the last one's.
## A change can take the picked record away or make another record an
## adjustment layer's own, and [method refresh] reads which.
func _listen_to(doc: SaDocument) -> void:
    if doc == _heard:
        return
    if _heard != null and is_instance_valid(_heard):
        _heard.active_layer_changed.disconnect(_on_active_layer_changed)
        _heard.document_changed.disconnect(refresh)
    _heard = doc
    if doc != null:
        doc.active_layer_changed.connect(_on_active_layer_changed)
        doc.document_changed.connect(refresh)


func _on_active_layer_changed(_layer: SaLayer) -> void:
    refresh()


## A document opened in place of the last: its active layer is heard from now
## on, and a record picked in the last one is not in it.
func _on_document_loaded(_doc_or_surface: Variant) -> void:
    refresh()


## Takes the panel away. Out of the tree at once, so neither a scenario nor the
## browser finds it, and freed at the end of the frame, because a refresh can
## run inside the panel's own Flatten, whose record has just gone.
func _drop_panel() -> void:
    if panel == null or not is_instance_valid(panel):
        panel = null
        return
    var in_tree := panel.is_inside_tree()
    panel.get_parent().remove_child(panel)
    if in_tree:
        panel.queue_free()
    else:
        panel.free()
    panel = null


## Whether *record* hangs on a layer of *doc* or on its root with a row of its
## own, which an adjustment layer's own record has not.
static func _attached(doc: SaDocument, record: SaAttachedFilter) -> bool:
    if doc.root_filters.has(record):
        return true
    var node := SaFilterOps.new(doc).node_of(record)
    return node != null and SaBackdropLayer.own_filter(node) != record


## The panel as the docker holds it: the tool options' panel, its rows fitted to
## the docker's width and its sliders, switches and choices marked the way
## `SaMake` marks a control, so a scenario's `control` step moves them. Both are
## done again on every draw, because an undo draws the rows anew. Tool Options'
## own panel stays unmarked, so a `control` step naming a slider both panels
## have finds this one.
class DockerPanel:
    extends SaFilterPanel

    ## What the rows are called here, the name the state dump files them under.
    const ROWS_NAME := "FiltersDockerRows"

    ## The kind a control of each class is marked as, for the walker.
    const KINDS := {
        "FactorSlider": SaMake.Kind.SLIDER,
        "SaChoiceButton": SaMake.Kind.CHOICE,
        "CheckBox": SaMake.Kind.TOGGLE,
        "CheckButton": SaMake.Kind.TOGGLE,
    }

    func _init(attached: SaAttachedFilter, its_filter: SaFilter, document: SaDocument) -> void:
        super(attached, its_filter, document)
        # The state dump files a page under its rows' name, and Tool Options'
        # panel names its rows "Rows" too, so this one's would hide it.
        var rows := get_node_or_null(^"Rows")
        if rows != null:
            rows.name = ROWS_NAME

    func _draw_rows() -> void:
        super()
        for declared: SaPageRow in dialog.rows():
            var line := declared.line as SaSettingsRows.Line
            var labels := line.get_node_or_null("Labels") as Control if line != null else null
            if labels == null:
                continue
            var titled := not String(line.get_meta(SaSettingsRows.TITLE_META, "")).is_empty()
            labels.visible = titled and labels.visible
            labels.custom_minimum_size.x = SaUI.px(LABEL_WIDTH) if titled else 0
            var title := labels.get_node_or_null("Title") as Label
            if title != null:
                title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        for kind_class: String in KINDS:
            for node in made_under(self, kind_class):
                if SaMake.kind_of(node) < 0:
                    node.set_meta(SaMake.KIND_META, KINDS[kind_class])
        # A slider asks for its widest text, the blur's Radius 171 wide, so here
        # it asks for a floor and cuts its text, the way Tool Options' do. A
        # whole number drops its zeros, which "Radius: 12.00 px" needed, being
        # 161 wide in a slider of 155.
        for node in made_under(self, "FactorSlider"):
            var slider := node as FactorSlider
            slider.trim_trailing_zeros = true
            slider.fits_its_text = false
            slider.preferred_width = SaUI.px(SLIDER_FLOOR)
            slider.custom_minimum_size.x = slider.preferred_width

    ## Every node under *under* of the class named *kind_class*, an engine
    ## class or a script's own, in tree order.
    static func made_under(under: Node, kind_class: String) -> Array[Node]:
        var out: Array[Node] = []
        for child in under.get_children():
            if child.is_class(kind_class) or _inherits(child.get_script() as Script, kind_class):
                out.append(child)
            out.append_array(made_under(child, kind_class))
        return out

    static func _inherits(script: Script, kind_class: String) -> bool:
        var at := script
        while at != null:
            if String(at.get_global_name()) == kind_class:
                return true
            at = at.get_base_script()
        return false
