## Every cause a real pipe tip was refused for, as a fixture
## preset, and each either paints its pipe or wears "pipe tip:" and the cause.
##
## The causes are the ones the pipes of Krita's own default bundles hit, read
## through `SaKppReader`: a placement Krita wrote as `(null)`, a
## one-dimensional pipe whose rank disagrees with its count of tips, a file
## that stops before its last tip, and a preset that names a pipe it does not
## embed. The first two now carry, the last two are told. The fixtures are
## Sara's own pipes carrying the parameter lines those files carry, since the
## files are Krita's and a fixture is committed.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

static var scratch_preset_dir: String = SaDataRoot.path("test_k1_pipe_presets")
static var scratch_dir: String = SaDataRoot.path("test_k1_pipe")

## The parameter line of Krita's `snow.gih`, cut to four cells, which says
## `placement:(null)` as sixteen of the Krita 4 default bundle's pipes do.
const NULL_LINE := "4 ncells:4 cellwidth:4 cellheight:4 step:0 dim:1 cols:1 rows:1 placement:(null) rank0:4 sel0:random"

## The same in capitals, which is how the Krita 3 bundle's five write it.
const NULL_UPPER_LINE := "4 ncells:4 cellwidth:4 cellheight:4 step:100 dim:1 placement:(NULL) rank0:4 sel0:incremental"

## `A_bamboo-leaves.gih`'s line: three tips and a rank of five.
const RANK_LINE := "3 ncells:3 cellwidth:4 cellheight:4 step:100 dim:1 cols:1 rows:1 placement:constant rank0:5 sel0:random"

## `fairy-dust.gih`'s line. The file in Krita's bundle promises four tips and
## holds one.
const SHORT_LINE := "4 ncells:4 cellwidth:4 cellheight:4 step:100 dim:1 cols:1 rows:1 placement:constant rank0:4 sel0:random"

const WRITTEN_TIPS := ["k1-null.gih", "k1-null-upper.gih", "k1-rank.gih", "k1-short.gih", "k1-missing.gih"]


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
    for file_name: String in WRITTEN_TIPS:
        var written := SaBrushTipMask.saved_dir().path_join(file_name)
        if FileAccess.file_exists(written):
            DirAccess.remove_absolute(written)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _import(store: SaPresetStore, preset_name: String, file_name: String, gih: PackedByteArray, embedded: bool) -> Dictionary:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name.get_basename() + ".kpp")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(KppFixtures.gih_kpp(preset_name, file_name, gih, embedded))
    file.close()
    var results := SaKppImport.import_path(path, store)
    assert_eq(results.size(), 1, "%s is one preset" % preset_name)
    return results[0] if not results.is_empty() else {}


func _assert_paints_its_pipe(store: SaPresetStore, result: Dictionary, preset_name: String, file_name: String) -> void:
    assert_eq(result.get("error", "missing"), "", "%s imports" % preset_name)
    assert_eq(result.get("not_carried", ["missing"]), [], "%s carries its pipe with no tag" % preset_name)
    var loaded := store.load_preset(preset_name)
    assert_not_null(loaded, "the store holds %s" % preset_name)
    if loaded == null:
        return
    var settings := SettingsScript.new()
    SaPresetStore.copy_settings(loaded, settings)
    assert_eq(settings.tip.kind, SaBrushTipScript.Kind.IMAGE, "%s has an image tip" % preset_name)
    assert_eq(settings.tip.image_path, SaBrushTipMask.saved_dir().path_join(file_name), "written to the tips folder")
    var mask := SaBrushTipMask.load_image(settings.tip.image_path)
    assert_true(mask.error.is_empty(), "%s loads as a pipe: %s" % [preset_name, mask.error])
    assert_true(mask.has_pipe(), "%s has cells to advance between" % preset_name)


func _assert_tagged_with(store: SaPresetStore, result: Dictionary, preset_name: String, cause: String) -> void:
    assert_eq(result.get("error", "missing"), "", "%s imports" % preset_name)
    var not_carried: Array = result.get("not_carried", [])
    assert_eq(not_carried.size(), 1, "%s wears one phrase: %s" % [preset_name, not_carried])
    var phrase := String(not_carried[0]) if not not_carried.is_empty() else ""
    assert_true(phrase.begins_with("pipe tip: "), "which says it is the pipe tip and why: %s" % phrase)
    assert_true(phrase.contains(cause), "naming the cause, %s: %s" % [cause, phrase])
    assert_true(Array(store.tags_for(preset_name)).has("not carried: " + phrase), "as a tag the docker filters by")


func test_a_placement_krita_wrote_as_null_paints_its_pipe() -> void:
    var store := _store()
    var lower := _import(store, "K1 null", "k1-null.gih", KppFixtures.gih_with(NULL_LINE, 4, 4), true)
    _assert_paints_its_pipe(store, lower, "K1 null", "k1-null.gih")
    var upper := _import(store, "K1 null upper", "k1-null-upper.gih", KppFixtures.gih_with(NULL_UPPER_LINE, 4, 4), true)
    _assert_paints_its_pipe(store, upper, "K1 null upper", "k1-null-upper.gih")
    var pipe := SaGihPipe.read_bytes(KppFixtures.gih_with(NULL_LINE, 4, 4), "k1-null.gih")
    assert_eq(pipe.placement, SaGihPipe.PLACEMENT_WHEN_UNSTATED, "and the null reads as a file that stated none")
    assert_eq(pipe.parameters["placement"], "(null)", "while the parameter keeps what the file wrote")


func test_a_one_dimension_rank_that_disagrees_with_the_count_paints_every_tip() -> void:
    var store := _store()
    var result := _import(store, "K1 rank", "k1-rank.gih", KppFixtures.gih_with(RANK_LINE, 3, 3), true)
    _assert_paints_its_pipe(store, result, "K1 rank", "k1-rank.gih")
    var pipe := SaGihPipe.read_bytes(KppFixtures.gih_with(RANK_LINE, 3, 3), "k1-rank.gih")
    assert_eq(pipe.ranks, PackedInt32Array([3]), "the rank takes the tips the file holds")
    assert_eq(pipe.parameters["rank0"], "5", "and the parameter keeps what it said")
    var line := "3 ncells:3 dim:2 rank0:5 rank1:1 sel0:random"
    var two := SaGihPipe.read_bytes(KppFixtures.gih_with(line, 3, 3), "k1-rank-two.gih")
    assert_true(two.error.contains("multiply"), "while two dimensions that disagree stay refused: %s" % two.error)


func test_a_pipe_that_stops_before_its_last_tip_says_where() -> void:
    var store := _store()
    var result := _import(store, "K1 short", "k1-short.gih", KppFixtures.gih_with(SHORT_LINE, 4, 1), true)
    _assert_tagged_with(store, result, "K1 short", "stops in tip 2 of 4")


func test_a_pipe_the_preset_does_not_embed_says_it_is_missing() -> void:
    var store := _store()
    var result := _import(store, "K1 missing", "k1-missing.gih", KppFixtures.gih_with(NULL_LINE, 4, 4), false)
    _assert_tagged_with(store, result, "K1 missing", "does not embed it")
    var phrase := String(result.get("not_carried", [""])[0])
    assert_false(phrase.contains("collection"), "and does not blame the format: %s" % phrase)


func test_no_cause_leaves_the_bare_phrase() -> void:
    var store := _store()
    var imports := [
        _import(store, "K1 null", "k1-null.gih", KppFixtures.gih_with(NULL_LINE, 4, 4), true),
        _import(store, "K1 rank", "k1-rank.gih", KppFixtures.gih_with(RANK_LINE, 3, 3), true),
        _import(store, "K1 short", "k1-short.gih", KppFixtures.gih_with(SHORT_LINE, 4, 1), true),
        _import(store, "K1 missing", "k1-missing.gih", KppFixtures.gih_with(NULL_LINE, 4, 4), false),
    ]
    for result: Dictionary in imports:
        assert_false(Array(result.get("not_carried", [])).has("pipe tip"), "no preset wears the bare phrase: %s" % result)
