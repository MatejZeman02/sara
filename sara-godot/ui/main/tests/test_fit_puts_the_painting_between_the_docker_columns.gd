## Fit puts the painting between the docker columns.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The default dockers covered from 28 to 60 per cent of the painting, and
## both paintings had their subject under one. The
## dockers stay floating, so the view counts every docker as a side
## cover and Fit fits into the free rectangle between them, while the second
## View row, Fit to Window, fits the whole visible rectangle as Fit did before.
##
## What is stated here is the free rectangle on a real canvas view with the
## dockers of the three shipped layouts as embedded windows, read out of the
## layout files themselves, the fit and the centre placed inside it, Fit to
## Window ignoring it, the boot's fit following a docker that hides, and the
## View menu's new row. The shots are
## `scenarios/fit-puts-the-painting-between-the-docker-columns.json` and its
## twin at 1280 by 1024.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The window every shipped layout is written for, and the bar over it, which
## ends above the dockers' first row at 79.
const WINDOW := Vector2i(1920, 1080)
const BAR := 65.0

## Where the left column ends in the layouts that keep the toolbox 10 px from
## the edge, and where the right column starts in all three.
const LEFT_COLUMN_END := 380.0
## The default layout butts its dockers edge to edge, so its left column starts
## at 60 and ends at 370.
const DEFAULT_LEFT_COLUMN_END := 370.0
const RIGHT_COLUMN_START := 1600.0

var _host: Node = null
## The fit the menu commands asked for, one entry a call, true for the whole
## window.
var _asked: Array[bool] = []


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "N5TestHost"
    EventBus.add_child(_host)
    _asked.clear()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_the_default_layouts_columns_leave_the_room_between_them() -> void:
    var view := _view_over_layout("res://layouts/default.cfg", WINDOW)
    var free := view.get_free_rect()
    assert_almost_eq(free.position.x, DEFAULT_LEFT_COLUMN_END, 1e-3, "The free rectangle starts where the left column ends")
    assert_almost_eq(free.end.x, RIGHT_COLUMN_START, 1e-3, "and ends where the right column starts")
    assert_almost_eq(free.position.y, BAR, 1e-3, "below the bar")
    assert_almost_eq(free.end.y, float(WINDOW.y), 1e-3, "and down to the window's bottom edge")


## The Useful layout's minimap heads the right column, and its Graph stands
## open in the middle. The Graph is 380 wide, and counted it would leave the
## painting too little, so it is skipped. The minimap stood beside the left
## column, and the Info docker before it, before the minimap moved.
func test_the_useful_layout_skips_the_minimap() -> void:
    var view := _view_over_layout("res://layouts/useful.cfg", WINDOW)
    var minimap := _side_named("MinimapDocker")
    assert_not_null(minimap, "The Useful layout opens the minimap")
    assert_true(minimap.visible and minimap.position.x * 2 > WINDOW.x, "shown, at the top of the right column")
    var graph := _side_named("GraphDocker")
    assert_true(graph != null and graph.visible, "the graph is shown in the middle")
    assert_false(_side_named("InfoDocker").visible, "and keeps the Info docker closed")
    var free := view.get_free_rect()
    assert_almost_eq(free.position.x, LEFT_COLUMN_END, 1e-3, "The graph does not move the left edge")
    assert_almost_eq(free.end.x, RIGHT_COLUMN_START, 1e-3, "and the right column still counts")


## The Full layout adds the Recorder, the Graph and the History in the middle
## as well, right of it, and none of the four floating dockers counts.
func test_the_full_layout_skips_every_docker_in_the_middle() -> void:
    var view := _view_over_layout("res://layouts/full.cfg", WINDOW)
    var free := view.get_free_rect()
    assert_almost_eq(free.position.x, LEFT_COLUMN_END, 1e-3, "The left edge is the left column's")
    assert_almost_eq(free.end.x, RIGHT_COLUMN_START, 1e-3, "and the right edge the right column's")


## The window kept as the stress test. The default layout fitted to
## it leaves 580 of 1280 between its columns, under the half a floating docker
## has to leave, and both columns still count because both stand against an
## edge.
func test_the_default_columns_both_count_on_a_window_1280_by_1024() -> void:
    var free := _free_on_default_fitted_to(Vector2i(1280, 1024))
    assert_almost_eq(free.position.x, DEFAULT_LEFT_COLUMN_END, 1e-3, "The left column counts")
    assert_almost_eq(free.end.x, 1280.0 - (WINDOW.x - RIGHT_COLUMN_START), 1e-3, "and so does the right")
    assert_true(free.size.x < 1280.0 * SaCanvasView.FREE_WIDTH_FLOOR, "though they leave less than the floor")


## The same window at an interface scale of 1.25, 1024 units wide, where the
## columns leave 324. Two fifths of the width as the floor for every docker,
## which was tried first, skipped the left column here.
func test_the_default_columns_both_count_at_a_scale_of_1_25_there() -> void:
    var free := _free_on_default_fitted_to(Vector2i(1024, 819))
    assert_almost_eq(free.position.x, DEFAULT_LEFT_COLUMN_END, 1e-3, "The left column counts")
    assert_almost_eq(free.end.x, 1024.0 - (WINDOW.x - RIGHT_COLUMN_START), 1e-3, "and so does the right")
    assert_true(free.size.x < 1024.0 * 0.4, "though they leave less than two fifths")


## A docker floating away from the edges counts when it leaves at least half,
## as the Layers docker does where a scenario parks it at x 1200.
func test_a_floating_docker_that_leaves_half_counts() -> void:
    var viewport := _viewport(WINDOW)
    var view := SaCanvasView.for_canvas(_canvas(viewport))
    _cover(viewport, Rect2(0.0, 0.0, float(WINDOW.x), BAR))
    _side(viewport, Rect2(1200.0, 120.0, 400.0, 500.0), true, "Parked")
    var free := view.get_free_rect()
    assert_almost_eq(free.position.x, 0.0, 1e-3, "Nothing on the left")
    assert_almost_eq(free.end.x, 1200.0, 1e-3, "and the parked docker's left side is the right edge")


func test_with_no_side_covers_the_free_rectangle_is_the_visible_one() -> void:
    var viewport := _viewport(WINDOW)
    var view := SaCanvasView.for_canvas(_canvas(viewport))
    _cover(viewport, Rect2(0.0, 0.0, float(WINDOW.x), BAR))
    assert_eq(view.get_free_rect(), view.get_visible_rect(), "Nothing beside the document leaves the visible rectangle")


## A docker hidden by Tab hides nothing, a window outside the group is not a
## docker, and a docker embedded in another viewport stands over that one.
func test_only_a_shown_docker_over_this_viewport_counts() -> void:
    var viewport := _viewport(WINDOW)
    var view := SaCanvasView.for_canvas(_canvas(viewport))
    _cover(viewport, Rect2(0.0, 0.0, float(WINDOW.x), BAR))
    _side(viewport, Rect2(0.0, 79.0, 380.0, 900.0), false, "Hidden")
    var stranger := _side(viewport, Rect2(1600.0, 79.0, 310.0, 900.0), true, "Stranger")
    stranger.remove_from_group(SaCanvasView.SIDE_COVER_GROUP)
    var elsewhere := _viewport(WINDOW)
    _side(elsewhere, Rect2(1600.0, 79.0, 310.0, 900.0), true, "Elsewhere")
    assert_eq(view.get_free_rect(), view.get_visible_rect(), "None of the three moves an edge")


func test_fit_centres_the_document_between_the_columns() -> void:
    var view := _view_over_layout("res://layouts/default.cfg", WINDOW)
    view.set_zoom(3.0)
    view.set_pan(Vector2(-900.0, -900.0))
    var document := Vector2i(2400, 1000)

    view.fit(document)

    var free := view.get_free_rect()
    var top_left := view.document_to_screen(Vector2.ZERO)
    var bottom_right := view.document_to_screen(Vector2(document))
    assert_almost_eq(view.get_zoom(), free.size.x / 2400.0, 1e-5, "The width between the columns decides the zoom")
    assert_almost_eq(top_left.x, DEFAULT_LEFT_COLUMN_END, 1e-3, "The left edge is the left column's")
    assert_almost_eq(bottom_right.x, RIGHT_COLUMN_START, 1e-3, "and the right edge the right column's")
    assert_almost_eq((top_left.y + bottom_right.y) * 0.5, free.get_center().y, 1e-3, "centred down the free height")


func test_centre_puts_the_middle_in_the_middle_of_the_free_rectangle() -> void:
    var view := _view_over_layout("res://layouts/default.cfg", WINDOW)
    view.set_zoom(0.5)
    view.set_pan(Vector2(-900.0, -900.0))

    view.center(Vector2i(1000, 800))

    var middle := view.document_to_screen(Vector2(500.0, 400.0))
    assert_almost_eq(view.get_zoom(), 0.5, 1e-6, "The zoom is the painter's")
    var between := (DEFAULT_LEFT_COLUMN_END + RIGHT_COLUMN_START) * 0.5
    assert_almost_eq(middle.x, between, 1e-3, "and the middle is between the columns")


## What View > Fit to Window asks the view for: the visible rectangle, with the
## dockers still there over it.
func test_fit_to_window_takes_the_whole_visible_rectangle_with_the_dockers_shown() -> void:
    var view := _view_over_layout("res://layouts/default.cfg", WINDOW)
    var document := Vector2i(2400, 1000)

    view.fit_into(document, view.get_visible_rect())

    assert_true(view.get_free_rect().size.x < WINDOW.x, "The dockers are there")
    assert_almost_eq(view.get_zoom(), WINDOW.x / 2400.0, 1e-5, "and the window's width decides the zoom")
    assert_almost_eq(view.document_to_screen(Vector2.ZERO).x, 0.0, 1e-3, "The document starts at the window's left edge")
    assert_almost_eq(view.document_to_screen(Vector2(document)).x, float(WINDOW.x), 1e-3, "and ends at its right")


## The boot's fit is held until the painter starts, and a docker that hides in
## that time, by Tab or by a layout, gives its room back to the fit.
func test_the_boot_fit_follows_a_docker_that_hides() -> void:
    var viewport := _viewport(WINDOW)
    var canvas := _canvas(viewport)
    var cover := _cover(viewport, Rect2(0.0, 0.0, float(WINDOW.x), BAR))
    var side := _side(viewport, Rect2(0.0, 79.0, 380.0, 900.0), true, "Column")
    canvas.resize_canvas(Vector2i(1024, 1024))
    var covers: Array[Control] = [cover]
    var hold := SaBootFit.new(canvas, SaCanvasView.for_canvas(canvas), covers, null)
    _host.add_child(hold)
    hold.fit_again()
    var view := SaCanvasView.for_canvas(canvas)
    assert_almost_eq(view.document_to_screen(Vector2(512.0, 512.0)).x, (380.0 + WINDOW.x) * 0.5, 1e-3, "Fitted beside the column")

    side.visible = false
    assert_true(hold._queued, "The docker hiding queues a fit")
    hold.fit_again()
    assert_almost_eq(view.document_to_screen(Vector2(512.0, 512.0)).x, WINDOW.x * 0.5, 1e-3, "and the fit takes the room back")
    assert_true(hold._held, "A fit it made itself does not end the hold")


## Read as source, because main needs the whole application to build: every
## docker the registry builds a window for joins the group, a module's too.
func test_every_registered_docker_is_a_side_cover() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/main_dockers.gd")
    var body := source.substr(source.find("func instantiate_registered_dockers"))
    body = body.substr(0, body.find("\nfunc "))
    assert_true(body.contains("win.add_to_group(SaCanvasView.SIDE_COVER_GROUP)"), "Each docker's window is a side cover")


## Fit to Window is the shortcut table's fit asked for the whole window, and
## Fit to View the same fit asked for the free rectangle.
func test_the_two_fit_rows_run_one_fit_with_two_rooms() -> void:
    var menu_commands := SaMenuCommands.new(_spy_fit, Callable(), Callable(), Callable())
    var rows := {}
    for command: SaCommandDescriptor in menu_commands.commands():
        rows[command.id] = command
    assert_true(rows.has(&"view_fit_window"), "There is a Fit to Window command")
    var fit_window: SaCommandDescriptor = rows[&"view_fit_window"]
    assert_eq(fit_window.menu_label(), "Fit to Window", "and its row reads Fit to Window")
    assert_true(fit_window.default_events.is_empty(), "with no chord, a row on the Shortcuts page a painter can give one")

    fit_window.handler.call()
    (rows[&"view_fit"] as SaCommandDescriptor).handler.call()
    assert_eq(_asked, [true, false] as Array[bool], "Fit to Window asks for the whole window and Fit to View does not")


func test_the_view_menu_lists_fit_to_window_under_fit_to_view() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var popup: SaChoicePopup = bar.menus.get("View")
    var ids := SaMenu.list_holding(popup, SaMenu.key(SaViewMenu.ID_FIT)).row_ids()
    var fit := ids.find(SaMenu.key(SaViewMenu.ID_FIT))
    assert_true(fit >= 0, "The View menu has Fit to View")
    assert_eq(ids.find(SaMenu.key(SaViewMenu.ID_FIT_WINDOW)), fit + 1, "and Fit to Window right under it")
    bar.free()


## The free rectangle on a host of *host*, under a bar, with the Default
## layout's shown dockers where `SaDockerLayoutFit` puts them on it.
func _free_on_default_fitted_to(host: Vector2i) -> Rect2:
    var placed := SaDockerLayoutFit.new(host, 79, WINDOW).place(_stored("res://layouts/default.cfg", true))
    var viewport := _viewport(host)
    var view := SaCanvasView.for_canvas(_canvas(viewport))
    _cover(viewport, Rect2(0.0, 0.0, float(host.x), BAR))
    for section: String in placed:
        _side(viewport, Rect2(placed[section]), true, section)
    return view.get_free_rect()


func _spy_fit(whole: bool = false) -> bool:
    _asked.append(whole)
    return true


## A canvas view over a viewport the size of *window*, under a bar, with the
## dockers of the layout file at *path* as embedded windows where the file puts
## them, shown or hidden as it says.
func _view_over_layout(path: String, window: Vector2i) -> SaCanvasView:
    var viewport := _viewport(window)
    var view := SaCanvasView.for_canvas(_canvas(viewport))
    _cover(viewport, Rect2(0.0, 0.0, float(window.x), BAR))
    var stored := _stored(path, false)
    for section: String in stored:
        _side(viewport, Rect2(stored[section]["rect"]), stored[section]["visible"], section)
    return view


## Section to `{"rect", "visible", "min"}` for every docker in the layout file at
## *path*, the shown ones alone when *shown_only*.
func _stored(path: String, shown_only: bool) -> Dictionary:
    var file := ConfigFile.new()
    assert_eq(file.load(path), OK, "%s reads" % path)
    var out: Dictionary = {}
    for section: String in file.get_sections():
        if section.begins_with("_layout"):
            continue
        var shown := bool(file.get_value(section, "visible", false))
        if shown_only and not shown:
            continue
        var rect := Rect2i(file.get_value(section, "position", Vector2i.ZERO), file.get_value(section, "size", Vector2i.ZERO))
        out[section] = {"rect": rect, "visible": shown, "min": Vector2i(60, 120)}
    return out


func _viewport(viewport_size: Vector2i) -> SubViewport:
    var viewport := SubViewport.new()
    viewport.size = viewport_size
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    return viewport


func _canvas(viewport: SubViewport) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    return canvas


func _cover(viewport: SubViewport, rect: Rect2) -> Control:
    var cover := Control.new()
    cover.position = rect.position
    cover.size = rect.size
    cover.add_to_group(SaCanvasView.COVER_GROUP)
    viewport.add_child(cover)
    return cover


## A docker's stand-in, embedded in *viewport* and in the side cover group, the
## way `instantiate_registered_dockers` leaves a docker.
func _side(viewport: SubViewport, rect: Rect2, shown: bool, side_name: String) -> Window:
    var side := Window.new()
    side.name = side_name
    side.borderless = true
    side.position = Vector2i(rect.position)
    side.size = Vector2i(rect.size)
    side.visible = shown
    side.add_to_group(SaCanvasView.SIDE_COVER_GROUP)
    viewport.add_child(side)
    if shown:
        assert_true(side.is_embedded(), "The stand-in must embed, or this suite measures nothing")
    return side


func _side_named(side_name: String) -> Window:
    for node in _host.get_tree().get_nodes_in_group(SaCanvasView.SIDE_COVER_GROUP):
        if node.name == side_name and _host.is_ancestor_of(node):
            return node as Window
    return null
