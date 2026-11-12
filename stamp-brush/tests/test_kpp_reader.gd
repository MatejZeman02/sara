## The Krita preset reader: two fixtures, a bundle of them, a folder, and a
## pipe refused by name.
##
## **The fixtures are read twice.** Once as the bytes `kpp_fixtures.gd` writes
## on the spot, and once as the files committed under `fixtures/`, which a
## scenario imports through the running app. The two have to read to the same
## dictionary, so a change to the writer that leaves the committed files behind
## fails here rather than in a scenario three units later.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")

const FIXTURES_DIR := "res://modules/sara-base-modules/stamp-brush/tests/fixtures"
const ROUND_COMMITTED := FIXTURES_DIR + "/sara-round.kpp"
const PNG_COMMITTED := FIXTURES_DIR + "/sara-png-tip.kpp"
const BUNDLE_COMMITTED := FIXTURES_DIR + "/sara-fixtures.bundle"
const PIPE_COMMITTED := FIXTURES_DIR + "/sara-pipe.kpp"

static var scratch_folder: String = SaDataRoot.path("kpp_fixtures")
static var scratch_round_path := scratch_folder + "/round.kpp"
static var scratch_png_path := scratch_folder + "/png-tip.kpp"
static var scratch_pipe_path := scratch_folder + "/pipe.kpp"
static var scratch_bundle_path := scratch_folder + "/two.bundle"
static var scratch_not_a_preset := scratch_folder + "/picture.kpp"


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_folder))
    _write(scratch_round_path, Fixtures.round_kpp())
    _write(scratch_png_path, Fixtures.png_kpp())


func after_each() -> void:
    var folder := ProjectSettings.globalize_path(scratch_folder)
    for name: String in [scratch_round_path, scratch_png_path, scratch_pipe_path, scratch_bundle_path, scratch_not_a_preset]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(name))
    DirAccess.remove_absolute(folder)


func _write(path: String, bytes: PackedByteArray) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()


## The generated tip, read out of a `zTXt`.
func test_the_round_fixture_reads_to_its_dictionary() -> void:
    var preset := SaKppReader.read_file(scratch_round_path)

    assert_eq(preset["error"], "", "The round preset read")
    assert_eq(preset["name"], Fixtures.ROUND_NAME, "with the Preset element's name")
    assert_eq(preset["engine"], "paintbrush", "and its paintopid as the engine")
    assert_eq(preset["format_version"], "5.0", "and the version text chunk beside it")
    var options: Dictionary = preset["options"]
    assert_eq(options.size(), 14, "Every param is an option, the brush definition among them")
    assert_eq(options["OpacityValue"], {"type": "internal", "value": "1"}, "an internal scalar as the XML gives it")
    assert_eq(options["OpacitycommonCurve"]["value"], "0,0;0.5,0.75;1,1;", "a curve string unwrapped from its CDATA")
    assert_true(
        String(options["OpacitySensor"]["value"]).contains('<params id="pressure"/>'), "and a sensor's own XML kept as text"
    )
    var tip: Dictionary = preset["tip"]
    assert_eq(tip["kind"], SaKppReader.TIP_GENERATED, "The tip is generated")
    assert_eq(tip["generator"]["type"], "circle", "a circle")
    assert_eq(tip["generator"]["diameter"], "40", "of the diameter the MaskGenerator states")
    assert_eq(tip["brush"]["spacing"], "0.1", "with the Brush element's spacing beside it")
    assert_eq((tip["bytes"] as PackedByteArray).size(), 0, "and no bytes, since nothing was embedded")
    assert_eq((preset["tags"] as PackedStringArray).size(), 0, "A lone .kpp carries no tags, Krita keeps those in its database")
    assert_eq(preset["licence"], "", "and no licence, which is a bundle's to state")


## The second fixture: a PNG tip embedded base64, read out of a compressed
## `iTXt`, through the loader's from-bytes door.
func test_the_png_fixture_reads_its_tip_through_the_loader() -> void:
    var preset := SaKppReader.read_file(scratch_png_path)

    assert_eq(preset["error"], "", "The PNG tip preset read")
    assert_eq(preset["name"], Fixtures.PNG_NAME, "with a name Latin-1 cannot spell, which is why it was an iTXt")
    var tip: Dictionary = preset["tip"]
    assert_eq(tip["kind"], SaKppReader.TIP_IMAGE, "The tip is an image")
    assert_eq(tip["format"], "png", "a PNG")
    assert_eq(tip["file_name"], Fixtures.TIP_FILE, "named by the brush definition")
    assert_eq(tip["size"], Vector2i(4, 4), "at the size the loader decoded")
    assert_eq(tip["bytes"], Fixtures.tip_png(), "and the bytes are the embedded resource's, whole")
    assert_eq((preset["resources"] as Dictionary).size(), 2, "Both embedded resources are kept")
    assert_eq(preset["resources"][Fixtures.PATTERN_FILE.get_basename()]["type"], "patterns", "the pattern among them")

    var loaded := SaTipImage.load_bytes(tip["bytes"], tip["file_name"])
    assert_true(loaded.ok(), "The bytes load through the from-bytes door: %s" % loaded.error)
    assert_almost_eq(loaded.at(1, 1), 1.0, 1e-5, "black at the centre is full coverage")
    assert_almost_eq(loaded.at(0, 0), 0.0, 1e-5, "and white at the corner is none")
    assert_eq(loaded.tip_name, Fixtures.TIP_FILE.get_basename(), "and the tip is named after the file name it was handed")


## The from-bytes door refuses by the name it is handed, the way the from-path
## door refuses by the path, so a `.gih` inside a preset gets the same sentence.
func test_the_from_bytes_door_refuses_by_name() -> void:
    var pipe := SaTipImage.load_bytes(PackedByteArray([1, 2, 3]), "pipe.gih")
    assert_false(pipe.ok(), "A .gih is refused")
    assert_true(pipe.error.contains("pipe.gih") and pipe.error.contains("Load Tip"), "by name, with the reason: %s" % pipe.error)

    var gbr := SaTipImage.load_bytes(PackedByteArray([1, 2, 3]), "short.gbr")
    assert_false(gbr.ok(), "and three bytes named .gbr are refused as too short")
    assert_true(gbr.error.contains("short.gbr"), "naming the tip rather than a path: %s" % gbr.error)

    var png := SaTipImage.load_bytes(Fixtures.tip_png(), "tip.png")
    assert_true(png.ok(), "while real PNG bytes load: %s" % png.error)
    assert_eq(png.size, Vector2i(4, 4), "at their size")


## A GIMP pipe inside a preset reads as an image tip through the pipe reader,
## so the import writes it to the tips folder and selects it the way it selects
## a `.gbr`, its selection modes carried by the file itself.
func test_a_gih_tip_reads_as_a_pipe() -> void:
    _write(scratch_pipe_path, Fixtures.pipe_kpp())
    var preset := SaKppReader.read_file(scratch_pipe_path)

    assert_eq(preset["error"], "", "The preset itself read")
    assert_eq(preset["name"], Fixtures.PIPE_NAME, "with its name")
    var tip: Dictionary = preset["tip"]
    assert_eq(tip["kind"], SaKppReader.TIP_IMAGE, "and the pipe is an image tip")
    assert_eq(tip["format"], "gih", "of the .gih format")
    assert_eq(tip["file_name"], Fixtures.PIPE_FILE, "named by the brush definition")
    assert_eq(tip["size"], Vector2i(4, 4), "at its first cell's own size")

    var pipe := SaGihPipe.read_bytes(tip["bytes"], tip["file_name"])
    assert_true(pipe.ok(), "The bytes are a pipe the pipe reader reads: %s" % pipe.error)
    assert_eq(pipe.tips.size(), 4, "of four cells")
    assert_eq(pipe.selections, PackedStringArray(["incremental"]), "advancing incrementally")


## A pipe whose selection mode Sara's eight do not cover is refused, and the
## reader names the mode so the import can tag the preset with it rather than
## with the whole tip.
func test_a_gih_with_an_unknown_selection_is_refused_naming_the_mode() -> void:
    _write(scratch_pipe_path, Fixtures.pipe_unknown_kpp())
    var preset := SaKppReader.read_file(scratch_pipe_path)

    assert_eq(preset["error"], "", "The preset itself read")
    var tip: Dictionary = preset["tip"]
    assert_eq(tip["kind"], SaKppReader.TIP_REFUSED, "and the tip refused")
    assert_eq(tip["selection"], "sideways", "naming the mode Sara does not cover")


## A bundle of the two reads to both, with the manifest's tags and the
## licence `meta.xml` states.
func test_a_bundle_of_the_two_reads_to_both_with_tags_and_licence() -> void:
    assert_eq(
        Fixtures.bundle(Fixtures.round_kpp(), Fixtures.png_kpp(), ProjectSettings.globalize_path(scratch_bundle_path)),
        OK,
        "The bundle wrote"
    )
    var presets := SaKppReader.read_bundle(scratch_bundle_path)

    assert_eq(presets.size(), 2, "Two presets in the zip, two out")
    var round_preset: Dictionary = presets[1] if presets[0]["name"] == Fixtures.PNG_NAME else presets[0]
    var png: Dictionary = presets[0] if presets[0]["name"] == Fixtures.PNG_NAME else presets[1]
    assert_eq(round_preset["error"], "", "The round one read: %s" % round_preset["error"])
    assert_eq(png["error"], "", "and the PNG one: %s" % png["error"])
    assert_eq(
        round_preset["tags"], PackedStringArray(["Sara fixtures", "Round"]), "The manifest's tags come with the round preset"
    )
    assert_eq(png["tags"], PackedStringArray(["Sara fixtures", "Textured"]), "and the other's with the PNG one")
    assert_eq(round_preset["licence"], Fixtures.BUNDLE_LICENCE, "The licence is the bundle's, on every preset")
    assert_eq(png["bundle"]["author"], Fixtures.BUNDLE_AUTHOR, "with the author beside it")
    assert_eq(png["tip"]["kind"], SaKppReader.TIP_IMAGE, "and the embedded tip read inside the zip too")
    assert_true(String(round_preset["source"]).ends_with("paintoppresets/sara-round.kpp"), "Each names the entry it came from")


## A folder reads every `.kpp` and `.bundle` directly in it, in name order.
func test_a_folder_reads_every_preset_in_name_order() -> void:
    Fixtures.bundle(Fixtures.round_kpp(), Fixtures.png_kpp(), ProjectSettings.globalize_path(scratch_bundle_path))
    var presets := SaKppReader.read_path(scratch_folder)

    assert_eq(presets.size(), 4, "Two files and a bundle of two")
    assert_eq(presets[0]["name"], Fixtures.PNG_NAME, "png-tip.kpp first")
    assert_eq(presets[1]["name"], Fixtures.ROUND_NAME, "round.kpp second")
    assert_true(String(presets[2]["source"]).contains("two.bundle"), "and the bundle's two after, since t sorts after r")


## What is not a preset is refused with a sentence rather than an empty
## dictionary: a picture named `.kpp`, and a file of another kind.
func test_what_is_not_a_preset_is_refused_with_a_sentence() -> void:
    _write(scratch_not_a_preset, Fixtures.tip_png())
    var picture := SaKppReader.read_file(scratch_not_a_preset)
    assert_true(String(picture["error"]).contains("picture"), "A PNG with no preset chunk is a picture: %s" % picture["error"])

    var other := SaKppReader.read_path(scratch_folder + "/nothing.txt")
    assert_eq(other.size(), 1, "A path of another kind answers one dictionary")
    assert_true(String(other[0]["error"]).contains(".kpp"), "saying what is read instead: %s" % other[0]["error"])

    var missing := SaKppReader.read_file(scratch_folder + "/missing.kpp")
    assert_true(String(missing["error"]).contains("could not be read"), "and a missing file says so: %s" % missing["error"])


## The committed fixtures are the written ones. A scenario imports the files
## under `fixtures/`, and this is what keeps them the presets the writer
## describes.
func test_the_committed_fixtures_read_as_the_written_ones_do() -> void:
    var written_round := SaKppReader.read_file(scratch_round_path)
    var committed_round := SaKppReader.read_file(ROUND_COMMITTED)
    var written_png := SaKppReader.read_file(scratch_png_path)
    var committed_png := SaKppReader.read_file(PNG_COMMITTED)

    for key: String in ["name", "engine", "options", "tip", "format_version", "error"]:
        assert_eq(committed_round[key], written_round[key], "sara-round.kpp agrees on %s" % key)
        assert_eq(committed_png[key], written_png[key], "and sara-png-tip.kpp on %s" % key)

    var bundle := SaKppReader.read_bundle(BUNDLE_COMMITTED)
    assert_eq(bundle.size(), 2, "and the committed bundle holds the two")
    assert_eq(bundle[0]["licence"], Fixtures.BUNDLE_LICENCE, "under the licence the writer states")


## The committed pipe preset the scenario imports is the one the writer makes,
## which is what keeps a binary in the tree from drifting.
func test_the_committed_pipe_preset_is_the_written_one() -> void:
    _write(scratch_pipe_path, Fixtures.pipe_kpp())
    var written := SaKppReader.read_file(scratch_pipe_path)
    var committed := SaKppReader.read_file(PIPE_COMMITTED)
    for key: String in ["name", "engine", "options", "error"]:
        assert_eq(committed[key], written[key], "sara-pipe.kpp agrees on %s" % key)
    assert_eq(committed["tip"]["kind"], SaKppReader.TIP_IMAGE, "and the tip is a pipe")
    assert_eq(committed["tip"]["size"], Vector2i(4, 4), "at its first cell's size")
