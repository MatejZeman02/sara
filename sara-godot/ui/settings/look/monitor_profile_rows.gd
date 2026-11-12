## The Display profile row on Preferences > Display and, under it while the
## monitor's own profile is the choice, the row that picks the ICC file and
## names the profile read from it. While the system's profile is the choice the
## same row names the profile the system gave the monitor the window is on, or
## why there is none, and offers no file.
##
## A class of its own beside `display_page.gd`, because the file row is a
## control with a picker and a reading of a file, a responsibility of its own,
## and the page is near the length that fails a run. These open the page's
## Gamuts section, and `SaProofProfileRows` adds the Proof gamut and its own
## file, kept apart from this one because the device a painting is proofed for
## is seldom the panel it is painted on.
class_name SaMonitorProfileRows
extends RefCounted

## The file row's key, which the profile row hides under every preset.
const FILE_ROW := &"display_profile_file"

## The control's children, by name, so a test and the dump can find them.
const NAME_LABEL := "MonitorProfileName"
const PATH_LABEL := "MonitorProfilePath"
const CHOOSE_BUTTON := "MonitorProfileChoose"


## Opens *ui*'s Gamuts section with the two rows, and the page goes on filling
## it. *profile_key* names the profile row the way the rest of Sara finds it.
func declare(ui: SaPage, profile_key: StringName) -> void:
    var section := ui.section("Gamuts")
    var profile_row := (
        SaColorSpaceRow
        . new(&"display_profile", &"display_custom_space", _choices())
        . declare(ui, "Display profile")
        . explain(
            tr(
                (
                    "The gamut and white your monitor shows. The view converts into them last, and encodes as sRGB."
                    + " The system's profile reads the profile your system assigns the monitor Sara is on,"
                    + " and follows the window to another monitor."
                    + " Monitor profile file reads the primaries of your panel's own ICC profile."
                    + " Custom... opens the colour space picker for any other gamut and white."
                )
            )
        )
        . named(profile_key)
    )
    (
        section
        . custom("Monitor profile", _file_control())
        . explain(
            tr(
                (
                    "A matrix monitor profile, ICC version 2 or 4, such as the one a calibration wrote."
                    + " Its primaries and white become the display."
                    + " A profile that cannot be read leaves the display on sRGB and says why."
                    + " Under The system's profile it names the profile your system gave the monitor instead."
                )
            )
        )
        . named(FILE_ROW)
    )
    profile_row.hides(FILE_ROW, [SaSettingsValues.DISPLAY_PROFILE_FILE, SaSettingsValues.DISPLAY_PROFILE_SYSTEM])


## The display profile's list: the presets the proof gamut offers too, the
## monitor's own profile file, and the system's profile where the platform has
## one to give.
func _choices() -> Array:
    var choices: Array = []
    for profile_id: String in SaSettings.DISPLAY_PROFILES:
        choices.append({"id": profile_id, "label": tr(SaColorSpace.display_name(StringName(profile_id)))})
    choices.append({"id": SaSettingsValues.DISPLAY_PROFILE_FILE, "label": tr("Monitor profile file")})
    if SaSettingsValues.display_profile_offered(SaSettingsValues.DISPLAY_PROFILE_SYSTEM):
        choices.append({"id": SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "label": tr("The system's profile")})
    return choices


## The profile's name or why it was not read, the file's path, and a button that
## picks another.
func _file_control() -> Control:
    var box := SaMake.column(null, "MonitorProfileBox", 6)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var said := SaMake.label(box, NAME_LABEL)
    said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var shown := SaPathRow.PathLabel.new()
    shown.name = PATH_LABEL
    shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(shown)
    var choose := SaMake.button(box, CHOOSE_BUTTON, tr("Choose..."))
    choose.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    choose.pressed.connect(_choose.bind(box))
    _show(box)
    # The choice moving between the file and the system's, the window crossing
    # to another monitor and the system's late answer all reach the view as this.
    var again := func(_enabled: bool) -> void: _show(box)
    box.tree_entered.connect(
        func() -> void:
            if not EventBus.tonemap_changed.is_connected(again):
                EventBus.tonemap_changed.connect(again)
    )
    box.tree_exiting.connect(
        func() -> void:
            if EventBus.tonemap_changed.is_connected(again):
                EventBus.tonemap_changed.disconnect(again)
    )
    return box


func _choose(box: Control) -> void:
    var filters := PackedStringArray([tr("*.icc, *.icm ; ICC profiles")])
    SaFilePicker.open(box, SaFilePicker.Mode.OPEN_FILE, filters, _chosen.bind(box), tr("Choose a Monitor Profile"))


func _chosen(path: Variant, box: Control) -> void:
    SaSettings.display_profile_file = String(path)
    if is_instance_valid(box):
        _show(box)


## What the row says for the file the settings hold, or for the system's.
static func _show(box: Control) -> void:
    var path := SaSettings.display_profile_file
    var said := box.find_child(NAME_LABEL, false, false) as Label
    var shown := box.find_child(PATH_LABEL, false, false) as SaPathRow.PathLabel
    var system := SaSettings.display_profile == SaSettingsValues.DISPLAY_PROFILE_SYSTEM
    (box.find_child(CHOOSE_BUTTON, false, false) as Control).visible = not system
    if system:
        _show_system(said, shown)
        return
    shown.show_path(path)
    if path.is_empty():
        said.text = SaPage.translated("No file chosen. The display stays on sRGB.")
        return
    var profile := SaIccProfile.read(path)
    if profile.space != null:
        said.text = profile.name
    else:
        said.text = "%s %s" % [profile.problem, SaPage.translated("The display stays on sRGB.")]


## The profile the system gave the monitor the window is on, and its file, or
## why the display stays on sRGB.
static func _show_system(said: Label, shown: SaPathRow.PathLabel) -> void:
    var reading := SaSettings.proofs.system_reading(DisplayServer.window_get_current_screen(), SaSystemProfile.godot_screens())
    var profile := reading.profile
    shown.show_path(reading.path)
    if profile.space != null:
        said.text = SaPage.translated("%s, the system's profile for %s.") % [profile.name, reading.monitor]
    else:
        said.text = "%s %s" % [profile.problem, SaPage.translated("The display stays on sRGB.")]
