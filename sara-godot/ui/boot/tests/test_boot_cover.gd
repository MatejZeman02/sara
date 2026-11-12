## The boot hides behind a picture of the last session, with a progress line
##.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A quit keeps the window's picture at a quarter of its size, and the next
## boot's cover is the topmost child before `ui_built`, names each stage in
## order, and is gone after the fade that follows `boot_finished`. With no
## saved picture, a window of another shape, or the Preferences switch off, the
## cover holds the stock picture. `scenarios/the-boot-hides-behind-a-picture-of-the-last-session.json`
## shoots the cover on the running app, held at the modules stage.
extends "res://tests/test_framework.gd"

static var scratch_picture: String = SaDataRoot.path("test_s8_last_session.webp")
static var scratch_layout: String = SaDataRoot.path("test_s8_docker_layout.cfg")


## A Main that runs no boot, for the quit, and draws from a planted canvas.
class QuietMain:
    extends "res://ui/main/main.gd"

    var planted: SaCanvas = null

    func _ready() -> void:
        pass

    func get_canvas() -> SaCanvas:
        return planted


## A Main whose every stage writes down what the cover showed there.
class RecordingMain:
    extends "res://ui/main/main.gd"

    ## [stage, the cover the topmost child as the stage is reached, the
    ## line's words then, whether the cover is still a child]
    var seen: Array = []
    var source := ""

    func _reach(stage: StringName, ds_name: String) -> bool:
        if source.is_empty() and _cover != null:
            source = _cover._source
        var held := super(stage, ds_name)
        var on_top := _cover != null and is_instance_valid(_cover) and get_child(-1) == _cover
        var still := _cover != null and is_instance_valid(_cover) and _cover.get_parent() == self
        var words: String = _cover._label.text if still else ""
        seen.append([stage, on_top, words, still])
        return held


var _host: Node = null
var _kept_switch := true


func before_each() -> void:
    _kept_switch = SaSettings.show_last_session
    SaSettings.show_last_session = true
    _host = Node.new()
    _host.name = "S8TestHost"
    EventBus.add_child(_host)
    _remove(scratch_picture)


func after_each() -> void:
    SaSettings.show_last_session = _kept_switch
    if _host != null:
        _host.free()
        _host = null
    _remove(scratch_picture)
    _remove(scratch_layout)
    # The Main ran its boot by hand and loaded every module, and a Main never
    # parented never puts them down, so the linux-pen module's reader thread
    # outlived the run and threw at exit.
    ModuleLoader.unload_all()


func test_a_quit_keeps_the_window_at_a_quarter_of_its_size() -> void:
    var planted := _planted_canvas()
    var main := _quiet_main(planted)
    main._request_quit()
    assert_true(FileAccess.file_exists(scratch_picture), "The quit wrote the picture")
    var image := Image.load_from_file(scratch_picture)
    var window := main.get_viewport().get_texture().get_size()
    assert_not_null(image, "and it reads back")
    if image != null:
        assert_eq(image.get_width(), floori(window.x / SaBootCover.SCALE_DOWN), "a quarter of the window's width")
        assert_eq(image.get_height(), floori(window.y / SaBootCover.SCALE_DOWN), "and of its height")
    _answer_and_free(main, planted)


func test_with_the_switch_off_a_quit_writes_no_picture_and_removes_the_last() -> void:
    _save_picture(DisplayServer.window_get_size())
    SaSettings.show_last_session = false
    var planted := _planted_canvas()
    var main := _quiet_main(planted)
    main._request_quit()
    assert_false(FileAccess.file_exists(scratch_picture), "No painting is left in the user folder")
    _answer_and_free(main, planted)


func test_the_cover_is_on_top_and_names_each_stage_until_it_fades() -> void:
    _save_picture(DisplayServer.window_get_size())
    var main := _booted_main()

    assert_eq(main.source, "last session", "The cover drew the saved picture")
    var stages: Array = []
    for entry: Array in main.seen:
        stages.append(entry[0])
    assert_eq(
        stages,
        [&"ui_built", &"modules_bootstrapped", &"blend_favourites_canonical", &"boot_finished"],
        "Every stage after the first was reached, in order"
    )
    if main.seen.size() == 4:
        assert_true(main.seen[0][1], "The cover is the topmost child when ui_built is reached, over all it built")
        for index in 3:
            assert_eq(main.seen[index][2], SaBootCover.STAGES[index + 1][1], "The line names %s" % stages[index])
            assert_true(main.seen[index][3], "and the cover is still up after %s" % stages[index])
        assert_false(main.seen[3][3], "No cover after the fade that follows boot_finished")
    main.free()


## The boot gave each docker it built a page on Layouts and
## dockers, in the `SaSettings` autoload, and the freed `Main` left them there.
## The search suite, run after this one, then listed Brush Presets twice,
## once as the docker and once as that page's setting. The pages go with the
## dockers' owner now, so the suite leaves the autoload's pages as it found them.
func test_a_freed_boot_leaves_no_dockers_page_behind() -> void:
    var pages := SaSettings.reorderable_categories()
    var main := _booted_main()
    var built := SaSettings.reorderable_categories()
    assert_true(built.size() > pages.size(), "The boot gave its dockers pages: %d more" % (built.size() - pages.size()))
    main.free()
    assert_eq(SaSettings.reorderable_categories(), pages, "and the freed Main took every one of them with it")


func test_the_stock_picture_stands_in_with_no_picture_another_shape_or_the_switch_off() -> void:
    var size := Vector2i(1600, 900)
    _expect_source(size, true, "stock", "No saved picture")
    _save_picture(size)
    _expect_source(size, true, "last session", "A saved picture of the same shape")
    _expect_source(size, false, "stock", "The switch off")
    _expect_source(Vector2i(900, 900), true, "stock", "A window of another shape")


func test_a_new_cover_shows_the_first_stage_and_ignores_a_name_it_does_not_know() -> void:
    var cover := SaBootCover.new(Vector2i(800, 600), scratch_picture, true)
    assert_eq(cover._label.text, SaBootCover.STAGES[0][1], "The first stage's words")
    assert_eq(cover._fill.anchor_right, 0.0, "and an empty line")
    cover.reach(&"not_a_stage")
    assert_eq(cover._stage, SaBootCover.STAGES[0][0], "An unknown mark moves nothing")
    cover.reach(&"modules_bootstrapped")
    assert_eq(cover._fill.anchor_right, 0.5, "Half way at the third of five")
    assert_eq(cover.layer, SaBootCover.LAYER, "Above the embedded windows' canvas")
    assert_eq(cover._root.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and it takes no input")
    cover.free()


func test_the_hold_flag_names_its_stage() -> void:
    assert_eq(SaBootCover.held_at(PackedStringArray(["--capture=x", "--hold-boot-at=ui_built"])), &"ui_built", "Read")
    assert_eq(SaBootCover.held_at(PackedStringArray(["--capture=x"])), &"", "and absent")


## A `RecordingMain` booted by hand, outside the tree, the way the runner can.
func _booted_main() -> RecordingMain:
    var main := RecordingMain.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_layout
    main.last_session_path = scratch_picture
    main._ready()
    return main


func _expect_source(size: Vector2i, show_last: bool, wanted: String, why: String) -> void:
    var cover := SaBootCover.new(size, scratch_picture, show_last)
    assert_eq(cover._source, wanted, why)
    cover.free()


func _save_picture(window: Vector2i) -> void:
    var image := Image.create(maxi(1, floori(window.x / 4.0)), maxi(1, floori(window.y / 4.0)), false, Image.FORMAT_RGBA8)
    image.fill(Color(0.6, 0.3, 0.2))
    image.save_webp(scratch_picture)


func _quiet_main(planted: SaCanvas) -> QuietMain:
    var main := QuietMain.new()
    main.name = "Main"
    main.is_test_environment = true
    main.planted = planted
    main.last_session_path = scratch_picture
    _host.add_child(main)
    return main


func _answer_and_free(main: QuietMain, planted: SaCanvas) -> void:
    for child in main._files.get_children():
        if child is SaMessage:
            child._answer(SaDocumentFiles.PROMPT_CANCEL)
    _host.remove_child(main)
    main.free()
    var easel := planted.easel
    var document := easel.document
    planted.free()
    easel.free()
    document.free()


func _planted_canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.easel = SaEasel.new()
    canvas.easel.document = SaDocument.new()
    canvas.easel.document.modified = true
    return canvas


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
