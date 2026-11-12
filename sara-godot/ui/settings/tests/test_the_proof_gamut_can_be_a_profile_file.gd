## The proof gamut can be a profile file: the matrix ICC profile of the device
## a painting is made for becomes the gamut Soft Proof and the Minimap clip to,
## from a path of its own beside the monitor's. A file written over is read
## again, and a file the reader refuses leaves the proof on sRGB with the
## reason on the Display page's row.
##
## The profiles the suite writes are the bytes of `assets/icc/`, which
## `scripts/gen_icc_profiles.py` makes from the primaries and white
## `SaColorSpace` declares, so a Display P3 file holds Display P3's own numbers.
extends "res://tests/test_framework.gd"

const P3_PROFILE := "res://assets/icc/display_p3.icc"
const REC2020_PROFILE := "res://assets/icc/rec2020.icc"
const TOLERANCE := 1e-4

var _saved_profile: String = ""
var _saved_file: String = ""
## A path of each case's own, because the reading is kept by path and modified
## time to the second and two cases run within one.
var _path: String = ""
var _cases: int = 0


func before_each() -> void:
    _cases += 1
    _path = SaDataRoot.path("proof_profile_%d.icc" % _cases)
    _saved_profile = SaSettings.proof_profile
    _saved_file = SaSettings.proof_profile_file


func after_each() -> void:
    SaSettings.proof_profile = _saved_profile
    SaSettings.proof_profile_file = _saved_file
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_a_display_p3_file_proofs_as_display_p3() -> void:
    _write(FileAccess.get_file_as_bytes(P3_PROFILE))
    SaSettings.proof_profile_file = _path
    SaSettings.proof_profile = SaSettingsValues.PROOF_PROFILE_FILE
    assert_eq(SaSettings.proof_profile, SaSettingsValues.PROOF_PROFILE_FILE, "The file is a proof gamut")
    assert_eq(SaSettings.proof_profile_file, _path, "kept in a path of its own")
    _assert_same_gamut(SaSettings.proof_profile_space(), SaColorSpace.display_p3(), "the P3 file")


## The cache is keyed by the path and the file's modified time, which the
## file system keeps to the second, so the second write waits past one.
func test_a_file_written_over_is_read_again() -> void:
    _write(FileAccess.get_file_as_bytes(P3_PROFILE))
    SaSettings.proof_profile_file = _path
    SaSettings.proof_profile = SaSettingsValues.PROOF_PROFILE_FILE
    _assert_same_gamut(SaSettings.proof_profile_space(), SaColorSpace.display_p3(), "the first write")
    OS.delay_msec(1100)
    _write(FileAccess.get_file_as_bytes(REC2020_PROFILE))
    _assert_same_gamut(SaSettings.proof_profile_space(), SaColorSpace.rec2020(), "the file written over")


func test_a_refused_file_proofs_as_srgb_and_the_display_page_says_why() -> void:
    _write("not a profile at all, only words".to_utf8_buffer())
    SaSettings.proof_profile_file = _path
    SaSettings.proof_profile = SaSettingsValues.PROOF_PROFILE_FILE
    _assert_same_gamut(SaSettings.proof_profile_space(), SaColorSpace.srgb(), "a refused file")
    var problem := SaIccProfile.read(_path).problem
    assert_false(problem.is_empty(), "The reader says why it refused the file")
    var window := SaSettingsWindow.new()
    assert_true(window.show_page("Canvas and colour"), "Canvas and colour opens")
    var said := window.content_container.find_child(SaProofProfileRows.NAME_LABEL, true, false) as Label
    assert_not_null(said, "The page carries the proof's file row")
    if said != null:
        assert_true(said.text.contains(problem), "and the row says why: %s" % said.text)
    window.free()


func test_the_monitor_s_file_is_not_the_proof_s() -> void:
    _write(FileAccess.get_file_as_bytes(REC2020_PROFILE))
    SaSettings.proof_profile_file = _path
    SaSettings.proof_profile = SaSettingsValues.DISPLAY_PROFILE_FILE
    assert_true(SaSettings.proof_profile != SaSettingsValues.DISPLAY_PROFILE_FILE, "The monitor's choice is not a proof's")


func _write(bytes: PackedByteArray) -> void:
    var out := FileAccess.open(_path, FileAccess.WRITE)
    out.store_buffer(bytes)
    out.close()


func _assert_same_gamut(got: SaColorSpace, want: SaColorSpace, label: String) -> void:
    assert_not_null(got, "%s: a space" % label)
    if got == null:
        return
    var largest := got.white.distance_to(want.white)
    for i in 3:
        largest = maxf(largest, got.primaries[i].distance_to(want.primaries[i]))
    assert_true(largest <= TOLERANCE, "%s: primaries and white within 1e-4, the largest off by %s" % [label, str(largest)])
