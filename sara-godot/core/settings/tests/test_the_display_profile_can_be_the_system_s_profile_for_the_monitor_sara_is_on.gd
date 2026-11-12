## The display profile can be the system's profile for the monitor Sara is on.
##
## A calibrated monitor already has its profile installed in the system, and the
## Display profile's fifth choice, The system's profile, takes it from there:
## colord on Linux, `GetICMProfile` on Windows, read by `SaIccProfile`. The
## system is a stand-in here, a callable handed to `SaSystemProfile`, so the
## suite is the same on every machine. The space follows the window to another
## screen, a system that names no profile or one Sara cannot read leaves the
## display on sRGB with the reason, and the choice is the default on Linux and
## Windows, where a painter who chose another keeps it.
##
## The Display page's row naming the profile found is the record of
## `scenarios/the-display-profile-can-be-the-system-s-profile-for-the-monitor-sara-is-on.json`.
extends "res://tests/test_framework.gd"

## A Display P3 profile, version 4, and the Rec. 2020 profile Sara ships.
const P3_PROFILE := "res://core/api/color/tests/fixtures/display_p3_v4.icc"
const REC2020_PROFILE := "res://assets/icc/rec2020.icc"

## A painter's laptop as colord and `xrandr` answered on a slower machine, the profile
## the one GNOME made from the Dell U2412M's EDID.
const DELL_COLORMGR := """Object Path:   /org/freedesktop/ColorManager/devices/xrandr_Dell_Inc__DELL_U2412M
Owner:         painter
Type:          display
Enabled:       Yes
Embedded:      No
Model:         DELL U2412M
Vendor:        Dell
Serial:        XXXXXXXXXXXX
Scope:         temp
Colorspace:    rgb
Device ID:     xrandr-Dell Inc.-DELL U2412M-XXXXXXXXXXXX
Profile 1:     icc-a1fe8cbd301762f23bf2ecc4a62d194d
               /home/painter/.local/share/icc/edid-af0ddc1ce6b332fbeab1ff861ca658c2.icc
Metadata:      OutputEdidMd5=af0ddc1ce6b332fbeab1ff861ca658c2
Metadata:      OutputPriority=primary
Metadata:      XRANDR_name=DP-2
"""
const DELL_XRANDR := """Monitors: 1
 0: +*DP-2 1920/520x1200/320+0+0  DP-2
"""

## Two monitors side by side, as Godot numbers its screens.
const LEFT := Rect2i(0, 0, 1920, 1200)
const RIGHT := Rect2i(1920, 0, 2560, 1440)

## A version before the step that moves the shipped sRGB to the system's.
const BEFORE_THE_STEP: int = 27

static var scratch_dir: String = SaDataRoot.path("test_settings")

var _saved_profile: String


func before_each() -> void:
    _saved_profile = SaSettings.display_profile


func after_each() -> void:
    SaSettings.display_profile = _saved_profile


func test_the_system_s_profile_is_the_display_space() -> void:
    var proofs := _proofs([SaSystemProfile.Display.new("DP-2", LEFT, P3_PROFILE)])
    var space := proofs.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 0, [LEFT])
    assert_true(
        space.shares_gamut(SaColorSpace.display_p3()), "The P3 profile the system names is the display: %s" % [space.gamut()]
    )
    var read := proofs.system_reading(0, [LEFT]).profile
    assert_eq(read.problem, "", "and nothing is said against it")
    assert_true(read.name.contains("Display P3"), "and the row reads its name: %s" % read.name)


func test_a_system_with_no_profile_leaves_srgb_and_says_why() -> void:
    var proofs := _proofs([])
    var space := proofs.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 0, [LEFT])
    assert_true(space.shares_gamut(SaColorSpace.srgb()), "A system with no profile leaves the display on sRGB")
    assert_true(proofs.system_reading(0, [LEFT]).profile.problem.contains("names no colour profile"), "and says why")
    var bare := _proofs([SaSystemProfile.Display.new("DP-2", LEFT, "")])
    assert_true(
        bare.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 0, [LEFT]).shares_gamut(SaColorSpace.srgb()),
        "So does a monitor it gives none"
    )
    assert_true(bare.system_reading(0, [LEFT]).profile.problem.contains("DP-2"), "and the reason names the monitor")


func test_a_profile_sara_cannot_read_leaves_srgb_with_its_reason() -> void:
    var path := SaDataRoot.path("test_not_a_profile.icc")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("not a profile at all, only words long enough to be read as a header and refused")
    file.close()
    var proofs := _proofs([SaSystemProfile.Display.new("DP-2", LEFT, path)])
    var space := proofs.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 0, [LEFT])
    var read := proofs.system_reading(0, [LEFT]).profile
    DirAccess.remove_absolute(path)
    assert_true(space.shares_gamut(SaColorSpace.srgb()), "A file the system names and Sara refuses leaves sRGB")
    assert_false(read.problem.is_empty(), "with SaIccProfile's reason: %s" % read.problem)
    var missing := _proofs([SaSystemProfile.Display.new("DP-2", LEFT, "/nowhere/gone.icc")])
    assert_true(missing.system_reading(0, [LEFT]).profile.problem.contains("is not there"), "and a file that is gone says so")


func test_two_screens_take_two_profiles_and_the_space_follows_the_window() -> void:
    var displays: Array[SaSystemProfile.Display] = [
        SaSystemProfile.Display.new("DP-2", LEFT, P3_PROFILE),
        SaSystemProfile.Display.new("HDMI-A-1", RIGHT, REC2020_PROFILE),
    ]
    var proofs := _proofs(displays)
    var screens: Array[Rect2i] = [LEFT, RIGHT]
    var on_left := proofs.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 0, screens)
    var on_right := proofs.display_space_on(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "", 1, screens)
    assert_true(on_left.shares_gamut(SaColorSpace.display_p3()), "On the left screen the display is its P3 profile")
    assert_true(on_right.shares_gamut(SaColorSpace.rec2020()), "and on the right its Rec. 2020 one: %s" % [on_right.gamut()])
    assert_true(proofs.screen_moved(0), "The first look says the view has to ask")
    assert_false(proofs.screen_moved(0), "staying on the screen says nothing")
    assert_true(proofs.screen_moved(1), "and crossing to the other says it again")


## Godot sizes a scaled desktop's screens in logical pixels and the system in
## device ones, so a screen of the same shape is the same monitor. One of
## another shape is no monitor the system knows, which is what a nested
## compositor's output is.
func test_a_screen_is_matched_to_its_monitor_by_where_it_stands() -> void:
    var displays: Array[SaSystemProfile.Display] = [SaSystemProfile.Display.new("DP-2", LEFT, P3_PROFILE)]
    var halved: Array[Rect2i] = [Rect2i(0, 0, 960, 600)]
    assert_eq(SaSystemProfile.matched(displays, halved, 0), displays[0], "A scaled screen of the same shape is the monitor")
    var nested: Array[Rect2i] = [Rect2i(0, 0, 1920, 1080)]
    assert_null(SaSystemProfile.matched(displays, nested, 0), "A screen of another shape is no monitor the system knows")
    var proofs := _proofs(displays)
    assert_true(proofs.system_reading(0, nested).profile.problem.contains("stands where"), "and the row says so")


func test_colord_s_answer_on_a_dell_names_the_dell_s_profile() -> void:
    var displays := SaSystemProfile.colormgr_displays(DELL_COLORMGR)
    assert_eq(displays.size(), 1, "One display")
    assert_eq(displays[0].name, "DP-2", "named by its output")
    assert_eq(
        displays[0].path,
        "/home/painter/.local/share/icc/edid-af0ddc1ce6b332fbeab1ff861ca658c2.icc",
        "with its first profile's file"
    )
    var rects := SaSystemProfile.xrandr_rects(DELL_XRANDR)
    assert_eq(rects.get("DP-2", Rect2i()), Rect2i(0, 0, 1920, 1200), "and xrandr puts DP-2 at the origin, 1920 by 1200")


func test_windows_lines_are_read_as_monitors() -> void:
    var text := (
        "\\\\.\\DISPLAY1\t0\t0\t2560\t1440\tC:\\Windows\\system32\\spool\\drivers\\color\\U2412M.icm\r\n"
        + "\\\\.\\DISPLAY2\t2560\t0\t1920\t1080\t\r\n"
    )
    var displays := SaSystemProfile.windows_displays(text)
    assert_eq(displays.size(), 2, "Two monitors")
    assert_eq(displays[0].rect, Rect2i(0, 0, 2560, 1440), "each where it stands")
    assert_true(displays[0].path.ends_with("U2412M.icm"), "the first with its profile")
    assert_eq(displays[1].path, "", "and the second with none")


func test_the_stand_in_names_one_profile_or_none() -> void:
    assert_true(SaSystemProfile.stand_in(SaSystemProfile.NONE).is_empty(), "none is a system with no profile")
    var one := SaSystemProfile.stand_in(P3_PROFILE)
    assert_eq(one.size(), 1, "and a path is one monitor")
    assert_eq(SaSystemProfile.matched(one, [Rect2i(0, 0, 1920, 1080)], 0), one[0], "that the one screen shows")


func test_an_empty_settings_folder_starts_on_the_system_s_profile() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("settings.cfg")
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    var chosen := _loaded_from(path)
    DirAccess.remove_absolute(path)
    DirAccess.remove_absolute(scratch_dir)
    assert_eq(chosen, SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "A first launch starts on the system's profile")


func test_a_painter_who_chose_display_p3_keeps_it() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", BEFORE_THE_STEP)
    config.set_value("ui", "display_profile", "display_p3")
    assert_eq(_loaded(config), "display_p3", "Display P3 chosen in an older build is kept")
    config.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    config.set_value("ui", "display_profile", "srgb")
    assert_eq(_loaded(config), "srgb", "and so is an sRGB chosen under this build")
    config.set_value("meta", "version", BEFORE_THE_STEP)
    assert_eq(
        _loaded(config),
        SaSettingsValues.DISPLAY_PROFILE_SYSTEM,
        "while the sRGB an older build shipped with moves to the system's once"
    )


func test_android_keeps_srgb_and_is_not_offered_the_system_s() -> void:
    assert_eq(SaSettingsValues.display_profile_default("Android"), "srgb", "Android starts on sRGB")
    assert_false(
        SaSettingsValues.display_profile_offered(SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "Android"),
        "and is not offered the system's"
    )
    assert_eq(
        SaSettingsValues.display_profile_default("Windows"),
        SaSettingsValues.DISPLAY_PROFILE_SYSTEM,
        "Windows starts on the system's"
    )
    assert_eq(SaSettingsValues.display_profile_default("Linux"), SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "and so does Linux")


func _proofs(displays: Array) -> SaSettingsProofs:
    var answer: Array[SaSystemProfile.Display] = []
    answer.assign(displays)
    return SaSettingsProofs.new(SaSystemProfile.new(func() -> Array[SaSystemProfile.Display]: return answer))


## The display profile *config* loads at, through `SaSettings.load_settings`,
## and then the runner's own file read again.
func _loaded(config: ConfigFile) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("settings.cfg")
    config.save(path)
    var chosen := _loaded_from(path)
    DirAccess.remove_absolute(path)
    DirAccess.remove_absolute(scratch_dir)
    return chosen


func _loaded_from(path: String) -> String:
    var saved_path: String = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(path)
    SaSettings.load_settings()
    var chosen: String = SaSettings.display_profile
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    return chosen
