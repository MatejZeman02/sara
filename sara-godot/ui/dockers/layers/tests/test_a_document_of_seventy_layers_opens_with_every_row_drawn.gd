## A document of seventy layers in groups, with twenty-five attached filters,
## opens with every row of the Layers docker drawn, in under five seconds.
##
## The welcome picture's working file, 68 layers and 25 filter rows, did not
## open: the main thread spun for minutes. Each layer the load added ran a full
## `sync()` of the rows, the rows each sync let go of waited for a frame end the
## load never reached, and each new row's `SaTheme.bind_font` scanned the whole
## `_bound_fonts` list twice, which reached 10,000 entries. The keeper now marks
## the rows stale and draws them once, and a bind is a lookup by control.
extends "res://tests/test_framework.gd"

## A load folds the composite caches, which are compute dispatches.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const DOC_SIZE := Vector2i(1024, 512)
const GROUPS := 7
const MEMBERS := 9
const FILTERS := 25

## The ceiling the row sets on the open, in milliseconds.
const LIMIT_MS := 5000.0

var _made: SaEasel
var _opened: SaEasel
var _canvas: SaCanvas
var _docker: LayersDocker
var _path := ""


## Seven groups of nine painted layers, seventy layers with the default two and
## less the one the groups take from them, and an invert attached to every
## third painted layer until twenty-five hang, saved to a file of its own. The
## Layers docker shows a fresh default document, as the app's does at start.
func before_each() -> void:
    _made = Bench.easel(DOC_SIZE)
    var doc := _made.document
    var ops := SaLayerOps.new(doc)
    var filters := SaFilterOps.new(doc)
    var attached := 0
    var painted := 0
    for g: int in GROUPS:
        var members: Array[SaLayer] = []
        for m: int in MEMBERS:
            var layer := ops.add()
            layer.name = "Paint %d.%d" % [g, m]
            doc.fill_layer(Color(float(m) / MEMBERS, float(g) / GROUPS, 0.3, 0.5), layer)
            members.append(layer)
            painted += 1
            if painted % 2 == 0 and attached < FILTERS:
                filters.attach(layer, Bench.INVERT)
                attached += 1
        ops.group_layers(members).name = "Group %d" % g
    while attached < FILTERS:
        filters.attach(null, Bench.INVERT)
        attached += 1
    _path = SaDataRoot.path("seventy-layers.sad")
    assert_eq(SaExport.save_sad(doc, _path, 0), OK, "the document of seventy layers saves")

    _opened = Bench.easel(DOC_SIZE)
    _canvas = SaCanvas.new()
    _canvas.easel = _opened
    _docker = LayersDocker.new()
    _docker.filter_registry = _opened.compositor.filter_chain.registry
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _opened.free()
    _made.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


## Every layer of the document and every filter hanging in it, which is the
## rows an open stack draws.
static func _expected_rows(doc: SaDocument) -> int:
    var count := doc.root_filters.size()
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer != doc.stroke_layer:
            count += 1 + layer.filters.size()
    return count


## The open draws the rows itself, once it has made a layer active, so the
## suite reads them straight after it, as the frame after the open draws them.
func test_the_document_opens_with_every_row_drawn_in_under_five_seconds() -> void:
    var doc := _opened.document
    var start := Time.get_ticks_usec()
    assert_eq(SaExport.load_sad(doc, _path, _opened.compositor), OK, "the document opens")
    SaLayerList.settle_thumbnails(_docker)
    var took := (Time.get_ticks_usec() - start) / 1000.0
    print("probe open %.1f ms" % took)
    var layers := 0
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            layers += 1
    assert_true(layers >= 70, "the file holds %d layers, seventy or more" % layers)
    assert_eq(_docker.item_list.rows.size(), _expected_rows(doc), "every layer and every filter has its row")
    assert_true(took < LIMIT_MS, "the open took %.1f ms, under %d" % [took, LIMIT_MS])
    var named := 0
    for i: int in _docker.item_list.rows.size():
        var layer: SaLayer = _docker.item_list.layer_at(i)
        if layer != null and String(_docker.item_list.rows[i].lbl.text) == str(layer.name):
            named += 1
    assert_eq(named, layers, "each layer's row reads its layer's name")


## The table holds one entry a control, and a bind sweeps out the controls that
## are gone once it has doubled since the last sweep, so between two sweeps it
## never holds more dead entries than live ones and the 64 a sweep lets grow.
func test_the_bound_colours_are_only_those_of_live_controls() -> void:
    var before := SaTheme.bound_font_count()
    assert_eq(SaExport.load_sad(_opened.document, _path, _opened.compositor), OK, "the document opens")
    var held := SaTheme._bound_fonts.size()
    var live := 0
    for id: int in SaTheme._bound_fonts:
        if is_instance_valid(instance_from_id(id)):
            live += 1
    assert_true(held - live <= live + 64, "the table holds %d entries for %d live controls" % [held, live])
    assert_eq(SaTheme.bound_font_count(), live, "and after a sweep, one for each live control")
    assert_eq(SaTheme._bound_fonts.size(), live, "which is what the table then holds")
    var rows: int = _docker.item_list.rows.size()
    assert_true(held - before <= rows * 8, "the open bound %d controls for %d rows" % [held - before, rows])


func test_the_open_draws_the_rows_once() -> void:
    var drawn := [0]
    _docker.list_keeper.followed.connect(func() -> void: drawn[0] += 1)
    assert_eq(SaExport.load_sad(_opened.document, _path, _opened.compositor), OK, "the document opens")
    assert_true(drawn[0] <= 3, "the open drew the rows %d times, not once a layer" % drawn[0])
