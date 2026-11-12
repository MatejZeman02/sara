## The shipped Oil Smudge reaches a painter who already has
## the old one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A store can hold an Oil Smudge written before the dilution became Colour
## Rate, with the dilution off, so the migration kept the rate off and the Paint
## and Smudge slider read "0 %". A shipped preset is written once, so the
## corrected recipe must reach such a profile by another route.
##
## Each case starts from a copy of such an old file,
## `tests/fixtures/oil-smudge-before-colour-rate/oil_smudge_before_colour_rate.tres.txt`, in a scratch
## store and never the real one, then starts the bar over it the way the app
## does: the shipped presets installed, the bar ready, the preset loaded.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript := preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The bar and the machine need a RenderingDevice.
const REQUIRES_GPU := true

const KEY := &"paint_and_smudge"
const OLD_FILE := "res://tests/fixtures/oil-smudge-before-colour-rate/oil_smudge_before_colour_rate.tres.txt"
const NAME := "Oil Smudge"

static var scratch_dir: String = SaDataRoot.path("test_presets")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _clear()
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _clear()


func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


## The old file put into the scratch store as Oil Smudge, with *edit*
## applied to its text, and the path it went to.
func _put_old_file(edit: Callable = Callable()) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var text := FileAccess.get_file_as_string(OLD_FILE)
    if edit.is_valid():
        text = String(edit.call(text))
    var path := scratch_dir.path_join(NAME + ".tres")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()
    return path


## Sara started over the scratch store: the shipped presets installed, the bar
## ready, Oil Smudge loaded through it. Answers the slider's text.
func _start_and_read_the_slider() -> String:
    _host = Control.new()
    _host.name = "U348Host"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.install_shipped(_machine.get_tool(&"brush").get("settings"), ShippedPresetsScript)
    _bar._ready()
    assert_true(_bar.preset_box.load_preset(NAME), "Oil Smudge loads through the bar")
    # The bar syncs in the frame after a load, and this reads it now.
    _bar.after.settle_all()
    var slider := _bar.control_for(KEY) as FactorSlider
    assert_not_null(slider, "the bar builds Paint and Smudge")
    return slider._label.text if slider != null else ""


func _settings() -> SaStampBrushSettings:
    return _machine.get_tool(&"brush").get("settings") as SaStampBrushSettings


## The fingerprint the ledger reads the old file at is the one the recipe
## lists as shipped before, so the file is recognised as Sara's own.
func test_the_reference_file_is_a_version_sara_shipped() -> void:
    var listed: Array = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        if entry.get("name", "") == NAME:
            listed = entry.get("shipped_before", [])
    assert_true(listed.has(SaPresetLedger.fingerprint(OLD_FILE)), "the old Oil Smudge is listed as shipped before")


## An untouched old file is replaced at start, and the slider
## then reads the shipped rate, ticked, as a number.
func test_an_untouched_old_oil_smudge_becomes_the_shipped_one_at_start() -> void:
    var path := _put_old_file()
    var before := FileAccess.get_file_as_string(path)
    var text := _start_and_read_the_slider()
    assert_true(FileAccess.get_file_as_string(path) != before, "the old file is replaced")
    var settings := _settings()
    assert_true(settings.smudge_color_rate_option.enabled, "the Colour Rate is on")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 0.0001, "at the shipped half")
    assert_true(settings.smudge_length_option.enabled, "the length is on")
    assert_eq(text, "%s: 50 %%" % tr("Paint and Smudge"), "the slider reads the shipped rate")
    print("untouched old file, slider after start: %s" % text)


## A copy the painter edited is never touched, and its slider says "off" in
## words while its Colour Rate is off.
func test_an_edited_old_oil_smudge_is_left_as_it_is_and_its_slider_says_off() -> void:
    var path := _put_old_file(func(old: String) -> String: return old.replace("value = 0.6", "value = 0.55"))
    var before := FileAccess.get_file_as_string(path)
    var text := _start_and_read_the_slider()
    assert_eq(FileAccess.get_file_as_string(path), before, "the edited file is byte for byte as it was")
    assert_false(_settings().smudge_color_rate_option.enabled, "its Colour Rate stays off")
    assert_eq(text, "%s: %s" % [tr("Paint and Smudge"), tr("off")], "the slider says off rather than 0 %")
    print("edited old file, slider after start: %s" % text)


## A second start of the same build reads the record and writes nothing, so a
## preset the build already put in place is not written on every start.
func test_a_second_start_of_the_same_build_leaves_the_file_alone() -> void:
    var path := _put_old_file()
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_machine.get_tool(&"brush").get("settings"), ShippedPresetsScript)
    var after_first := FileAccess.get_file_as_string(path)
    assert_true(after_first != FileAccess.get_file_as_string(OLD_FILE), "the first start replaced it")
    var again := SaPresetStore.new()
    again.dir = scratch_dir
    assert_eq(again.install_shipped(_machine.get_tool(&"brush").get("settings"), ShippedPresetsScript), 0, "nothing is written")
    assert_eq(FileAccess.get_file_as_string(path), after_first, "the file is as the first start left it")
