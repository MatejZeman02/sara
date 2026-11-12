## The rounding of full precision colour at save is the
## painter's choice for each document. A full precision document of colours
## that 12 significant bits would move is saved as Ctrl+S saves it, as the
## working-file autosave saves it and as Save as JPEG XL saves it. With the
## choice off each reopens with every colour chunk's bytes as they were before
## the save, and with it on as the rounding gives them. With it off an
## export leaves the live colour as it lies and equals an export of the
## document saved and opened again. The choice comes back from the file, and a
## file that does not name it opens with it on.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Rounding = preload("res://core/sad-file/tests/test_a_full_precision_save_rounds_colour_to_12_significant_bits_once.gd")
const Kept = preload("res://core/sad-file/tests/test_half_precision_and_the_autosaves_keep_every_bit.gd")
const Live = preload("res://core/sad-snapshot/tests/test_an_export_rounds_the_live_colour_as_the_saved_file_holds_it.gd")
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

## The three saves the suite makes, by how the painter makes each.
const SAVES: Array[String] = ["Ctrl+S", "the working-file autosave", "Save as JPEG XL"]

static var saved: String = SaDataRoot.path("test_saved.sad")
static var working: String = SaDataRoot.path("test_working.sad")

## The codec registry a save asked when the case began, put back after.
var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null
var _autosave: SaAutosave = null


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _registries.register_builtins()
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    SaCodecRegistry.install(_was_installed)
    _was_installed = null
    _registries = null
    for path: String in [saved, saved + "1", working, working + "1", Live.saved, SaAutosave.recovery_path_for(working)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Registers the JPEG XL module into the suite's registries as the loader does,
## false when its library is not built here.
func _load_the_module() -> bool:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return SaCodecRegistry.shared().named(CODEC) != null


## Saves *doc* as *how* saves it and answers the file it wrote, empty when the
## save did not end well.
func _save(doc: SaDocument, how: String) -> String:
    match how:
        "Ctrl+S":
            return saved if Rounding.save_as_the_painter(doc, saved) else ""
        "Save as JPEG XL":
            SaSadFile.save_in_background(doc, saved, 0, null, true, Callable(), true, CODEC)
            return saved if SaSadFile.finish_saves() else ""
    doc.file_path = working
    if _autosave == null:
        _autosave = SaAutosave.new()
        _autosave.follow_settings = false
        _autosave.attach(doc)
    _autosave.write_working_file = true
    doc.modified = true
    if _autosave.save_now() != OK:
        return ""
    var save: SaSadSave = SaSadSave._saves.back() if not SaSadSave._saves.is_empty() else null
    assert_true(save != null and save.rounds, "The working-file autosave is a save that rounds")
    return working if SaSadFile.finish_saves() else ""


## Paints a full precision document, sets its choice to *on*, saves it each
## way and reads every colour chunk of each reopen against what *on* asks.
func _saves_follow_the_choice(on: bool) -> void:
    var jxl := _load_the_module()
    for how: String in SAVES:
        if how == "Save as JPEG XL" and not jxl:
            assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
            continue
        var doc := Kept.painted(SaColorSpace.Depth.F32)
        if not on:
            assert_true(SaSadSnapshot.choose_rounding(doc, false), "%s: the choice turns off" % how)
        var painted := Kept.colour_of(doc)
        var expected := painted
        if on:
            expected = {}
            for grid_pos: Variant in painted:
                var bytes: PackedByteArray = (painted[grid_pos] as PackedByteArray).duplicate()
                for at in range(0, bytes.size(), 4):
                    bytes.encode_u32(at, SaSadSnapshot.round_bits(bytes.decode_u32(at)))
                expected[grid_pos] = bytes
            assert_true(expected != painted, "%s: 12 bits move the painted colours" % how)
        var path := _save(doc, how)
        assert_false(path.is_empty(), "%s: the save ends" % how)
        var back := Rounding.reopened(path)
        assert_not_null(back, "%s: the file opens" % how)
        if back != null:
            var opened := Kept.colour_of(back)
            assert_eq(opened.size(), Rounding.POSITIONS.size(), "%s: every colour chunk comes back" % how)
            var word := "the bytes before the save" if not on else "the bytes the rounding gives"
            for grid_pos: Variant in expected:
                assert_true(opened.get(grid_pos) == expected[grid_pos], "%s: chunk %s reopens with %s" % [how, grid_pos, word])
            assert_eq(back.color_space.rounds_at_save, on, "%s: the choice comes back from the file" % how)
            back.free()
        if _autosave != null:
            _autosave.discard_recovery()
            _autosave.free()
            _autosave = null
        doc.free()
        for gone: String in [saved, saved + "1", working, working + "1"]:
            DirAccess.remove_absolute(ProjectSettings.globalize_path(gone))


func test_with_the_choice_off_every_save_keeps_every_bit() -> void:
    _saves_follow_the_choice(false)


func test_with_the_choice_on_every_save_rounds_as_does() -> void:
    _saves_follow_the_choice(true)


func test_a_file_that_does_not_name_the_choice_opens_with_it_on() -> void:
    var doc := Kept.painted(SaColorSpace.Depth.F32)
    assert_true(doc.color_space.rounds_at_save, "A new document rounds at save")
    assert_true(Rounding.save_as_the_painter(doc, saved), "The save ends")
    var space := SaTyped.strings(SaTyped.strings(_header(saved)).get("color_space", {}))
    assert_false(space.has("rounds_at_save"), "A file saved with the choice on names nothing, as a file saved before the row")
    var back := Rounding.reopened(saved)
    assert_true(back != null and back.color_space.rounds_at_save, "and opens with the choice on")
    if back != null:
        back.free()
    doc.free()


func test_the_choice_is_one_history_step_and_a_conversion_keeps_it() -> void:
    var doc := Kept.painted(SaColorSpace.Depth.F32)
    doc.modified = false
    assert_true(SaSadSnapshot.choose_rounding(doc, false), "The choice turns off")
    assert_false(doc.color_space.rounds_at_save, "and the document holds it")
    assert_true(doc.modified, "and the document is changed")
    assert_false(SaSadSnapshot.choose_rounding(doc, false), "Turning it off again changes nothing")
    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.display_p3()), "A conversion to Display P3 runs")
    assert_false(doc.color_space.rounds_at_save, "and keeps the choice")
    assert_eq(doc.undo_redo.get_current_action_name(), "Convert Colour Space", "The conversion is the last step")
    doc.undo_redo.undo()
    assert_false(doc.color_space.rounds_at_save, "Its undo keeps the choice")
    assert_eq(doc.undo_redo.get_current_action_name(), "Keep Every Bit at Save", "The choice is the step before it")
    doc.undo_redo.undo()
    assert_true(doc.color_space.rounds_at_save, "and its undo turns the rounding on again")
    doc.free()


func test_with_the_choice_off_an_export_leaves_the_live_colour_and_equals_one_of_the_reopened_file() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 256), null, SaColorSpace.srgb())
    _paint(easel.document)
    assert_true(SaSadSnapshot.choose_rounding(easel.document, false), "The choice turns off")
    var before := Kept.colour_of(easel.document)
    assert_true(Rounding.save_as_the_painter(easel.document, saved), "The save ends")
    var opened := SaEasel.create_default(Vector2i(512, 256), null, SaColorSpace.srgb())
    assert_eq(SaExport.load_sad(opened.document, saved, opened.compositor), OK, "The saved file opens in a second easel")
    var live := _exported(easel)
    assert_eq(Kept.colour_of(easel.document), before, "An export leaves the live colour's bytes as they were")
    var reopened := _exported(opened)
    assert_true(live != null and reopened != null, "Both export")
    if live != null and reopened != null:
        assert_true(live.get_data() == reopened.get_data(), "and the live export equals the reopened one")
    var on := SaEasel.create_default(Vector2i(512, 256), null, SaColorSpace.srgb())
    _paint(on.document)
    var painted := Kept.colour_of(on.document)
    _exported(on)
    assert_true(Kept.colour_of(on.document) != painted, "With the choice on, the export rounds the live colour, as the does")
    for made: SaEasel in [easel, opened, on]:
        made.free()


## Writes random colour from below zero to above one in every chunk of
## [constant Rounding.POSITIONS] of *doc*'s active layer, as the sibling suite does.
static func _paint(doc: SaDocument) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var rng := RandomNumberGenerator.new()
    rng.seed = 240
    for grid_pos in Rounding.POSITIONS:
        var colour := doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.ALBEDO)
        var bytes := PackedByteArray()
        bytes.resize(colour.size.x * colour.size.y * 16)
        for at in range(0, bytes.size(), 4):
            bytes.encode_float(at, rng.randf_range(-0.5, 1.5))
        rd.texture_update(colour.rid, 0, bytes)


## The picture an export of *easel* reads, after the export's own flush.
static func _exported(easel: SaEasel) -> Image:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    SaExport.flush_for_export(easel)
    return SaExport.get_texture_image_float(easel.output)


## The header of the `.sad` at *path*, as the v4 reader reads it.
static func _header(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    return SaTyped.strings(JSON.parse_string(text))
