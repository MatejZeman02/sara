## Two filters of one kind attached to one layer read apart: the second reads
## "Gaussian Blur 2" and the third "Gaussian Blur 3", counted in the order the
## records run in, the first without a number, and listed the other way up, the
## newest on top.
##
## The number is worked out whenever a title is asked for and never kept, so
## taking a record away or moving one renumbers the rest, and the tool options
## panel and the edit window read the title the row reads. The running app's
## half is `scenarios/two-filters-of-one-kind-attached-to-a-layer-read-apart.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")


## A filter with the Gaussian Blur's title and one slider, so a panel and a
## window have a page to build. Its pass is the fixture's invert, and it is
## registered under the fixture's module, so the compositor the bench built
## finds the kernel when a step redraws.
class Blur:
    extends SaFilter

    func title() -> String:
        return "Gaussian Blur"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.slider("Radius", 1, 50, 10.0)

    func run(ctx: SaFilterContext) -> void:
        ctx.point_pass("invert", "invert", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


## The other kind.
class Sharpen:
    extends Blur

    func title() -> String:
        return "Sharpen"


var _easel: SaEasel = null
var _doc: SaDocument = null
var _background: SaLayer = null
var _registry: SaFilterRegistry = null
var _blur: StringName = &""
var _sharpen: StringName = &""
var _canvas: SaCanvas = null
var _docker: LayersDocker = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _background = _doc.get_node("Background") as SaLayer
    _registry = _easel.compositor.filter_chain.registry
    var blur := Blur.new()
    var sharpen := Sharpen.new()
    _registry.register(blur, Bench.OWNER)
    _registry.register(sharpen, Bench.OWNER)
    _blur = SaFilterRegistry.key_for(Bench.OWNER, blur)
    _sharpen = SaFilterRegistry.key_for(Bench.OWNER, sharpen)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.filter_registry = _registry
    _docker.target_canvas = _canvas


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _canvas = null
    _easel = null
    _doc = null
    _background = null
    _registry = null


## Attaches one record of each key in *keys* to *node*, in order, and lists
## the docker again.
func _attach(node: SaLayer, keys: Array[StringName]) -> Array[SaAttachedFilter]:
    var made: Array[SaAttachedFilter] = []
    for key: StringName in keys:
        made.append(SaFilterOps.new(_doc).attach(node, key))
    _docker.sync_layer_list()
    return made


## The titles of the filter rows the docker lists under *node*, top to bottom,
## which is the record that runs last first, *node* null for the document's
## root.
func _titles_under(node: SaLayer) -> Array[String]:
    var found: Array[String] = []
    for row: SaRowFrame in _docker.item_list.rows:
        var view := row as SaFilterRowView
        if view != null and view.node == node:
            found.append(view.filter_title)
    return found


## The title the docker's row gives *record*.
func _row_title(record: SaAttachedFilter) -> String:
    for row: SaRowFrame in _docker.item_list.rows:
        var view := row as SaFilterRowView
        if view != null and view.record == record:
            return view.filter_title
    return ""


func test_three_of_one_kind_and_one_of_another_read_apart() -> void:
    var made := _attach(_background, [_blur, _blur, _sharpen, _blur])
    assert_eq(
        _titles_under(_background),
        ["Gaussian Blur 3", "Sharpen", "Gaussian Blur 2", "Gaussian Blur"] as Array[String],
        "The second and third blur carry their number, the first and the one sharpen none, the newest on top"
    )
    assert_eq(_background.filters, made, "and the layer holds the records in the order they run")


func test_taking_the_first_away_renumbers_the_rest() -> void:
    var made := _attach(_background, [_blur, _blur, _sharpen, _blur])
    _docker.item_list.picked.pick_filter(made[0])
    assert_true(_docker.actions.delete_filter(), "The first blur comes off by the docker's own Delete Filter")
    _docker.sync_layer_list()
    assert_eq(
        _titles_under(_background),
        ["Gaussian Blur 2", "Sharpen", "Gaussian Blur"] as Array[String],
        "The blur that was second reads plain and the one that was third reads 2"
    )
    assert_eq(_row_title(made[3]), "Gaussian Blur 2", "the same record that read 3 before")

    assert_true(_doc.undo(), "The step undoes")
    _docker.sync_layer_list()
    assert_eq(
        _titles_under(_background),
        ["Gaussian Blur 3", "Sharpen", "Gaussian Blur 2", "Gaussian Blur"] as Array[String],
        "and the four titles are what they were"
    )


func test_a_record_moved_takes_the_number_of_its_new_place() -> void:
    var made := _attach(_background, [_blur, _sharpen, _blur])
    assert_true(SaFilterOps.new(_doc).reorder(_background, made[2], 0), "The last blur moves to run first")
    _docker.sync_layer_list()
    assert_eq(
        _titles_under(_background),
        ["Sharpen", "Gaussian Blur 2", "Gaussian Blur"] as Array[String],
        "The one that runs first is plain, and is listed last"
    )
    assert_eq(_row_title(made[2]), "Gaussian Blur", "and it is the record that moved")
    assert_eq(_row_title(made[0]), "Gaussian Blur 2", "while the one that stood first reads 2")


func test_each_layer_and_the_root_count_their_own() -> void:
    var paint := SaLayerOps.new(_doc).add()
    _attach(paint, [_blur])
    _attach(_background, [_blur])
    _attach(null, [_blur, _blur])
    assert_eq(_titles_under(paint), ["Gaussian Blur"] as Array[String], "A blur on one layer is the first of its own")
    assert_eq(_titles_under(_background), ["Gaussian Blur"] as Array[String], "and so is one on another")
    assert_eq(_titles_under(null), ["Gaussian Blur 2", "Gaussian Blur"] as Array[String], "and the root counts its own")


func test_the_panel_and_the_window_read_the_rows_title() -> void:
    var made := _attach(_background, [_blur, _blur, _sharpen, _blur])
    var window := SaFilterEditWindow.new()
    window.watch(_registry)
    for record: SaAttachedFilter in made:
        var said := _row_title(record)
        var panel := SaFilterPanel.new(record, _registry.get_filter(record.key), _doc)
        assert_eq((panel.get_node("Heading") as Label).text, said, "The tool options panel is headed '%s'" % said)
        assert_eq(panel.describe()["title"], said, "and its state dump says so")
        panel.free()
        window.open(record, _doc)
        assert_eq(window.title, "%s on Background" % said, "The edit window is titled '%s' and names the layer" % said)
        assert_eq(window.describe()["title"], window.title, "and its state dump says so")
    window.free()


func test_a_key_no_module_answers_is_numbered_too() -> void:
    var missing := &"gone.filter"
    _attach(_background, [missing, missing])
    assert_eq(
        _titles_under(_background),
        ["gone.filter 2", "gone.filter"] as Array[String],
        "A record of a missing module reads its key, and the second its number"
    )


func test_a_record_that_hangs_nowhere_reads_the_title_alone() -> void:
    var loose := SaAttachedFilter.new(_blur)
    _attach(_background, [_blur])
    assert_eq(SaAttachedFilter.numbered("Gaussian Blur", _background.filters, loose), "Gaussian Blur", "Outside the list")
    assert_eq(SaAttachedFilter.numbered_in(_doc, loose, "Gaussian Blur"), "Gaussian Blur", "and outside the document")
