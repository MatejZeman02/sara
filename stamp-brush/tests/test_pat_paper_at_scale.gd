## A GIMP `.pat` paper on a brush whose texture scale is not one, which is the
## shape every Krita import with a paper has. The dab asks the
## pattern for its mask rather than reading the file through the picture
## importer, which does not know the format and would pay a failed read and a
## log line on every dab. A paper that cannot be made is refused once rather
## than once per dab.
extends "res://tests/test_framework.gd"

const PatternTests = preload("res://modules/sara-base-modules/stamp-brush/tests/test_pattern.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## A pattern is a texture.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_pat_paper_at_scale")
const SIDE := 16

var _refusals: int = 0


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


func _write(file_name: String, bytes: PackedByteArray) -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var file := FileAccess.open(scratch_dir.path_join(file_name), FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()


func _paper() -> PackedByteArray:
    var texels := PackedByteArray()
    texels.resize(SIDE * SIDE)
    texels.fill(200)
    return PatternTests._pat_bytes(SIDE, SIDE, 1, "Rough", texels)


func _settings(pattern_name: String, scale: float) -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = pattern_name
    settings.texture_scale = scale
    return settings


func _count(_line: String, _kind: int) -> void:
    _refusals += 1


func test_a_pat_paper_binds_at_a_scale_other_than_one() -> void:
    _write("rough.pat", _paper())
    var dab := SaDabPattern.new(SaPatternStore.new([scratch_dir]))
    var bound := dab.texture(_settings("Rough", 2.0))
    assert_true(bound != null, "A scaled .pat paper binds: %s" % dab.error)
    assert_eq(dab.error, "", "and nothing is wrong with it")
    assert_eq(dab.builds, 1, "made once")
    dab.texture(_settings("Rough", 2.0))
    assert_eq(dab.builds, 1, "and answered from the last ask after that")


func test_a_paper_that_cannot_be_read_is_refused_once() -> void:
    _write("torn.png", "not a picture at all".to_utf8_buffer())
    SaProblems.announce = false
    SaProblems.attach_sink(_count)
    _refusals = 0
    var dab := SaDabPattern.new(SaPatternStore.new([scratch_dir]))
    assert_true(dab.texture(_settings("Torn", 1.0)) == null, "A torn picture binds nothing")
    assert_false(dab.error.is_empty(), "and says why")
    var first := _refusals
    assert_true(first >= 1, "The first dab reports the read")
    dab.texture(_settings("Torn", 1.0))
    dab.texture(_settings("Torn", 1.0))
    assert_eq(_refusals, first, "and the dabs after it read nothing and report nothing")
