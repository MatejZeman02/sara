## Load Tip on an `.abr` opens a chooser and loads the tip picked.
##
## The chooser is built on the `.abr` fixtures. The version 1 file's computed brush
## is read as a refused cell with its sentence, the version 6 file's three
## pictures as cells by name, and the tip picked is read back from the `.png` it
## was written as, texel for texel, with its name and spacing. Load Tip's
## filters gain `.abr`, and the single tip reader's sentence for one sends the
## painter to Load Tip.
##
## The chooser lives in `ui/pickers`, and core reaches it
## through `SaDialogsInHand`, so the `.abr` branch is read here through that
## door: with a stand-in attached, with `SaPickers` attached, and with nothing
## attached, where Load Tip says so in the corner.
extends "res://tests/test_framework.gd"

const AbrWriter = preload("res://core/api/abr/tests/abr_writer.gd")

## Every name a pick here can be written under, cleared before and after each
## test so a file another run left does not take a name.
const STEMS: Array[String] = ["Dry Disc", "Left Half", "Deep Ramp", "a-computed-brush-and-a-picture-v1 2"]

var _refused: Array[String] = []
var _chosen: Array[String] = []

## What the door had attached before each test, put back after it.
var _owner_before: Object = null
var _abr_before: Callable = Callable()
var _file_dialog_before: Callable = Callable()


func before_each() -> void:
    _owner_before = SaDialogsInHand._owner
    _abr_before = SaDialogsInHand._abr
    _file_dialog_before = SaDialogsInHand._file_dialog
    _refused.clear()
    _chosen.clear()
    _clear_written()
    EventBus.paint_refused.connect(_on_refused)


func after_each() -> void:
    SaDialogsInHand.detach(self)
    if _owner_before != null:
        SaDialogsInHand.attach(_owner_before, _abr_before, _file_dialog_before)
    EventBus.paint_refused.disconnect(_on_refused)
    _clear_written()


func _on_refused(sentence: String) -> void:
    _refused.append(sentence)


func _clear_written() -> void:
    var folder := SaBrushTipMask.saved_dir()
    if not DirAccess.dir_exists_absolute(folder):
        return
    for file in DirAccess.get_files_at(folder):
        for stem in STEMS:
            if file.begins_with(stem) and file.ends_with(".png"):
                DirAccess.remove_absolute(folder.path_join(file))


func _chooser(fixture: String) -> SaAbrChooser:
    var read := SaAbrCollection.load_from(AbrWriter.FIXTURE_DIR.path_join(fixture))
    assert_true(read.ok(), "%s is read, read '%s'" % [fixture, read.error])
    return SaAbrChooser.new(read, _chosen.append)


func _cell(chooser: SaAbrChooser, place: int) -> Button:
    return chooser.cells.get_node_or_null("AbrTip%d" % place) as Button


## The first texel of *tip*'s mask that differs from *expected*'s by more than
## *within*, or -1.
func _differs(tip: SaTipImage.Tip, expected: SaTipImage.Tip, within: float) -> int:
    for i in mini(tip.mask.size(), expected.mask.size()):
        if absf(tip.mask[i] - expected.mask[i]) > within:
            return i
    return -1


func test_load_tip_offers_an_abr() -> void:
    var lines := SaBrushTipMask.load_filters()
    assert_true(lines[0].contains("*.abr"), "The Brush Tip line, the first, takes .abr, read '%s'" % lines[0])
    assert_true(lines[0].contains("*.png") and lines[0].contains("*.gih"), "beside what it took before")
    assert_true("\n".join(lines).contains("*.abr ; Photoshop Brushes"), "and a Photoshop line stands of its own")
    assert_eq(lines.size(), 5, "Five lines, the Photoshop one added")


func test_the_single_tip_reader_sends_an_abr_to_load_tip() -> void:
    var tip := SaTipImage.load_bytes(PackedByteArray([1, 2, 3]), "dry media.abr")
    assert_false(tip.ok(), "The single tip reader still takes no collection")
    assert_eq(
        tip.error, "dry media.abr is a brush collection. Load Tip opens it and loads the tip picked from it.", "The new sentence"
    )
    assert_false(tip.error.contains("yet"), "and it no longer says not yet")


func test_a_computed_brush_is_a_refused_cell_with_its_sentence() -> void:
    var chooser := _chooser(AbrWriter.V1_NAME)
    var sentence := chooser.collection.tips[0].error
    assert_true(sentence.contains("is a computed brush"), "The reader refused the computed brush, read '%s'" % sentence)
    var refused := _cell(chooser, 1)
    assert_not_null(refused, "The computed brush has a cell, the first")
    if refused == null:
        chooser.free()
        return
    assert_null(refused.icon, "with no picture")
    assert_true(refused.text.begins_with(SaAbrChooser.UNREADABLE_MARK), "but the grid's mark, read '%s'" % refused.text)
    assert_true(refused.text.contains("a-computed-brush-and-a-picture-v1 1"), "and its name")
    assert_almost_eq(refused.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "dimmed, as the grid dims a refused cell")
    assert_true(refused.tooltip_text.contains("(unreadable)"), "Its tooltip says it is unreadable")
    assert_true(refused.tooltip_text.contains(sentence), "and carries the sentence, read '%s'" % refused.tooltip_text)

    refused.pressed.emit()
    assert_eq(_refused, [sentence], "A press says the sentence where refusals go")
    assert_true(_chosen.is_empty(), "and loads nothing")
    var picture := _cell(chooser, 2)
    assert_not_null(picture.icon, "The picture beside it is a cell with a picture")
    picture.pressed.emit()
    assert_eq(_chosen.size(), 1, "and a press on it loads it, the chooser still up after the refusal")
    chooser.free()


func test_a_collection_s_tips_are_cells_by_name() -> void:
    var chooser := _chooser(AbrWriter.V6_NAME)
    assert_eq(chooser.cells.get_child_count(), 3, "A cell per tip")
    var names: Array[String] = []
    for place in 3:
        var cell := _cell(chooser, place + 1)
        names.append(cell.text)
        assert_not_null(cell.icon, "%s has a picture" % cell.text)
        assert_eq(cell.modulate.a, 1.0, "%s is not dimmed" % cell.text)
        assert_eq(cell.get_theme_constant("icon_max_width"), SaAbrChooser.PICTURE, "and its picture is not capped smaller")
    assert_eq(names, ["Dry Disc", "Left Half", "Deep Ramp"], "named as the collection names them")
    var ramp := _cell(chooser, 3).icon.get_image()
    assert_eq(ramp.get_size(), Vector2i(SaAbrChooser.PICTURE, 53), "A 12 by 10 tip fits the square in its proportions")
    assert_eq(ramp.get_format(), Image.FORMAT_LA8, "white with the coverage as alpha, as the Tip Image grid draws it")
    var half := _cell(chooser, 2).icon.get_image()
    assert_eq(half.get_pixel(4, 32).a, 1.0, "The left half is covered")
    assert_eq(half.get_pixel(60, 32).a, 0.0, "and the right is not")
    assert_eq(half.get_pixel(4, 32).r, 1.0, "in white")
    chooser.free()


func test_the_tip_picked_is_a_png_that_loads_as_the_tip_did() -> void:
    var chooser := _chooser(AbrWriter.V6_NAME)
    var tip: SaTipImage.Tip = chooser.collection.tips[1]
    var written := chooser.pick(1)
    assert_eq(written, SaBrushTipMask.saved_dir().path_join("Left Half.png"), "Written into the saved tips folder by its name")
    assert_eq(_chosen, [written], "and handed on by that path")
    assert_true(_refused.is_empty(), "with nothing refused")
    var loaded := SaTipImage.load_from(written)
    assert_true(loaded.ok(), "The file loads as a .png, read '%s'" % loaded.error)
    assert_eq(loaded.size, tip.size, "at the tip's size")
    assert_eq(loaded.mask.size(), tip.mask.size(), "with a texel per texel")
    assert_eq(_differs(loaded, tip, 1e-6), -1, "every texel as the collection held it")
    assert_eq(loaded.tip_name, "Left Half", "under the name the collection gave it")
    assert_almost_eq(loaded.spacing, 0.15, 1e-6, "at the spacing the collection gave it")
    assert_false(loaded.colourful, "a grey mask")
    assert_true(SaBrushTipMask.available().has(written), "and the Tip Image grid lists it")
    chooser.free()


func test_a_tip_stored_at_16_bits_keeps_its_upper_byte() -> void:
    var chooser := _chooser(AbrWriter.V6_NAME)
    var tip: SaTipImage.Tip = chooser.collection.tips[2]
    var loaded := SaTipImage.load_from(chooser.pick(2))
    assert_eq(loaded.size, Vector2i(12, 10), "Deep Ramp loads at its size")
    assert_eq(_differs(loaded, tip, 1.0 / 510.0 + 1e-6), -1, "every texel within half a step of eight bits")
    assert_almost_eq(loaded.spacing, 0.5, 1e-6, "and its spacing")
    chooser.free()


func test_a_tip_picked_twice_is_one_file_and_a_name_taken_is_numbered() -> void:
    var chooser := _chooser(AbrWriter.V6_NAME)
    var first := chooser.pick(0)
    var again := SaAbrChooser.write(chooser.collection.tips[0], AbrWriter.V6_NAME, 1)
    assert_eq(again, first, "The same tip picked again is the file it was written as")
    var taken := SaBrushTipMask.save("Left Half.png", PackedByteArray([1, 2, 3]))
    assert_false(taken.is_empty(), "A file of another picture holds the name")
    var numbered := chooser.pick(1)
    assert_eq(numbered.get_file(), "Left Half 2.png", "so the tip takes the next number")
    assert_eq(FileAccess.get_file_as_bytes(taken), PackedByteArray([1, 2, 3]), "and the file there is left as it was")
    chooser.free()


## The `.abr` branch puts a window up over the main one, which a suite cannot,
## since it runs inside the root's own setting up of its children and a window
## shown from one maps a real one. The scenario of this row opens it in the
## running app, and here the other branch is read.
func test_load_tip_hands_any_other_file_on_as_it_is() -> void:
    var told: Array[String] = []
    var ahead := SaDialogsInHand.abr_ahead_of(told.append)
    ahead.call("/home/painter/tip.png")
    ahead.call("/home/painter/knife.gih")
    assert_eq(told, ["/home/painter/tip.png", "/home/painter/knife.gih"], "Any other file goes on as it is")
    assert_true(_refused.is_empty(), "with nothing said")


## Load Tip on an `.abr` asks the door, and the chooser the interface builds
## for it loads the tip picked. A stand-in builds the chooser and keeps it off
## the screen, the window the running app puts up being the scenario's.
func test_load_tip_on_an_abr_asks_the_door_and_the_chooser_loads_the_tip_picked() -> void:
    var opened: Array[SaAbrChooser] = []
    var builds := func(path: String, on_chosen: Callable) -> void:
        opened.append(SaAbrChooser.new(SaAbrCollection.load_from(path), on_chosen))
    SaDialogsInHand.attach(self, builds, Callable())
    var told: Array[String] = []
    SaDialogsInHand.abr_ahead_of(told.append).call(AbrWriter.FIXTURE_DIR.path_join(AbrWriter.V6_NAME))
    assert_eq(opened.size(), 1, "An .abr opens the chooser the interface attached")
    assert_true(told.is_empty(), "and loads nothing before a pick")
    if opened.is_empty():
        return
    var written := opened[0].pick(0)
    assert_eq(told, [written], "The tip picked reaches Load Tip by the path it was written to")
    assert_eq(written.get_file(), "Dry Disc.png", "the first tip by its name")
    opened[0].free()


func test_the_interface_attaches_the_chooser() -> void:
    var host := Node.new()
    SaDialogsInHand.detach(SaDialogsInHand._owner)
    SaPickers.attach(host)
    assert_true(SaDialogsInHand.is_attached(), "SaPickers attaches its answers to the door")
    assert_eq(SaDialogsInHand._owner, host, "owned by the host it was installed on")
    SaDialogsInHand.detach(host)
    host.free()


func test_a_host_with_no_chooser_says_so_in_the_corner() -> void:
    SaDialogsInHand.detach(SaDialogsInHand._owner)
    var told: Array[String] = []
    SaDialogsInHand.abr_ahead_of(told.append).call("/home/painter/dry media.abr")
    var said := "dry media.abr is a brush collection, and there is no window here to choose its tip in."
    assert_eq(_refused, [said], "Said in the corner")
    assert_true(told.is_empty(), "and nothing loads")


func test_a_collection_not_read_is_refused_and_opens_nothing() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var told: Array[String] = []
    SaDialogsInHand.attach(self, SaPickers.open_abr, Callable())
    SaDialogsInHand.abr_ahead_of(told.append).call(SaDataRoot.path("missing.abr"))
    assert_eq(_refused, ["missing.abr could not be read."], "The reader's sentence is said")
    assert_null(root.get_node_or_null("AbrChooser"), "and nothing opens")
    assert_true(told.is_empty(), "and nothing loads")
