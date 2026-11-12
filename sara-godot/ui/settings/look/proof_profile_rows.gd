## The Proof gamut row on Preferences > Display and, under it while a profile
## file is the choice, the row that picks the file of the device the painting is
## made for and names the profile read from it.
##
## A class of its own beside `display_page.gd`, as `SaMonitorProfileRows` is,
## because the file row is a control with a picker and a reading of a file, and
## the page is near the length that fails a run. The proof keeps a path apart
## from the monitor's: the screen the painter sits at is seldom the phone or the
## client's monitor the painting is proofed for.
class_name SaProofProfileRows
extends RefCounted

## The proof gamut row's key, as the rest of Sara finds it.
const PROFILE_ROW := &"proof_profile"
## The file row's key, which the proof gamut row hides under every preset.
const FILE_ROW := &"proof_profile_file"

## The control's children, by name, so a test and the dump can find them.
const NAME_LABEL := "ProofProfileName"
const PATH_LABEL := "ProofProfilePath"
const CHOOSE_BUTTON := "ProofProfileChoose"


## Adds the two rows to *ui*'s last section, the page's Gamuts section. The
## proof gamut row is the colour space picker's, so the saved spaces and
## Custom... follow the file entry as they follow the presets.
func declare(ui: SaPage) -> void:
    var section := ui.sections[-1]
    var profile_row := (
        SaColorSpaceRow
        . new(&"proof_profile", &"proof_custom_space", _choices())
        . declare(ui, "Proof gamut")
        . explain(
            tr(
                (
                    "The gamut View > Soft Proof and the Minimap's proof clip the picture to, an RGB gamut, "
                    + "so a print proof is not among them. Never touches a pixel."
                    + " Profile file reads the primaries of a device's own ICC profile, a phone's or a client's monitor's,"
                    + " and reads it again when the file changes. Custom... opens the colour space picker."
                )
            )
        )
        . named(PROFILE_ROW)
        . node("ProofGamutOption")
    )
    (
        section
        . custom("Proof profile", _file_control())
        . explain(
            tr(
                (
                    "A matrix display profile, ICC version 2 or 4, of the device the painting is made for."
                    + " Its primaries and white become the proof gamut."
                    + " A profile that cannot be read leaves the proof on sRGB and says why."
                )
            )
        )
        . named(FILE_ROW)
    )
    profile_row.hides(FILE_ROW, SaSettingsValues.PROOF_PROFILE_FILE)


## The proof gamut's list: every preset `SaSettings.DISPLAY_PROFILES` names, and
## a device's profile file last.
func _choices() -> Array:
    var choices: Array = []
    for profile_id: String in SaSettings.DISPLAY_PROFILES:
        choices.append({"id": profile_id, "label": tr(SaColorSpace.display_name(StringName(profile_id)))})
    choices.append({"id": SaSettingsValues.PROOF_PROFILE_FILE, "label": tr("Profile file")})
    return choices


## The profile's name or why it was not read, the file's path, and a button that
## picks another.
func _file_control() -> Control:
    var box := SaMake.column(null, "ProofProfileBox", 6)
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
    show_file(box)
    return box


func _choose(box: Control) -> void:
    var filters := PackedStringArray([tr("*.icc, *.icm ; ICC profiles")])
    SaFilePicker.open(box, SaFilePicker.Mode.OPEN_FILE, filters, _chosen.bind(box), tr("Choose a Proof Profile"))


func _chosen(path: Variant, box: Control) -> void:
    SaSettings.proof_profile_file = String(path)
    if is_instance_valid(box):
        show_file(box)


## What the row says for the file the settings hold.
static func show_file(box: Control) -> void:
    var path := SaSettings.proof_profile_file
    var said := box.find_child(NAME_LABEL, false, false) as Label
    var shown := box.find_child(PATH_LABEL, false, false) as SaPathRow.PathLabel
    shown.show_path(path)
    if path.is_empty():
        said.text = SaPage.translated("No file chosen. The soft proof stays on sRGB.")
        return
    var profile := SaIccProfile.read(path)
    if profile.space != null:
        said.text = profile.name
    else:
        said.text = "%s %s" % [profile.problem, SaPage.translated("The soft proof stays on sRGB.")]
