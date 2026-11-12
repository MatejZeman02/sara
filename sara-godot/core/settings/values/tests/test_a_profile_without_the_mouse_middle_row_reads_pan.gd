## The mouse's wheel press is stored beside the pen's buttons and a profile
## written before it existed reads it as Pan.
##
## The profile is read through a file object and a values node of the suite's
## own, as the brush slots' suite does, so nothing the running application
## listens to hears the painter's buttons change under it.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_d11_mouse_middle.cfg")

## The pen's table as it was left before the row existed: the middle
## button bound to Eraser while held, and a right button bound to Pan.
const PENS := {"extra1": "nothing", "extra2": "nothing", "middle": "eraser", "right": "pan"}


func before_each() -> void:
    _clear()


func after_each() -> void:
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


## A profile of this version holding the pen's table and, when *mouse* is not
## empty, the mouse's row.
func _write_profile(mouse: String) -> SaSettingsFile:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    config.set_value("input", "pen_buttons", PENS)
    if mouse != "":
        config.set_value("input", "mouse_middle", mouse)
    config.save(ProjectSettings.globalize_path(scratch_path))
    var file := SaSettingsFile.new()
    file.settings_path = ProjectSettings.globalize_path(scratch_path)
    return file


func _loaded(file: SaSettingsFile) -> SaSettingsValues:
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    return values


func test_a_profile_without_the_key_reads_the_mouse_row_as_pan_and_the_pen_s_unchanged() -> void:
    var file := _write_profile("")
    var values := _loaded(file)
    assert_eq(values.mouse_middle, SaSettingsPenButtons.PAN, "The mouse's row reads Pan")
    assert_eq(values.pen_buttons["middle"], SaSettingsPenButtons.ERASER, "and the pen's Middle row is still Eraser")
    assert_eq(values.pen_buttons, SaSettingsPenButtons.bound(PENS), "with the whole table as it was stored")
    assert_eq(SaSettingsKeys.place_of(&"mouse_middle"), ["input", "mouse_middle"], "The row is stored beside pen_buttons")
    values.free()


func test_a_stored_choice_comes_back() -> void:
    var values := _loaded(_write_profile(SaSettingsPenButtons.EYEDROPPER))
    assert_eq(values.mouse_middle, SaSettingsPenButtons.EYEDROPPER, "The mouse's row reads what was stored")
    assert_eq(values.pen_buttons["middle"], SaSettingsPenButtons.ERASER, "beside the pen's, which the mouse's never moves")
    values.free()


func test_a_word_no_row_offers_is_pan() -> void:
    var values := _loaded(_write_profile("juggle"))
    assert_eq(values.mouse_middle, SaSettingsPenButtons.PAN, "A hand-edited action nothing knows is Pan")
    values.mouse_middle = SaSettingsPenButtons.NOTHING
    assert_eq(values.mouse_middle, SaSettingsPenButtons.NOTHING, "and every listed action is accepted, Nothing included")
    values.mouse_middle = "pan or juggle"
    assert_eq(values.mouse_middle, SaSettingsPenButtons.PAN, "A string that merely contains one is no action")
    values.free()
