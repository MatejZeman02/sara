## The display profile can be the monitor's own ICC file: a matrix monitor
## profile is read into the panel's primaries and white, and the display matrix
## it gives is the one the preset of the same primaries gives. A profile that
## holds no primaries, or a path with no file behind it, leaves the display on
## sRGB with the reason.
##
## The suite writes its profiles itself, so each byte is one it chose, and also
## reads `fixtures/display_p3_v4.icc`, written by a second writer outside Sara,
## which is what the Preferences scenario picks. The fixture was made for Sara
## from the published Display P3 primaries by a short numpy script and carries
## no third party's work, so it is under Sara's own GPLv3 like the rest of the
## tree.
extends "res://tests/test_framework.gd"

const FIXTURE := "res://core/api/color/tests/fixtures/display_p3_v4.icc"
const TOLERANCE := 1e-4

var _saved_profile: String = ""
var _saved_file: String = ""
var _written: Array[String] = []


func before_each() -> void:
    _saved_profile = SaSettings.display_profile
    _saved_file = SaSettings.display_profile_file


func after_each() -> void:
    SaSettings.display_profile = _saved_profile
    SaSettings.display_profile_file = _saved_file
    for path in _written:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _written.clear()


func test_a_version_4_profile_with_the_display_p3_primaries_gives_the_display_p3_matrix() -> void:
    var path := _write("p3_v4.icc", _profile_bytes(SaColorSpace.display_p3(), true, "A P3 panel"))
    var profile := SaIccProfile.read(path)
    assert_eq(profile.problem, "", "The profile is read")
    assert_eq(profile.name, "A P3 panel", "and its name is its desc tag's")
    assert_eq(profile.space.id, SaColorSpace.ID_CUSTOM, "It is a custom space")
    for fill: String in SaSettings.DISPLAY_FILLS:
        _assert_same_matrix(fill, profile.space, SaColorSpace.display_p3())


func test_the_profile_reaches_the_display_through_the_settings() -> void:
    var path := _write("p3_settings.icc", _profile_bytes(SaColorSpace.display_p3(), true, "A P3 panel"))
    SaSettings.display_profile_file = path
    SaSettings.display_profile = SaSettingsValues.DISPLAY_PROFILE_FILE
    assert_eq(SaSettings.display_profile, SaSettingsValues.DISPLAY_PROFILE_FILE, "The file is a display profile")
    _assert_same_matrix("correct", SaSettings.display_profile_space(), SaColorSpace.display_p3())


func test_the_committed_fixture_is_display_p3() -> void:
    var profile := SaIccProfile.read(FIXTURE)
    assert_eq(profile.problem, "", "The fixture is read")
    assert_eq(profile.name, "Display P3, a test profile", "and named")
    _assert_same_matrix("correct", profile.space, SaColorSpace.display_p3())


func test_a_version_2_profile_with_no_chad_is_adapted_from_its_white_point() -> void:
    var path := _write("p3_v2.icc", _profile_bytes(SaColorSpace.display_p3(), false, "Old P3"))
    var profile := SaIccProfile.read(path)
    assert_eq(profile.problem, "", "A version 2 profile is read")
    assert_eq(profile.name, "Old P3", "with its desc type name")
    _assert_same_matrix("correct", profile.space, SaColorSpace.display_p3())


func test_a_profile_with_only_an_a2b0_tag_leaves_the_display_on_srgb_and_says_why() -> void:
    var path := _write("lut.icc", _lut_bytes())
    var profile := SaIccProfile.read(path)
    assert_null(profile.space, "A lookup table profile is not read")
    assert_true(profile.problem.contains("lookup table"), "and says it is one: %s" % profile.problem)
    SaSettings.display_profile_file = path
    SaSettings.display_profile = SaSettingsValues.DISPLAY_PROFILE_FILE
    _assert_same_matrix("correct", SaSettings.display_profile_space(), SaColorSpace.srgb())


func test_a_path_with_no_file_leaves_the_display_on_srgb_and_says_why() -> void:
    SaSettings.display_profile_file = SaDataRoot.path("no_such_profile.icc")
    SaSettings.display_profile = SaSettingsValues.DISPLAY_PROFILE_FILE
    _assert_same_matrix("correct", SaSettings.display_profile_space(), SaColorSpace.srgb())
    var said := SaIccProfile.read(SaSettings.display_profile_file).problem
    assert_true(said.contains("is not there"), "The file is said to be missing: %s" % said)


func test_the_proof_gamut_does_not_take_the_monitor_s_file() -> void:
    SaSettings.proof_profile = SaSettingsValues.DISPLAY_PROFILE_FILE
    var said := "A proof's file is its own, never the monitor's"
    assert_true(SaSettings.proof_profile != SaSettingsValues.DISPLAY_PROFILE_FILE, said)


func test_a_file_that_is_not_a_profile_is_refused() -> void:
    var path := _write("text.icc", "not a profile at all, only words".to_utf8_buffer())
    assert_null(SaIccProfile.read(path).space, "Text is no profile")


func _assert_same_matrix(fill: String, read: SaColorSpace, preset: SaColorSpace) -> void:
    var got := SaDisplayFill.matrix(fill, SaColorSpace.srgb(), read)
    var want := SaDisplayFill.matrix(fill, SaColorSpace.srgb(), preset)
    var largest := 0.0
    for column in 3:
        for row in 3:
            largest = maxf(largest, absf(got[column][row] - want[column][row]))
    assert_true(largest <= TOLERANCE, "%s: every entry within 1e-4 of the preset's, the largest off by %s" % [fill, str(largest)])


func _write(file_name: String, bytes: PackedByteArray) -> String:
    var path := SaDataRoot.path("%s" % file_name)
    var out := FileAccess.open(path, FileAccess.WRITE)
    out.store_buffer(bytes)
    out.close()
    _written.append(path)
    return path


## A monitor profile of *space*: the colorants adapted from its white to D50 by
## Bradford, as a calibration writes them. Version 4 with `chad`, an `mluc`
## name and a D50 white point, or version 2 with a `desc` name, the panel's own
## white in `wtpt` and no `chad`.
func _profile_bytes(space: SaColorSpace, version_4: bool, profile_name: String) -> PackedByteArray:
    var pcs_white := _xy(SaIccProfile.PCS_WHITE)
    var chad := SaColorSpace.adaptation(space.white, pcs_white)
    var colorants := chad * space.rgb_to_xyz()
    var tags: Array = []
    tags.append(["desc", _mluc(profile_name) if version_4 else _desc(profile_name)])
    tags.append(["rXYZ", _xyz_tag(colorants.x)])
    tags.append(["gXYZ", _xyz_tag(colorants.y)])
    tags.append(["bXYZ", _xyz_tag(colorants.z)])
    if version_4:
        tags.append(["wtpt", _xyz_tag(SaIccProfile.PCS_WHITE)])
        var sf32 := "sf32".to_ascii_buffer()
        sf32.append_array(PackedByteArray([0, 0, 0, 0]))
        for row in 3:
            for column in 3:
                sf32.append_array(_s15(chad[column][row]))
        tags.append(["chad", sf32])
    else:
        tags.append(["wtpt", _xyz_tag(SaColorSpace.xy_to_xyz(space.white))])
    return _assemble(4 if version_4 else 2, tags)


## A profile with an `A2B0` tag and no colorants, as a lookup table profile is.
func _lut_bytes() -> PackedByteArray:
    var a2b0 := "mAB ".to_ascii_buffer()
    a2b0.resize(32)
    return _assemble(4, [["desc", _mluc("A LUT panel")], ["A2B0", a2b0], ["wtpt", _xyz_tag(SaIccProfile.PCS_WHITE)]])


func _assemble(version: int, tags: Array) -> PackedByteArray:
    var table := PackedByteArray()
    var body := PackedByteArray()
    var start := SaIccProfile.HEADER_SIZE + 4 + 12 * tags.size()
    for tag: Array in tags:
        var data: PackedByteArray = tag[1]
        while data.size() % 4 != 0:
            data.append(0)
        table.append_array(String(tag[0]).to_ascii_buffer())
        table.append_array(_u32(start + body.size()))
        table.append_array(_u32(data.size()))
        body.append_array(data)
    var header := PackedByteArray()
    header.resize(SaIccProfile.HEADER_SIZE)
    header.encode_u8(8, version)
    for i in 4:
        header[12 + i] = "mntr".unicode_at(i)
        header[16 + i] = "RGB ".unicode_at(i)
        header[20 + i] = "XYZ ".unicode_at(i)
        header[36 + i] = "acsp".unicode_at(i)
    var out := header
    out.append_array(_u32(tags.size()))
    out.append_array(table)
    out.append_array(body)
    var total := _u32(out.size())
    for i in 4:
        out[i] = total[i]
    return out


func _mluc(text: String) -> PackedByteArray:
    var units := PackedByteArray()
    for character in text:
        var code := character.unicode_at(0)
        units.append(code >> 8)
        units.append(code & 0xFF)
    var out := "mluc".to_ascii_buffer()
    out.append_array(PackedByteArray([0, 0, 0, 0]))
    out.append_array(_u32(1))
    out.append_array(_u32(12))
    out.append_array("enUS".to_ascii_buffer())
    out.append_array(_u32(units.size()))
    out.append_array(_u32(28))
    out.append_array(units)
    return out


func _desc(text: String) -> PackedByteArray:
    var out := "desc".to_ascii_buffer()
    out.append_array(PackedByteArray([0, 0, 0, 0]))
    out.append_array(_u32(text.length() + 1))
    out.append_array(text.to_ascii_buffer())
    out.append(0)
    # The Unicode and ScriptCode parts a version 2 description carries after
    # its ASCII, empty.
    out.resize(out.size() + 4 + 4 + 2 + 1 + 67)
    return out


func _xyz_tag(value: Vector3) -> PackedByteArray:
    var out := "XYZ ".to_ascii_buffer()
    out.append_array(PackedByteArray([0, 0, 0, 0]))
    out.append_array(_s15(value.x))
    out.append_array(_s15(value.y))
    out.append_array(_s15(value.z))
    return out


func _s15(value: float) -> PackedByteArray:
    var raw := int(roundf(value * 65536.0))
    if raw < 0:
        raw += 0x100000000
    return _u32(raw)


func _u32(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


func _xy(xyz: Vector3) -> Vector2:
    var total := xyz.x + xyz.y + xyz.z
    return Vector2(xyz.x / total, xyz.y / total)
