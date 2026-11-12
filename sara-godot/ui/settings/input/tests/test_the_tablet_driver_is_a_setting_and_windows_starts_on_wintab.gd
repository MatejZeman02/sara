## The tablet driver as a setting: Windows starts on WinTab,
## and the Workspace row offers the drivers the engine names and switches both
## the live driver and the one the next launch asks for.
##
## The row's model is built from a stub list, because the suite runs headless
## on Linux where the engine names no Windows driver, and a recording callable
## stands in for `DisplayServer.tablet_set_current_driver`.
extends "res://tests/test_framework.gd"

var _saved: String
var _switched: PackedStringArray


func before_each() -> void:
    _saved = SaSettings.tablet_driver
    _switched = PackedStringArray()


func after_each() -> void:
    SaSettings.tablet_driver = _saved


func _record(driver_name: String) -> void:
    _switched.append(driver_name)


func _windows() -> SaTabletDriver:
    return SaTabletDriver.new(PackedStringArray(["wintab", "winink"]), "winink", _record)


## WinTab is the default tablet driver on Windows for now.
func test_windows_starts_on_wintab() -> void:
    assert_eq(
        String(ProjectSettings.get_setting("input_devices/pen_tablet/driver.windows")),
        "wintab",
        "project.godot starts Windows on WinTab"
    )


func test_the_row_offers_what_the_engine_names_and_selects_the_current_one() -> void:
    var driver := _windows()
    var ids: Array = []
    for entry: Dictionary in driver.choices():
        ids.append(String(entry["id"]))
    assert_eq(ids, ["wintab", "winink"], "every driver the engine names, in its order")
    assert_eq(String(driver.choices()[1]["label"]), "Windows Ink", "under the name a painter knows")
    assert_eq(driver.current, "winink", "the driver in use is the one selected")


func test_choosing_writes_the_setting_and_the_live_driver() -> void:
    var driver := _windows()
    assert_true(driver.choose("wintab"), "a driver the engine names is taken")
    assert_eq(SaSettings.tablet_driver, "wintab", "the next launch asks for it")
    assert_eq(_switched, PackedStringArray(["wintab"]), "and this one switches to it now")
    assert_eq(driver.current, "wintab", "and the row now shows it")


func test_a_driver_the_engine_does_not_name_is_refused() -> void:
    SaSettings.tablet_driver = ""
    var driver := _windows()
    assert_false(driver.choose("x11"), "refused")
    assert_eq(SaSettings.tablet_driver, "", "nothing written for the next launch")
    assert_eq(_switched.size(), 0, "and nothing switched now")


## A platform that names no driver still has the one it is using, so the row is
## never an empty dropdown.
func test_an_engine_naming_nothing_still_offers_the_current_driver() -> void:
    var driver := SaTabletDriver.new(PackedStringArray(), "default")
    assert_eq(driver.names, PackedStringArray(["default"]), "the current driver alone")
