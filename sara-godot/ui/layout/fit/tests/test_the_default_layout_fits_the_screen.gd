## The default layout covers nothing on a 1280 by 1024 screen.
##
## The shipped default is laid out at 1280 by 1024, 1366 by 768 and 1920 by
## 1080, and at each no two dockers overlap, which is stronger than their
## titles not overlapping, and every docker is wholly on the host below the
## bar. At 1920 by 1080, the host the file was written for, the fit is the file
## exactly. A layout the painter has saved is not refitted, only kept on the
## host as a resize keeps it, and the Welcome window comes in front of the
## dockers the boot opened after it.
##
## It is also laid out at 1280 by 800 at scale 1 and 2, and on the hosts scale 2
## gives a 1280 by 1024 and a 1920 by 1080 window. On those the floors of a column are
## more than its height, and the file's `close_order` closes dockers until they
## fit and the painting keeps `SaDockerLayoutFit.PAINTING_SHARE` of the width.
## Scale 2 halves the host a docker is laid out on and leaves its floor as it
## is, so a host of 640 by 400 is 1280 by 800 at scale 2.
##
## The Reference ships closed, so the default opens six, and the Reference
## waits where no fit opens it, in the middle of the right of the painting
## between the Minimap and the Graph, since the Tool Options docker takes the
## column's foot to show all of the brush's rows. Its probe is built beside the
## open ones so a suite reads it stay shut.
##
## The Brush Presets opens by default, so it is easy to find. Tool Options heads
## the left column and the Brush Presets stands under it, and it heads the close order, so a host with no room for both closes it
## first and every smaller host is fitted as if it shipped closed.
##
## The shots are `scenarios/the-default-layout-covers-nothing-on-a-1280-by-1024-screen.json`
## and `scenarios/at-1280-by-800-and-at-scale-2-the-default-layout-leaves-room-to-paint.json`.
extends "res://tests/test_framework.gd"

## The first row below a one-row bar, `MainDockers.below_bar` with no bar.
const TOP := 65

## Each open docker's floor as the fit is handed it on the running app at scale
## 1, the column's want included, read again on a 1280 by 800 window. A probe window has no column, so the
## suite says it. The Layers
## docker's `floor_size` in the file is above its own and is merged in the way
## the store merges it.
## The Brush Presets' floor, which it has whether it is open or closed.
const PRESETS_FLOOR := Vector2i(295, 212)

const FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "ToolOptionsDocker": Vector2i(206, 255),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
    "BrushPresetsDocker": PRESETS_FLOOR,
    "MinimapDocker": Vector2i(168, 132),
}

## The closed Reference's floor, the `min_size` a fresh profile's dump reads
## once its buttons share the tabs' row.
const REFERENCE_FLOOR := Vector2i(224, 132)

## Where both files keep the closed Reference, under the
## Minimap's slot and beside the Graph's, clear of both columns. A closed
## docker is kept on the window rather than fitted to it.
const REFERENCE_RECT := Rect2i(1280, 320, 310, 223)

## Where both files keep the Tool Options docker, at the head of the left
## column under the bar's 79, so that the brush's twelve rows
## show: the rows ask 563 with the docker's grip. The Brush Presets stands
## under it with the 491 three rows of presets need and a gap of 18, so its
## foot ends at 1008, inside the 1009 a window 1048 tall keeps above the status
## line.
const BRUSH_PRESETS_RECT := Rect2i(60, 517, 310, 491)
const TOOL_OPTIONS_RECT := Rect2i(60, 79, 310, 438)

const SIZES: Array[Vector2i] = [
    Vector2i(1280, 1024),
    Vector2i(1366, 768),
    Vector2i(1920, 1080),
    Vector2i(1280, 800),
    Vector2i(640, 400),
    Vector2i(640, 512),
    Vector2i(960, 540),
]

## Both files a fresh profile can open the default from.
const SHIPPED_FILES: Array[String] = [DockerLayoutStore.SHIPPED_DEFAULTS, "res://layouts/default.cfg"]

static var scratch_live: String = SaDataRoot.path("test_d14_docker_layout.cfg")

var _root: Node = null


func after_each() -> void:
    SaFocusMode.active = false
    if _root != null:
        _root.free()
        _root = null
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


## The shipped file's open dockers, section to `{"rect", "min"}`.
func _shipped() -> Dictionary:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var out: Dictionary = {}
    for section in cfg.get_sections():
        if String(section).begins_with("_") or not bool(cfg.get_value(section, "visible", false)):
            continue
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        var floor_size: Vector2i = cfg.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i())
        out[section] = {"rect": rect, "min": floor_size.max(FLOORS.get(section, Vector2i.ONE))}
    return out


## The fit of the shipped default on *host*, with the file's close order.
func _fit(host: Vector2i) -> SaDockerLayoutFit:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    return SaDockerLayoutFit.new(host, TOP, _written_for(), order)


## The dockers the default keeps open on *host*, sorted, every one of the six
## where they all fit. Worked out by hand from `FLOORS` and the file, so a
## change to either that moves the answer is read here first. The left column
## stands on the Tool Options' 255 alone and the right on 484 with a gap of 10.
static func _open_on(host: Vector2i) -> Array:
    # Height closes the Minimap and the Brush Presets, the head of the order, then the Layers
    # on the right, then width the Tool Options.
    if host in [Vector2i(640, 400), Vector2i(640, 512)]:
        return ["ColorDocker", "ToolBoxDocker"]
    # Height alone, the Brush Presets again, and the two columns left give up
    # width instead.
    if host == Vector2i(960, 540):
        return ["ColorDocker", "ToolBoxDocker", "ToolOptionsDocker"]
    return ["BrushPresetsDocker", "ColorDocker", "LayersDocker", "MinimapDocker", "ToolBoxDocker", "ToolOptionsDocker"]


## *host* less the rows the status line takes from its foot, the host the store
## hands the fit.
static func _above_the_line(host: Vector2i) -> Vector2i:
    return host - Vector2i(0, SaStatusLine.rows_taken())


func _written_for() -> Vector2i:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    return cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())


func test_the_shipped_default_opens_six_dockers_written_for_1920_by_1080() -> void:
    assert_eq(_written_for(), Vector2i(1920, 1080), "the file says the host it was written for")
    var open := _shipped().keys()
    open.sort()
    var floors := FLOORS.keys()
    floors.sort()
    assert_eq(open, floors, "every docker a fresh profile opens has a floor here")
    assert_eq(open.size(), 6, "and a fresh profile opens six, the Minimap at the head of the right column")


## Both files keep the Reference closed, in its place beside the columns, where
## the Window menu opens it clear of the rest, so that the Tool Options has the
## foot of the left column.
func test_both_shipped_defaults_keep_the_reference_closed_clear_of_the_columns() -> void:
    for path in SHIPPED_FILES:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        assert_false(bool(cfg.get_value("ReferenceDocker", "visible", true)), "the Reference ships closed in %s" % path)
        var rect := Rect2i(cfg.get_value("ReferenceDocker", "position"), cfg.get_value("ReferenceDocker", "size"))
        assert_eq(rect, REFERENCE_RECT, "between the Minimap and the Graph in %s" % path)
        for section: String in _shipped():
            var open := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
            assert_false(rect.intersects(open), "clear of the %s in %s" % [section, path])
        var kept := _fit(Vector2i(1920, 1048)).kept(rect.position, rect.size)
        assert_eq(kept, rect.position, "and where it stands on a window 1048 tall, so it opens clear of them there")


## Both files keep the Brush Presets and the Tool Options as the constants say,
## the Tool Options tall enough for the brush's rows and the Brush Presets open
## under it.
func test_both_shipped_defaults_give_the_tool_options_the_brushs_rows() -> void:
    for path in SHIPPED_FILES:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        var presets := Rect2i(cfg.get_value("BrushPresetsDocker", "position"), cfg.get_value("BrushPresetsDocker", "size"))
        var options := Rect2i(cfg.get_value("ToolOptionsDocker", "position"), cfg.get_value("ToolOptionsDocker", "size"))
        assert_eq(presets, BRUSH_PRESETS_RECT, "the Brush Presets in %s" % path)
        assert_true(bool(cfg.get_value("BrushPresetsDocker", "visible", false)), "open in %s" % path)
        assert_false(presets.intersects(options), "and clear of the Tool Options in %s" % path)
        assert_eq(options, TOOL_OPTIONS_RECT, "the Tool Options in %s" % path)
        var kept := _fit(Vector2i(1920, 1048)).kept(options.position, options.size)
        assert_eq(kept, options.position, "and kept where it stands on a window 1048 tall in %s" % path)


func test_at_each_size_nothing_overlaps_and_everything_is_on_the_screen() -> void:
    var dockers := _shipped()
    for host in SIZES:
        var placed := _fit(host).place(dockers)
        var open := placed.keys()
        open.sort()
        assert_eq(open, _open_on(host), "the dockers open at %s" % host)
        var spans: Array[Vector2i] = []
        for rect: Rect2i in placed.values():
            spans.append(Vector2i(rect.position.x, rect.end.x))
        var painting := host.x - SaWorkspacePage.covered_width(spans)
        var share := "%d of %d" % [painting, host.x]
        assert_true(painting >= host.x * SaDockerLayoutFit.PAINTING_SHARE, "the painting keeps %s at %s" % [share, host])
        var sections := placed.keys()
        for i in sections.size():
            var rect: Rect2i = placed[sections[i]]
            var floor_size: Vector2i = dockers[sections[i]]["min"]
            var screen := Rect2i(Vector2i(0, TOP), host - Vector2i(0, TOP))
            assert_true(screen.encloses(rect), "%s %s is wholly on %s below the bar" % [sections[i], rect, host])
            var floored := rect.size.x >= floor_size.x and rect.size.y >= floor_size.y
            assert_true(floored, "%s %s keeps its floor at %s" % [sections[i], rect, host])
            for j in range(i + 1, sections.size()):
                assert_false(rect.intersects(placed[sections[j]]), "%s and %s overlap at %s" % [sections[i], sections[j], host])


func test_the_host_the_file_was_written_for_gets_the_file() -> void:
    var dockers := _shipped()
    var placed := _fit(Vector2i(1920, 1080)).place(dockers)
    for section: String in dockers:
        var stored: Rect2i = dockers[section]["rect"]
        var floor_size: Vector2i = dockers[section]["min"]
        # No floor is above the file's size today, and one that were would
        # grow a docker of the left half to the right.
        var opened := Rect2i(stored.position, stored.size.max(floor_size))
        assert_eq(placed[section], opened, "%s is where the file puts it" % section)


func test_the_right_column_keeps_its_distance_from_the_right_edge() -> void:
    var dockers := _shipped()
    var placed := _fit(Vector2i(1280, 1024)).place(dockers)
    var layers: Rect2i = placed["LayersDocker"]
    var colour: Rect2i = placed["ColorDocker"]
    assert_eq(layers.end.x, 1280 - 10, "the Layers docker is on a host 1280 wide, where 1600 put it nowhere")
    assert_eq(colour.end.x, 1280 - 10, "the Colour Picker too")
    assert_true(colour.end.y <= layers.position.y, "and the Colour Picker ends above the Layers title")


func test_heights_are_given_up_from_the_lowest_docker_and_never_below_a_floor() -> void:
    var wanted: Array[int] = [230, 430, 290]
    var floors: Array[int] = [212, 132, 182]
    assert_eq(SaDockerLayoutFit.shared_out(wanted, floors, 950), wanted, "room for all of them changes nothing")
    var capture: Array[int] = [230, 430, 263]
    assert_eq(SaDockerLayoutFit.shared_out(wanted, floors, 923), capture, "27 short shortens the lowest docker alone")
    var small: Array[int] = [230, 231, 182]
    var at_768 := SaDockerLayoutFit.shared_out(wanted, floors, 643)
    assert_eq(at_768, small, "307 short takes the lowest to its floor and the one above gives the rest")
    assert_eq(SaDockerLayoutFit.shared_out(wanted, floors, 100), floors, "every floor when even the floors do not fit")


## At 1280 by 800 and scale 2 the painting is what is left between the toolbox
## and the Colour Picker, where the file with no order laid every docker over
## another and over the whole of it.
func test_at_scale_2_on_1280_by_800_the_painting_shows() -> void:
    var host := Vector2i(640, 400)
    var placed := _fit(host).place(_shipped())
    assert_eq(placed["ToolBoxDocker"], Rect2i(0, 79, 60, 306), "the toolbox where the file has it, its foot at the margin")
    assert_eq(placed["ColorDocker"], Rect2i(320, 79, 310, 306), "the Colour Picker 10 in from the right edge")
    var unordered := SaDockerLayoutFit.new(host, TOP, _written_for()).place(_shipped())
    assert_eq(unordered.size(), 6, "with no order every docker is placed, as before")
    assert_true(unordered["LayersDocker"].intersects(unordered["ColorDocker"]), "and the Layers over the Colour Picker")


## A column closes for its own height, so the right column's want never closes
## the Tool Options, and a docker the order does not name is never closed. At
## 584 tall the left column's floors, the Tool Options' 255 and the Brush
## Presets' 212 with their gap, fit with 5 to spare and the right's are 4
## short.
func test_a_column_closes_the_first_docker_of_the_order_it_holds() -> void:
    var placed := _fit(Vector2i(1280, 584)).place(_shipped())
    assert_false(placed.has("MinimapDocker"), "at 1280 by 584 the Minimap closes, the first of the order its column holds")
    assert_true(placed.has("LayersDocker"), "and the Layers stays, now the Minimap's 250 is the one that did not fit")
    assert_true(placed.has("ToolOptionsDocker"), "and the Tool Options, the first of the whole order, has its column's room")
    var roomy := _fit(Vector2i(1280, 800)).place(_shipped())
    assert_eq(roomy["LayersDocker"].size, Vector2i(310, 272), "at 1280 by 800 the Layers gives up height to its floor and stays")
    var tiny := _fit(Vector2i(320, 120)).place(_shipped())
    assert_eq(tiny.keys(), ["ToolBoxDocker"], "the toolbox, which the order does not name, stays on a host too short for it")


## Width is given up down to the floors before a docker closes for it, the
## rightmost column first. A column of the right half keeps its right edge.
func test_the_columns_give_up_width_before_a_docker_closes_for_it() -> void:
    var placed := _fit(Vector2i(960, 540)).place(_shipped())
    assert_eq(placed["ColorDocker"].size.x, 214, "the Colour Picker at its floor")
    assert_eq(placed["ColorDocker"].end.x, 950, "and its right edge where the file has it")
    assert_eq(placed["ToolOptionsDocker"].size.x, 302, "then the Tool Options gives the 8 still wanted")
    assert_eq(placed["ToolBoxDocker"].size.x, 60, "and the toolbox nothing")


## The two files a fresh profile can open the default from close the same
## dockers in the same order and give the Layers docker the same floor, four
## rows tall and as wide as its blend row reads whole at.
func test_both_shipped_defaults_carry_the_same_order_and_floors() -> void:
    var orders: Array = []
    var floors: Array = []
    for path in SHIPPED_FILES:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        orders.append(cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, []))
        floors.append(cfg.get_value("LayersDocker", SaDockerLayoutRefit.FLOOR_SIZE, Vector2i()))
    var order := ["MinimapDocker", "BrushPresetsDocker", "ToolOptionsDocker", "LayersDocker", "ColorDocker"]
    assert_eq(
        orders[0], order, "the Minimap, the Brush Presets, the Tool Options, then the right column, and not the closed Reference"
    )
    assert_eq(orders[1], orders[0], "in both files")
    assert_eq(floors[0], Vector2i(310, 272), "the Layers floor")
    assert_eq(floors[1], floors[0], "in both files")


## A docker is kept on the host with its title below the bar, and a host too
## short for both keeps the title.
func test_a_docker_is_kept_below_the_bar_before_its_foot_is_kept_on_the_host() -> void:
    var fit := SaDockerLayoutFit.new(Vector2i(1280, 400), TOP, Vector2i())
    assert_eq(fit.kept(Vector2i(2000, -40), Vector2i(300, 200)), Vector2i(980, TOP), "pushed in from the right and down")
    assert_eq(fit.kept(Vector2i(100, 300), Vector2i(300, 200)), Vector2i(100, 200), "pushed up only until its foot is in")
    assert_eq(fit.kept(Vector2i(100, 300), Vector2i(300, 380)), Vector2i(100, TOP), "and never above the bar for its foot")


## A host of *host* embedding one probe window per open docker, and the store
## over them reading *live*.
func _store_on(host: Vector2i) -> DockerLayoutStore:
    _root = Node.new()
    _root.name = "D14Host"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []
    var floors := FLOORS.duplicate()
    floors["ReferenceDocker"] = REFERENCE_FLOOR
    for section: String in floors:
        var probe := Window.new()
        probe.name = section
        probe.min_size = floors[section]
        probe.size = floors[section]
        parent.add_child(probe)
        configs.append({"id": section, "name": section, "node": probe})
    var store := DockerLayoutStore.new()
    store.path = scratch_live
    store.dockers_provider = func() -> Array: return configs
    store.save_allowed = func() -> bool: return true
    store.top_inset = func() -> int: return TOP
    _root.add_child(store)
    return store


## The sections of the dockers open in *store*, sorted.
func _open(store: DockerLayoutStore) -> Array:
    var out: Array = []
    for config: Dictionary in store.dockers_provider.call():
        if (config["node"] as Window).visible:
            out.append(config["id"])
    out.sort()
    return out


func _rects(store: DockerLayoutStore) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in store.dockers_provider.call():
        var win: Window = config["node"]
        out[config["id"]] = Rect2i(win.position, win.size)
    return out


func test_a_first_run_is_fitted_to_the_host_it_opens_on() -> void:
    var store := _store_on(Vector2i(1280, 1024))
    store.restore_all()
    var expected := _fit(_above_the_line(Vector2i(1280, 1024))).place(_shipped())
    var rects := _rects(store)
    for section: String in expected:
        assert_eq(rects[section], expected[section], "%s is where the fit puts it" % section)


## A first run on a window too small for the six opens the ones the fit keeps
## and closes the rest, and a layout that is still `default` forks nothing.
func test_a_first_run_on_a_small_host_opens_only_what_has_room() -> void:
    var store := _store_on(Vector2i(640, 400))
    store.restore_all()
    var expected := _fit(_above_the_line(Vector2i(640, 400))).place(_shipped())
    assert_eq(_open(store), _open_on(Vector2i(640, 400)), "the toolbox and the Colour Picker open")
    var rects := _rects(store)
    for section: String in expected:
        assert_eq(rects[section], expected[section], "%s is where the fit puts it" % section)
    assert_eq(store.current_preset(), "default", "and the layout is still default")


## The shipped default is fitted again on a resize, and the window grown back
## gives every docker the rectangle it opened with.
func test_a_resize_fits_the_default_again_and_a_grow_gives_it_back() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var opened := _rects(store)
    var viewport := store.get_parent().get_child(0) as SubViewport
    viewport.size = Vector2i(1280, 1024)
    store.reflow_to_host()
    var expected := _fit(_above_the_line(Vector2i(1280, 1024))).place(_shipped())
    var rects := _rects(store)
    for section: String in expected:
        assert_eq(rects[section], expected[section], "%s is where the fit puts it on the smaller host" % section)
    viewport.size = Vector2i(1920, 1080)
    store.reflow_to_host()
    assert_eq(_rects(store), opened, "and every docker is back where it opened once the window grows")


## A host that shrinks closes the dockers it has no room for and opens them
## again where they opened once it grows, which a scale change does too.
func test_a_shrink_closes_what_has_no_room_and_a_grow_opens_it_again() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var opened := _rects(store)
    var viewport := store.get_parent().get_child(0) as SubViewport
    viewport.size = Vector2i(640, 400)
    store.reflow_to_host()
    assert_eq(_open(store), _open_on(Vector2i(640, 400)), "a host of 640 by 400 keeps two open")
    var expected := _fit(_above_the_line(Vector2i(640, 400))).place(_shipped())
    var rects := _rects(store)
    for section: String in expected:
        assert_eq(rects[section], expected[section], "%s is where the fit puts it" % section)
    viewport.size = Vector2i(1920, 1080)
    store.reflow_to_host()
    assert_eq(_open(store), _open_on(Vector2i(1920, 1080)), "and the six are open again once it grows")
    assert_eq(_rects(store), opened, "where they opened")


## The fit opens again only what it closed. A docker closed some other way, by
## the painter or by the boot, stays closed, and while Tab has the dockers
## hidden the fit shows and hides nothing, since `SaFocusMode` keeps what was
## open.
func test_the_fit_opens_only_what_it_closed() -> void:
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var viewport := store.get_parent().get_child(0) as SubViewport
    var tool_options := viewport.get_child(0).get_node("ToolOptionsDocker") as Window
    tool_options.hide()
    viewport.size = Vector2i(640, 400)
    store.reflow_to_host()
    viewport.size = Vector2i(1920, 1080)
    store.reflow_to_host()
    assert_false(tool_options.visible, "the Tool Options closed by hand stays closed")
    assert_true(_open(store).has("LayersDocker"), "and the Layers the fit closed is open again")

    for config: Dictionary in store.dockers_provider.call():
        (config["node"] as Window).hide()
    SaFocusMode.active = true
    viewport.size = Vector2i(640, 400)
    store.reflow_to_host()
    viewport.size = Vector2i(1920, 1080)
    store.reflow_to_host()
    SaFocusMode.active = false
    assert_eq(_open(store), [], "under Tab a shrink and a grow open nothing")

    viewport.size = Vector2i(640, 400)
    store.reflow_to_host()
    # Tab's way back shows the six it hid, and not the closed Reference.
    for config: Dictionary in store.dockers_provider.call():
        if FLOORS.has(config["id"]):
            (config["node"] as Window).show()
    store.reflow_to_host()
    var tab_back := _open_on(Vector2i(640, 400))
    assert_eq(_open(store), tab_back, "and the reflow after Tab's way back closes what has no room")


## A first run leaves the Reference closed where the file
## keeps it, and neither a shrink nor a grow opens it, since the fit opens only
## what it closed.
func test_a_first_run_leaves_the_reference_closed_through_a_shrink_and_a_grow() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var viewport := store.get_parent().get_child(0) as SubViewport
    var closed := viewport.get_child(0).get_node("ReferenceDocker") as Window
    assert_false(closed.visible, "the Reference is closed on the first run")
    assert_eq(_rects(store)["ReferenceDocker"], REFERENCE_RECT, "in its place beside the columns")
    for host: Vector2i in [Vector2i(640, 400), Vector2i(1280, 800), Vector2i(1920, 1048), Vector2i(1920, 1080)]:
        viewport.size = host
        store.reflow_to_host()
        assert_false(closed.visible, "and still closed after a reflow to %s" % host)
    assert_eq(_rects(store)["ReferenceDocker"], REFERENCE_RECT, "back in its place once the window grows")


func test_a_layout_the_painter_saved_is_never_refitted() -> void:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, "default (custom)")
    cfg.set_value("ToolOptionsDocker", "position", Vector2i(400, 300))
    cfg.save(scratch_live)
    var store := _store_on(Vector2i(1280, 1024))
    store.restore_all()
    var rects := _rects(store)
    assert_eq(rects["ToolOptionsDocker"].position, Vector2i(400, 300), "where the painter put it")
    _assert_as_the_file_stands(store, rects, "and the rest as the file stands, its strips in reach on a host 1280 wide")


func test_a_file_that_names_no_layout_is_the_painters_own() -> void:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    cfg.erase_section_key(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET)
    cfg.save(scratch_live)
    var store := _store_on(Vector2i(1280, 1024))
    store.restore_all()
    _assert_as_the_file_stands(store, _rects(store), "a profile from before presets is not refitted")


## A painter's layout restored on a host 1280 by 1024 is not refitted. Each
## docker keeps its title strip in reach the way a resize keeps it, and the file's place is remembered, so the
## host grown to 1920 by 1080
## puts it back there.
##
## The fit would pull the Layers docker in to end 10 short of x 1280, and the
## strip rule moves it no further than leaves 128 of its strip on the host,
## where it would otherwise stand wholly inside. It stands at the file's x 1600,
## outside the window, and loading Useful into a window that size must not lose
## its right column. It stands at x 1600 again only where
## a screen reaches that far, because the store never places a docker where no
## screen shows it (`SaDockerStoredEntry.scaled`). On a screen 1280 wide the
## store rightly leaves Layers where the probe was, at (0, 0), and the suite
## must not read that as a move.
func _assert_as_the_file_stands(store: DockerLayoutStore, rects: Dictionary, why: String) -> void:
    var shipped := _shipped()
    var fitted: Rect2i = _fit(Vector2i(1280, 1024)).place(shipped)["LayersDocker"]
    var restored: Rect2i = rects["LayersDocker"]
    assert_true(restored.position != fitted.position, "%s, the Layers %s is not where a fit puts it" % [why, restored])
    var stored: Rect2i = shipped["LayersDocker"]["rect"]
    if not SaDockerStoredEntry.all_screens_rect().intersects(Rect2i(stored.position, restored.size)):
        skip("no screen here reaches x 1600, so the store keeps the Layers docker off it, as it should")
        return
    var below_bar := Rect2i(0, TOP, 1280, 1024 - TOP)
    var reached := SaDockerLayoutFit.reached(stored.position, restored.size, below_bar)
    assert_eq(restored.position, reached, "%s: the Layers keeps its strip in reach" % why)
    assert_eq(restored.position.x, 1280 - SaDockerLayoutFit.STRIP_IN_REACH.x, "%s: and no further in" % why)
    var viewport := store.get_parent().get_child(0) as SubViewport
    viewport.size = Vector2i(1920, 1080)
    store.reflow_to_host()
    assert_eq(_rects(store)["LayersDocker"].position, stored.position, "%s: the Layers, back once the host has room" % why)


func test_the_welcome_window_comes_in_front_of_the_dockers_the_boot_opened() -> void:
    var store := _store_on(Vector2i(1280, 1024))
    var viewport := store.get_parent().get_child(0) as SubViewport
    var welcome := SaWelcomeWindow.new()
    welcome.visible = false
    viewport.get_child(0).add_child(welcome)
    welcome.show()
    # What the boot does after the Welcome window is up: every docker opens.
    for config: Dictionary in store.dockers_provider.call():
        (config["node"] as Window).hide()
        (config["node"] as Window).show()
    var stack := viewport.get_embedded_subwindows()
    assert_true(stack[-1] != welcome, "a docker the boot opened is in front of it, which was the fault")
    welcome.come_forward()
    stack = viewport.get_embedded_subwindows()
    assert_eq(stack[-1], welcome, "and after the boot the Welcome window is in front of every docker")


## Whether no screen here is 1920 wide. These tests lay the shipped layout on a
## host of 1920 by 1080, and the store rightly keeps every docker on a screen,
## so on a smaller screen it puts them where no 1920 wide layout has them.
func _no_screen_is_1920_wide() -> bool:
    return SaDockerStoredEntry.all_screens_rect().size.x < 1920
