## The one colour space picker: the preset as a shortcut, the gamut with its
## primaries as xy, the white point, the curve, the gamma, the colour model and
## the depth, and the spaces the painter saved under a name.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The facade of `ui/color_space/picker`. Every place that asks for a colour
## space builds this rather than a chooser of its own, so a space a painter can
## make in one place can be chosen in every other: File > New shows its rows
## behind the details switch, Image > Colour Space shows them as its Target.
##
## It holds rows and the rules between them and no window. A host declares the
## rows on its own `SaPage`, binds them through itself as *held_as*, hands every
## row change to [method row_changed] and pushes the rows back into their
## controls when [signal moved] fires, the way File > New's rows always worked.
##
## The rows are a shortcut and the numbers behind it. The primaries, the white,
## the curve, the colour model and the depth are the space, held here as values,
## and every choice row is a label for them that moves when they do:
## [method selected_space] reads the values, never a row. That is what lets a
## painter pick ACEScg and then move one primary, and what lets a saved space be
## any combination at all, since most combinations have no name.
@tool
class_name SaColorSpacePicker
extends RefCounted

## A rule moved the rows, or the painter moved a field. The host pushes every
## row back into its control and brings the rest of its page after them.
signal moved

## The last entry of the preset, gamut and white point rows, selected when the
## values add up to nothing those rows name.
const CUSTOM_LABEL := "Custom"

## The preset row's last entry, past Custom, which opens a file dialog for an
## ICC profile rather than naming a space.
const PROFILE_FILE_LABEL := "Profile file…"

## The tone curve row's last entry, one past the named curves, which the gamma
## slider drives. "Custom" because it stands in a list of named curves, several
## of them gammas too.
const GAMMA_LABEL := "Custom gamma"

## The whites a painter names. D50 joins the two the gamuts imply because it is
## the white of print and of every ICC profile's connection space, so a space
## built for print work names it rather than typing it.
const WHITE_D50 := Vector2(0.34567, 0.35850)
const WHITES: Array[Dictionary] = [
    {"label": "D65", "xy": SaColorSpace.WHITE_D65},
    {"label": "D60", "xy": SaColorSpace.WHITE_D60},
    {"label": "D50", "xy": WHITE_D50},
]

## The rows that describe the space itself, which a host with a details switch
## keeps behind it. The preset and the depth are the two the painter picks.
const DETAIL_KEYS: Array[StringName] = [
    &"gamut", &"primaries", &"white", &"white_xy", &"transfer", &"gamma", &"coordinates", &"save_space"
]

## The step a typed coordinate snaps to. Four places is what every published
## standard gives its primaries and whites to.
const XY_STEP := 0.0001


## An HSlider with vertical marks at the exponents people actually reach for.
##
## Godot's own `tick_count` spaces ticks evenly across the range, which at 0.1 to
## 6.0 puts none of them on 2.2 or 2.4. These are drawn at the values themselves.
## They are a guide rather than a snap: the slider still stops anywhere its step
## allows, because the space between the named curves is the reason it exists.
class GammaSlider:
    extends HSlider

    const MARKS: Array[float] = [1.0, 2.2, 2.4, 2.6, 3.0]

    func _draw() -> void:
        var span := maxf(max_value - min_value, 0.0001)
        # The grabber travels between its own half-widths, not between the edges,
        # so a mark drawn at the plain fraction of the width sits off the value it
        # names by half a grabber at each end.
        var grabber := get_theme_icon(&"grabber")
        var inset: float = float(grabber.get_width()) * 0.5 if grabber != null else 0.0
        var usable := maxf(size.x - inset * 2.0, 1.0)
        var tint := Color(1.0, 1.0, 1.0, 0.35)
        for mark: float in MARKS:
            if mark < min_value or mark > max_value:
                continue
            var x := inset + (mark - min_value) / span * usable
            # Above and below the track, so a mark never sits on top of the fill
            # and reads as part of it.
            draw_line(Vector2(x, 0.0), Vector2(x, size.y * 0.28), tint, 1.0)
            draw_line(Vector2(x, size.y * 0.72), Vector2(x, size.y), tint, 1.0)


## One chromaticity as two typed numbers, x and y, under a word that says which
## light it is. A row kind of the page has no mark for a pair, and a pair split
## over two rows reads as two unrelated numbers.
class XyField:
    extends HBoxContainer

    ## The painter typed a coordinate. *xy* is the pair as it now stands.
    signal edited(xy: Vector2)

    var x_spin: SpinBox = null
    var y_spin: SpinBox = null

    ## *said* is already in the painter's language.
    func _init(node_name: String, said: String) -> void:
        name = node_name
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_theme_constant_override("separation", SaUI.px(6))
        if not said.is_empty():
            var word := SaMake.label(self, "Word", said)
            word.custom_minimum_size.x = float(SaUI.px(44))
        x_spin = _spin("X")
        y_spin = _spin("Y")

    func _spin(axis: String) -> SpinBox:
        var spin := SaMake.spin_box(self, axis, 0.0, 1.0, XY_STEP, 0.0)
        spin.prefix = axis.to_lower()
        spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        spin.value_changed.connect(func(_value: float) -> void: edited.emit(xy()))
        return spin

    ## The pair the two fields hold.
    func xy() -> Vector2:
        return Vector2(float(x_spin.value), float(y_spin.value))

    ## Shows *point* without announcing it, so a rule that moved the values
    ## never reads as the painter typing.
    func show_xy(point: Vector2) -> void:
        x_spin.set_value_no_signal(point.x)
        y_spin.set_value_no_signal(point.y)


## The three primaries, red, green and blue, one pair each.
class PrimariesField:
    extends VBoxContainer

    signal edited(primaries: PackedVector2Array)

    var lights: Array[XyField] = []

    func _init() -> void:
        name = "PrimariesFields"
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # Each word a literal, so the catalogue's extractor reads it.
        var words := [SaPage.translated("Red"), SaPage.translated("Green"), SaPage.translated("Blue")]
        for i: int in range(3):
            var light := XyField.new("%sXy" % ["Red", "Green", "Blue"][i], words[i])
            light.edited.connect(func(_xy: Vector2) -> void: edited.emit(primaries()))
            add_child(light)
            lights.append(light)

    func primaries() -> PackedVector2Array:
        var out := PackedVector2Array()
        for light: XyField in lights:
            out.append(light.xy())
        return out

    func show_primaries(xy: PackedVector2Array) -> void:
        for i in mini(xy.size(), lights.size()):
            lights[i].show_xy(xy[i])


## The name field, Save, Rename and Delete under the rows. Rename and Delete act
## on the saved space the preset row shows, so they are live only while it
## shows one.
class SaveRow:
    # A flow, so on a narrow host the buttons go under the name rather than
    # widening the dialog past the host's edge.
    extends HFlowContainer

    var name_field: LineEdit = null
    var save_button: Button = null
    var rename_button: Button = null
    var delete_button: Button = null

    func _init(saving: Callable, renaming: Callable, deleting: Callable) -> void:
        name = "SpaceSaver"
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_theme_constant_override("h_separation", SaUI.px(6))
        add_theme_constant_override("v_separation", SaUI.px(6))
        name_field = LineEdit.new()
        name_field.name = "SpaceName"
        name_field.placeholder_text = SaPage.translated("Name")
        name_field.custom_minimum_size.x = SaUI.px(100)
        name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_field.text_submitted.connect(func(_text: String) -> void: saving.call(name_field.text))
        add_child(name_field)
        save_button = _button(
            "SaveSpace", "Save as…", "Keep this colour space under the name typed, for every place that asks for one."
        )
        save_button.pressed.connect(func() -> void: saving.call(name_field.text))
        rename_button = _button("RenameSpace", "Rename", "Give the saved colour space shown above the name typed.")
        rename_button.pressed.connect(func() -> void: renaming.call(name_field.text))
        delete_button = _button("DeleteSpace", "Delete", "Forget the saved colour space shown above.")
        delete_button.pressed.connect(deleting)

    func _button(node_name: String, text: String, tip: String) -> Button:
        var made := Button.new()
        made.name = node_name
        made.text = SaPage.translated(text)
        made.tooltip_text = SaPage.translated(tip)
        add_child(made)
        return made


## The spaces the painter saved, kept with their settings as a name and the
## space's own header, the record a `.sad` writes, so a saved space reads back
## with every value a document's would.
class Saved:
    const NAME := "name"
    const SPACE := "space"

    ## Every saved space in the order it was saved, `{"name", "space"}` with the
    ## space as an `SaColorSpace`. A record the header reader cannot read is
    ## left out rather than shown as sRGB.
    static func listed() -> Array[Dictionary]:
        var out: Array[Dictionary] = []
        for record: Variant in SaSettings.saved_color_spaces:
            if not record is Dictionary or not (record as Dictionary).has(SPACE):
                continue
            var raw: Variant = record[SPACE]
            if not raw is Dictionary:
                continue
            var header: Dictionary[String, Variant] = {"color_space": raw}
            var space := SaColorSpace.from_header(header)
            space.id = SaColorSpace.ID_CUSTOM
            out.append({NAME: String(record.get(NAME, "")), SPACE: space})
        return out

    ## Keeps *space* under *wanted*, trimmed, in place of a saved space of the
    ## same name. Answers the name kept, or empty for an empty name.
    static func save(wanted: String, space: SaColorSpace) -> String:
        var kept_as := wanted.strip_edges()
        if kept_as.is_empty() or space == null:
            return ""
        var records := _without(kept_as)
        records.append({NAME: kept_as, SPACE: Dictionary(space.to_header())})
        SaSettings.saved_color_spaces = records
        return kept_as

    ## Gives the space saved as *from* the name *to*. Answers whether it did:
    ## not for a name nothing holds, an empty one, or one another space holds.
    static func rename(from: String, to: String) -> bool:
        var wanted := to.strip_edges()
        if wanted.is_empty() or (wanted != from and has(wanted)) or not has(from):
            return false
        var records: Array = SaSettings.saved_color_spaces.duplicate(true)
        for record: Variant in records:
            if record is Dictionary and String(record.get(NAME, "")) == from:
                record[NAME] = wanted
        SaSettings.saved_color_spaces = records
        return true

    ## Forgets the space saved as *saved_name*, and answers whether there was one.
    static func delete(saved_name: String) -> bool:
        if not has(saved_name):
            return false
        SaSettings.saved_color_spaces = _without(saved_name)
        return true

    static func has(saved_name: String) -> bool:
        for record: Dictionary in listed():
            if record[NAME] == saved_name:
                return true
        return false

    static func _without(saved_name: String) -> Array:
        return SaSettings.saved_color_spaces.duplicate(true).filter(
            func(record: Variant) -> bool: return not (record is Dictionary and String(record.get(NAME, "")) == saved_name)
        )


## The rows the host binds, each the position of its entry, which is what every
## rule below and the committed scenarios take.
var space_row: int = 0
var gamut_row: int = 0
var white_row: int = 0
var transfer_row: int = 0
var coordinates_row: int = 0
var depth_row: int = 0

## The space's own values, which the rows above name when they can.
var primaries: PackedVector2Array = SaGamut.srgb().primaries
var white: Vector2 = SaColorSpace.WHITE_D65

## The saved spaces as the preset row lists them, read when the rows are
## declared and again after a save, a rename or a delete.
var saved: Array[Dictionary] = []

## The name field and its three buttons, once the details are declared.
var save_row: SaveRow = null
## The drawing of the chosen space, when a host asked for one.
var browser: SaColorSpaceBrowser = null

var _gamma_slider: HSlider = null
var _gamma_value: Label = null
## The exponent the slider's entry means, held as well as shown so a picker
## whose details were never drawn still knows its curve.
var _custom_gamma: float = SaTransferFunction.srgb().exponent
var _primaries_field: PrimariesField = null
var _white_field: XyField = null
## The preset row, whose list follows the saved spaces.
var _space_entry: SaPageRow = null

## The profile file read last, listed above Custom under its description, or
## null. A host that opens on a document whose space came from a file lists
## that space here too, under the name the document saved.
var profile: SaProfileFile = null

## Why the last profile file offered was refused, for the host's status line,
## or empty. Cleared by the next move of the rows.
var profile_problem: String = ""

## The window the rows stand in, which the profile file's dialog opens over.
var _host: Node = null

## The row [method _settle] last put the preset row on, where it goes back to
## when the painter picks Profile file and the dialog has not answered.
var _shown_row: int = 0

## Guards the two-way sync between the transfer row and the gamma slider.
var _syncing: bool = false


func _init() -> void:
    saved = Saved.listed()
    # A space saved in one picker is listed in every other one open at the time.
    SaSettings.changed.connect(_on_settings_changed)


## The preset, saved spaces under it, then Custom, and the depth unless the
## host's space keeps its own. Declared on the section *ui* has open, bound
## through *window*, which holds this picker as *held_as*. *title* is the
## row's word, "Target" in a dialog that converts to it.
func declare_picked(
    ui: SaPage, window: Object, held_as: StringName, title: String = "Colour space", with_depth: bool = true
) -> void:
    var rows := ui.sections[-1]
    _host = window as Node
    _space_entry = rows.choice(title, space_labels(), window, _through(held_as, "space_row"))
    _space_entry.named(&"space").node("SpaceOption")
    if not with_depth:
        return
    # Built from SaColorSpace.storage_depths(), never listed by hand, so a
    # choice of a depth chunk storage cannot allocate never reaches a header.
    var depths: Array = SaColorSpace.storage_depths().map(func(depth: int) -> String: return SaColorSpace.depth_name(depth))
    rows.choice("Bit depth", depths, window, _through(held_as, "depth_row")).named(&"depth").node("DepthOption")


## The rows of [constant DETAIL_KEYS], on the section *ui* has open, bound as
## [method declare_picked] binds.
func declare_details(ui: SaPage, window: Object, held_as: StringName) -> void:
    var rows := ui.sections[-1]
    var gamuts: Array = SaGamut.presets().map(func(g: SaGamut) -> String: return g.display_name)
    rows.choice("Gamut", gamuts + [tr(CUSTOM_LABEL)], window, _through(held_as, "gamut_row")).named(&"gamut").node(
        "GamutRowOption"
    )
    _primaries_field = PrimariesField.new()
    _primaries_field.edited.connect(_on_primaries_typed)
    rows.custom("Primaries", _primaries_field).named(&"primaries")
    # A gamut implies a white, D60 for ACES AP1 and D65 for the rest, and
    # picking a gamut moves this row there. It is a row of its own because a
    # space for print is the same three lights at D50.
    var whites: Array = WHITES.map(func(entry: Dictionary) -> String: return String(entry["label"]))
    var white_entry := rows.choice("White point", whites + [tr(CUSTOM_LABEL)], window, _through(held_as, "white_row"))
    white_entry.named(&"white").node("WhitePointOption")
    white_entry.explain(tr("Picking a gamut moves it to that gamut's own white."))
    _white_field = XyField.new("WhitePointXy", "")
    _white_field.edited.connect(_on_white_typed)
    rows.custom("White xy", _white_field).named(&"white_xy")
    # Each curve by its short name, the words in brackets left to the tooltip:
    # the column is narrow and cut "Gamma 3.0 (cube root)" to "Gamma 3.0 (cub".
    var curves: Array = SaTransferFunction.presets().map(
        func(c: SaTransferFunction) -> String: return transfer_label(c.display_name)
    )
    var transfer := rows.choice("Tone curve", curves + [tr(GAMMA_LABEL)], window, _through(held_as, "transfer_row"))
    transfer.named(&"transfer").node("TransferOption")
    rows.custom("Gamma", _gamma_row()).named(&"gamma")
    # What the chunks actually hold, RGB or Oklab. The rows above describe the
    # document's RGB view either way.
    var systems: Array = SaColorSpace.storage_coordinates().map(
        func(system: int) -> String: return SaColorSpace.coordinates_name(system)
    )
    var coordinates := rows.choice("Colour model", systems, window, _through(held_as, "coordinates_row"))
    coordinates.named(&"coordinates").node("CoordinatesOption")
    save_row = SaveRow.new(save_as, rename_saved, delete_saved)
    rows.custom("Save colour space", save_row).named(&"save_space")
    _show_values()


## The preset row's entries: the presets, the saved spaces by name, the
## profile file read last by its description, Custom, and Profile file.
func space_labels() -> Array:
    var labels: Array = SaColorSpace.presets().map(func(p: SaColorSpace) -> String: return SaColorSpace.display_name(p.id))
    for record: Dictionary in saved:
        labels.append(String(record[Saved.NAME]))
    if profile != null:
        labels.append(profile.name)
    labels.append(tr(CUSTOM_LABEL))
    labels.append(tr(PROFILE_FILE_LABEL))
    return labels


## The row the Custom entry stands at, one past the presets, the saved spaces
## and the profile file read.
func custom_row() -> int:
    return SaColorSpace.presets().size() + saved.size() + (1 if profile != null else 0)


## The row the profile file read stands at, or -1 when none was.
func profile_row() -> int:
    return SaColorSpace.presets().size() + saved.size() if profile != null else -1


## The row that opens the file dialog, the last.
func profile_file_row() -> int:
    return custom_row() + 1


## *property* of this class as the host reaches it, `picker:space_row`, so a
## row's binding is the host's own and its write lands here through the host's
## member, the way `SaOptionSpec` reaches a tip through `tip:image_path`.
static func _through(held_as: StringName, property: String) -> NodePath:
    return NodePath("%s:%s" % [held_as, property])


## The gamma slider and its readout, the one control a row kind has no mark for.
func _gamma_row() -> HBoxContainer:
    var gamma_row := SaMake.row(null, "GammaRow", SaTheme.GAP)
    gamma_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _gamma_slider = GammaSlider.new()
    _gamma_slider.name = "GammaSlider"
    _gamma_slider.min_value = SaTransferFunction.MIN_GAMMA
    _gamma_slider.max_value = SaTransferFunction.MAX_GAMMA
    _gamma_slider.step = 0.1
    _gamma_slider.value = SaTransferFunction.srgb().exponent
    _gamma_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _gamma_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _gamma_slider.value_changed.connect(_on_gamma_moved)
    gamma_row.add_child(_gamma_slider)
    _gamma_value = SaMake.label(gamma_row, "GammaValue")
    _gamma_value.custom_minimum_size = Vector2(float(SaUI.px(44)), 0.0)
    _gamma_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _sync_gamma_row()
    return gamma_row


## The drawing of what the rows add up to, made once and kept in step with
## every move from then on. The host places it where its page has room.
func make_browser() -> SaColorSpaceBrowser:
    if browser == null:
        browser = SaColorSpaceBrowser.new(true)
        browser.name = "ColorSpaceBrowser"
        browser.show_space(selected_space())
    return browser


## A row moved on the host's page. Answers whether *key* was one of the
## picker's rows.
func row_changed(key: StringName) -> bool:
    match key:
        &"space":
            _on_space_picked(space_row)
        &"gamut":
            _on_gamut_picked(gamut_row)
        &"white":
            _on_white_picked(white_row)
        &"transfer":
            _on_transfer_selected(transfer_row)
        &"coordinates", &"depth":
            _settle()
        _:
            return false
    return true


## Puts every row and every value on *space*. What a host opens on, and the
## one place that says what an unanswered picker means. The depth is set here
## and never by a preset, because a preset carries none: depth is orthogonal to
## what the colours mean.
func show_space(space: SaColorSpace) -> void:
    if space == null:
        return
    if not space.profile_name.is_empty() and (profile == null or profile.name != space.profile_name):
        profile = SaProfileFile.new(space.profile_name, space)
        relist()
    depth_row = maxi(SaColorSpace.storage_depths().find(space.depth), 0)
    _take_values(space)
    gamut_row = _gamut_row_for(primaries)
    white_row = _white_row_for(white)
    _settle()


## The preset, saved space or profile file at *index* fills every value but
## the depth. Custom fills nothing, it is what the row reads once a value
## moved. Profile file puts the row back on what the values are and opens the
## file dialog, whose answer lands in [method take_profile_file].
func _on_space_picked(index: int) -> void:
    var presets := SaColorSpace.presets()
    var chosen: SaColorSpace = null
    if index == profile_file_row():
        _settle(_shown_row)
        if _host != null and is_instance_valid(_host):
            SaProfileFile.ask(_host, take_profile_file)
        return
    if index >= 0 and index < presets.size():
        chosen = presets[index]
    elif index >= presets.size() and index < presets.size() + saved.size():
        chosen = saved[index - presets.size()][Saved.SPACE]
    elif index == profile_row():
        chosen = profile.space
    if chosen == null:
        _settle()
        return
    _take_values(chosen)
    gamut_row = _gamut_row_for(primaries)
    white_row = _white_row_for(white)
    # The row stays on the entry picked even when a preset holds the same
    # values, so a saved space that copies sRGB still reads as its own name.
    _settle(index)


## The values of *space* other than its depth, the curve onto the slider when
## no named curve is it.
func _take_values(space: SaColorSpace) -> void:
    primaries = space.primaries.duplicate()
    white = space.white
    var curves := SaTransferFunction.presets()
    transfer_row = curves.size()
    _syncing = true
    if _gamma_slider != null:
        _gamma_slider.value = space.transfer.exponent
    _custom_gamma = space.transfer.exponent
    for i in curves.size():
        if curves[i].id == space.transfer.id:
            transfer_row = i
            _custom_gamma = curves[i].exponent
            if _gamma_slider != null:
                _gamma_slider.value = curves[i].exponent
            break
    _syncing = false
    _sync_gamma_row()
    var systems := SaColorSpace.storage_coordinates()
    coordinates_row = maxi(systems.find(space.coordinates), 0)


## A named gamut puts its primaries in and its own white with them, the pairing
## every standard uses. Custom keeps the numbers the fields hold, which is
## where a painter goes to type new ones.
func _on_gamut_picked(index: int) -> void:
    var gamuts := SaGamut.presets()
    if index >= 0 and index < gamuts.size():
        primaries = gamuts[index].primaries.duplicate()
        white = gamuts[index].default_white()
        white_row = _white_row_for(white)
    _settle()


func _on_white_picked(index: int) -> void:
    if index >= 0 and index < WHITES.size():
        white = WHITES[index]["xy"]
    _settle()


func _on_primaries_typed(typed: PackedVector2Array) -> void:
    primaries = typed
    gamut_row = _gamut_row_for(primaries)
    _settle()


func _on_white_typed(typed: Vector2) -> void:
    white = typed
    white_row = _white_row_for(white)
    _settle()


## Dragging the slider is itself a choice of curve, so it moves the transfer row
## onto its entry rather than needing that picked first.
func _on_gamma_moved(value: float) -> void:
    if _syncing:
        return
    _custom_gamma = value
    transfer_row = SaTransferFunction.presets().size()
    _sync_gamma_row()
    _settle()


## Picking a named curve leaves the slider showing that curve's own exponent, so
## the row never reads as something the document is not. sRGB really does have a
## 2.4 power segment, it just has a straight toe under it as well.
func _on_transfer_selected(index: int) -> void:
    var curves := SaTransferFunction.presets()
    if index < curves.size():
        _syncing = true
        _custom_gamma = curves[index].exponent
        if _gamma_slider != null:
            _gamma_slider.value = curves[index].exponent
        _syncing = false
    _sync_gamma_row()
    _settle()


## Sets the gamma the slider's entry means and puts the curve row on it, as a
## drag of the slider to *value* would.
func set_gamma(value: float) -> void:
    if _gamma_slider != null:
        _syncing = true
        _gamma_slider.value = value
        _syncing = false
    _on_gamma_moved(value)


func _sync_gamma_row() -> void:
    if _gamma_value != null and _gamma_slider != null:
        _gamma_value.text = "%.1f" % _gamma_slider.value


## The gamut row's entry for *xy*, Custom when no named gamut is those lights.
static func _gamut_row_for(xy: PackedVector2Array) -> int:
    var gamuts := SaGamut.presets()
    for i in gamuts.size():
        if gamuts[i].matches_primaries(xy):
            return i
    return gamuts.size()


## The white point row's entry for *xy*, Custom when it is none of the named.
static func _white_row_for(xy: Vector2) -> int:
    for i in WHITES.size():
        if (WHITES[i]["xy"] as Vector2).is_equal_approx(xy):
            return i
    return WHITES.size()


## Reads the profile file at *path* and puts the rows on it, under its
## description. A file the reader refuses leaves the rows where they were and
## [member profile_problem] saying why. Answers whether the file was taken.
func take_profile_file(path: String) -> bool:
    var read := SaProfileFile.read(path)
    if read.space == null:
        profile_problem = read.problem
        moved.emit()
        return false
    profile = read
    relist()
    _on_space_picked(profile_row())
    return true


## Moves the preset row to *picked*, or to whatever now matches, a preset
## first, then a saved space, then the profile file read, or onto Custom,
## shows the values in their fields and says so.
func _settle(picked: int = -1) -> void:
    var chosen := selected_space()
    profile_problem = ""
    space_row = picked if picked >= 0 else custom_row()
    var presets := SaColorSpace.presets()
    for i in presets.size():
        if picked < 0 and presets[i].with_depth(chosen.depth).matches(chosen):
            space_row = i
            break
    if picked < 0 and space_row == custom_row():
        for i in saved.size():
            if (saved[i][Saved.SPACE] as SaColorSpace).with_depth(chosen.depth).matches(chosen):
                space_row = presets.size() + i
                break
    if picked < 0 and space_row == custom_row() and not chosen.profile_name.is_empty():
        space_row = profile_row()
    _shown_row = space_row
    _show_values()
    moved.emit()


## The values into the fields and the drawing, and Rename and Delete live only
## while the preset row shows a saved space.
func _show_values() -> void:
    if _primaries_field != null:
        _primaries_field.show_primaries(primaries)
    if _white_field != null:
        _white_field.show_xy(white)
    if save_row != null:
        var on_saved := saved_name().is_empty()
        save_row.rename_button.disabled = on_saved
        save_row.delete_button.disabled = on_saved
    if browser != null:
        browser.show_space(selected_space())


## The name of the saved space the preset row shows, or empty.
func saved_name() -> String:
    var at := space_row - SaColorSpace.presets().size()
    return String(saved[at][Saved.NAME]) if at >= 0 and at < saved.size() else ""


## What the preset row would call *space*: a preset's name, a saved space's
## name, or Custom. The host's "Current:" line says it this way.
func name_of(space: SaColorSpace) -> String:
    if space == null:
        return ""
    if not space.profile_name.is_empty():
        return space.profile_name
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.with_depth(space.depth).matches(space):
            return SaColorSpace.display_name(preset.id)
    for record: Dictionary in saved:
        if (record[Saved.SPACE] as SaColorSpace).with_depth(space.depth).matches(space):
            return String(record[Saved.NAME])
    return tr(CUSTOM_LABEL)


## Keeps the space the rows add up to under *wanted* and puts the preset row on
## it. Answers the name kept, or empty when none was typed.
func save_as(wanted: String) -> String:
    var kept_as := Saved.save(wanted, selected_space())
    if kept_as.is_empty():
        return ""
    relist()
    if save_row != null:
        save_row.name_field.text = ""
    _settle()
    return kept_as


## Gives the saved space the preset row shows the name *wanted*.
func rename_saved(wanted: String) -> bool:
    var renamed := Saved.rename(saved_name(), wanted)
    if renamed:
        relist()
        if save_row != null:
            save_row.name_field.text = ""
        _settle()
    return renamed


## Forgets the saved space the preset row shows. Its values stay on the rows,
## which then read Custom.
func delete_saved() -> bool:
    var gone := Saved.delete(saved_name())
    if gone:
        relist()
        _settle()
    return gone


## Reads the saved spaces again and gives the preset row the new list.
func relist() -> void:
    saved = Saved.listed()
    if _space_entry == null:
        return
    # The shape a section gives bare labels, each entry its index and its words,
    # since the row stores what its section would have built.
    var labels := space_labels()
    _space_entry.choices = range(labels.size()).map(func(i: int) -> Dictionary: return {"id": i, "label": String(labels[i])})
    if _space_entry.control != null and is_instance_valid(_space_entry.control):
        (_space_entry.control as SaChoiceButton).set_choices(_space_entry.choices)


func _on_settings_changed(key: StringName) -> void:
    if key == &"saved_color_spaces":
        relist()


## A curve's name as the Transfer row shows it, without the words in brackets.
static func transfer_label(full_name: String) -> String:
    return full_name.get_slice(" (", 0)


## The chosen curve's full name, which the Transfer row's short label left out
## and its tooltip says.
func transfer_name() -> String:
    var curves := SaTransferFunction.presets()
    return curves[transfer_row].display_name if transfer_row < curves.size() else tr(GAMMA_LABEL)


## Puts the gamut row on the preset called *gamut_name*, by its name or its id,
## and answers whether there was one.
func select_gamut(gamut_name: String) -> bool:
    var gamuts := SaGamut.presets()
    for i in gamuts.size():
        if gamuts[i].display_name == gamut_name or String(gamuts[i].id) == gamut_name:
            gamut_row = i
            _on_gamut_picked(i)
            return true
    return false


## Sets the three primaries as typing them would, for a door and a suite.
func set_primaries(xy: PackedVector2Array) -> void:
    if _primaries_field != null:
        _primaries_field.show_primaries(xy)
    _on_primaries_typed(xy)


## Sets the white as typing it would.
func set_white(xy: Vector2) -> void:
    if _white_field != null:
        _white_field.show_xy(xy)
    _on_white_typed(xy)


## `D65 (0.3127, 0.3290)`, or the coordinates alone for a white none of the
## named ones is. Static so a test can ask without a picker.
static func white_point_text(xy: Vector2) -> String:
    var name_of_white := ""
    for entry: Dictionary in WHITES:
        if xy.is_equal_approx(entry["xy"]):
            name_of_white = String(entry["label"])
    var coordinates := "(%.4f, %.4f)" % [xy.x, xy.y]
    return "%s %s" % [name_of_white, coordinates] if not name_of_white.is_empty() else coordinates


## The white, the saved space shown and the space the rows add up to, for a
## host's capture. The white is worth a number rather than a picture, because
## a screenshot cannot say whether it followed the gamut.
func capture_state() -> Dictionary:
    var space := selected_space()
    return {
        "white": white_point_text(space.white),
        "space_id": String(space.id),
        "space_name": name_of(space),
        "space_white": [space.white.x, space.white.y],
        "space_primaries": Array(space.primaries).map(func(p: Vector2) -> Array: return [p.x, p.y]),
        "space_exponent": space.transfer.exponent,
        "saved": saved.map(func(record: Dictionary) -> String: return String(record[Saved.NAME])),
        "saved_shown": saved_name(),
        "profile": profile.name if profile != null else "",
        "profile_problem": profile_problem,
    }


## The space the values add up to, at the depth the depth row names.
##
## Composed from the values, never read back off the preset row, so a painter
## who picks ACEScg and then changes the curve gets what they changed it to.
## A composition that is a named space carries that space's id, because the id
## reaches the `.sad` header and "custom" there would lose a fact the file
## could have recorded.
func selected_space() -> SaColorSpace:
    var curves := SaTransferFunction.presets()
    var curve: SaTransferFunction = (
        SaTransferFunction.gamma(_custom_gamma)
        if transfer_row >= curves.size()
        else curves[clampi(transfer_row, 0, curves.size() - 1)]
    )
    var depths := SaColorSpace.storage_depths()
    var depth: int = depths[clampi(depth_row, 0, depths.size() - 1)]
    var systems := SaColorSpace.storage_coordinates()
    var system: int = systems[clampi(coordinates_row, 0, systems.size() - 1)]
    var space := SaColorSpace.create(
        SaColorSpace.ID_CUSTOM,
        primaries.duplicate(),
        white,
        curve,
        depth as SaColorSpace.Depth,
        system as SaColorSpace.Coordinates
    )
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.with_depth(space.depth).matches(space):
            space.id = preset.id
            break
    # The values a profile file gave, unchanged, are that profile's, and carry
    # its description to the document's header.
    if profile != null and profile.space.with_depth(space.depth).matches(space):
        space.profile_name = profile.name
    return space
