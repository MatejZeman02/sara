## A cached preset picture that cannot be read is drawn again, with no error
## line, at the next look.
##
## An emulator's smoke run stops the emulator a minute after the start, and the
## pictures the first start wrote in its last seconds were left on the disk image
## as files of nothing. The start after it read them as fresh, since a file of
## nothing is still newer than its preset, and printed `Error loading image`
## eight times, once for each of the last eight presets by name.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A picture is a stroke drawn through the real paint path.
const REQUIRES_GPU := true

## How many shares of a frame the chooser is given to draw every picture.
const SHARES: int = 2000

static var scratch_dir: String = SaDataRoot.path("test_unreadable_thumbs")

var _errors: SaErrorCatcher = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _errors = SaErrorCatcher.new()
    OS.add_logger(_errors)


func after_each() -> void:
    OS.remove_logger(_errors)
    _errors = null
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    return store


## A chooser over *store*, given shares of a frame until every cell shows its
## picture, and its report then.
func _chooser_drawn(store: SaPresetStore) -> Dictionary:
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    var count := store.list_names().size()
    var shares := 0
    while shares < SHARES and int(chooser.cells.report()["drawn"]) < count:
        chooser.cells.build(SaBrushPresetCells.SLICE_USEC)
        shares += 1
    var report := chooser.cells.report()
    chooser.free()
    return report


## Leaves the picture at *png* as a cut-short write leaves it: nothing at all when
## *keep* is 0, and its first *keep* bytes otherwise.
func _cut(png: String, keep: int) -> void:
    var bytes := FileAccess.get_file_as_bytes(png)
    var file := FileAccess.open(png, FileAccess.WRITE)
    file.store_buffer(bytes.slice(0, keep))
    file.close()


## A picture left as a file of nothing, newer than its preset, is stale, and the
## next `ensure` draws it again into a picture that loads with no error.
func test_a_picture_left_empty_is_drawn_again_by_the_next_look() -> void:
    var store := _store()
    var preset_name := store.list_names()[0]
    var settings := store.load_preset(preset_name)
    var png := SaPresetThumbs.ensure(scratch_dir, preset_name, StateBrushScript, settings)
    assert_false(png.is_empty(), "'%s' has a picture to begin with" % preset_name)
    _cut(png, 0)
    assert_true(SaPresetThumbs.is_stale(scratch_dir, preset_name), "A picture of nothing is stale")
    var renders := SaPresetThumbs.renders
    var again := SaPresetThumbs.ensure(scratch_dir, preset_name, StateBrushScript, settings)
    assert_eq(again, png, "The next look keeps the picture where it was")
    assert_true(SaPresetThumbs.renders > renders, "and draws it again rather than handing back the empty file")
    var image := Image.load_from_file(again)
    assert_not_null(image, "The picture drawn again loads")
    assert_eq(_errors.texts([SaErrorCatcher.ERROR]), PackedStringArray(), "with no error line")


## A picture cut short anywhere is stale, because a PNG without its `IEND` chunk
## fails to load as surely as an empty one.
func test_a_picture_cut_short_is_stale_and_a_whole_one_is_not() -> void:
    var store := _store()
    var preset_name := store.list_names()[0]
    var png := SaPresetThumbs.ensure(scratch_dir, preset_name, StateBrushScript, store.load_preset(preset_name))
    assert_false(SaPresetThumbs.is_stale(scratch_dir, preset_name), "A whole picture is not stale")
    var length := FileAccess.get_file_as_bytes(png).size()
    _cut(png, length >> 1)
    assert_true(SaPresetThumbs.is_stale(scratch_dir, preset_name), "Half a picture is stale")
    _cut(png, 8)
    assert_true(SaPresetThumbs.is_stale(scratch_dir, preset_name), "and so is its signature alone")
    assert_eq(_errors.texts([SaErrorCatcher.ERROR]), PackedStringArray(), "and asking prints no error line")


## The emulator's case whole: a chooser over the shipped presets draws them, the
## last pictures are left as nothing, and the next chooser shows every cell's
## picture with no `Error loading image` line.
func test_the_next_chooser_shows_every_picture_after_the_last_were_left_empty() -> void:
    var store := _store()
    var names := store.list_names()
    var first := _chooser_drawn(store)
    assert_eq(int(first["drawn"]), names.size(), "The first chooser draws every picture: %s" % str(first))
    # The picture the chooser cached, which is the tip's beside the stroke's
    # when the profile shows tips, so the file emptied is the one it reads.
    var one_dab := SaSettings.preset_thumb_tip
    var emptied: Array[String] = []
    for preset_name: String in names.slice(maxi(0, names.size() - 2)):
        _cut(SaPresetThumbs.path_for(scratch_dir, preset_name, one_dab), 0)
        emptied.append(preset_name)
    _errors.stop()
    _errors = SaErrorCatcher.listening()
    var next := _chooser_drawn(store)
    var said := "The next chooser shows every picture, %s among them: %s" % [str(emptied), str(next)]
    assert_eq(int(next["drawn"]), names.size(), said)
    assert_eq(_errors.texts([SaErrorCatcher.ERROR]), PackedStringArray(), "with no error line")
    for preset_name: String in emptied:
        var again := Image.load_from_file(SaPresetThumbs.path_for(scratch_dir, preset_name, one_dab))
        assert_not_null(again, "'%s' is a picture again" % preset_name)
