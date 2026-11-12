## The New Document dialog's templates: the ones Sara ships, the ones a painter
## saved, and the file each saved one is.
##
## A template is a record of rows, and it names only the rows it fills. One that
## names no colour space leaves the space the dialog opened on, which is the
## painter's default, so a print template does not undo a preference. The keys
## are the dialog's own words, `size`, `dpi`, `space` and `background`, the last
## in `SaDocumentBackground`'s shape. A saved template names every row, its
## space as the `.sad` header writes one, so a gamma chosen on the slider
## survives the file.
##
## A class of its own rather than lines in the dialog, because the dialog is near
## the length the run fails at, and the templates are one thing: which records
## there are, and where the saved ones live. It is handed the rows' values and
## never the dialog, so it holds nothing of the class it was cut from.
class_name NewDocumentTemplates
extends RefCounted

const ID := "id"
const LABEL := "label"
const SIZE := "size"
const DPI := "dpi"
## A preset's id, which a shipped template names a space by.
const SPACE := "space"
## A space as `SaColorSpace.to_header` writes it, which a saved one carries.
const HEADER := "color_space"
const BACKGROUND := "background"

## Where the saved templates go under the data root, beside `brush_presets`.
const FOLDER := "templates"
const EXTENSION := ".json"

## A saved template's id is this and its file's name, so it can never be taken
## for a shipped one, whatever the painter called it.
const SAVED_PREFIX := "saved:"

## The ground a painting on canvas is laid on, primed rather than bleached.
const PRIMED := Color(0.94, 0.92, 0.87)

## What Sara ships, in the order the row lists them. Picked against Krita's
## templates and Photoshop's presets: the screen and video sizes both open on,
## the two ISO pages print work starts from, a comic page at the 600 dpi line
## art is drawn at, a square for a sketch, and the two linear documents a
## painter otherwise sets up by hand, a painting on canvas and a texture.
const SHIPPED: Array[Dictionary] = [
    {
        ID: "screen",
        LABEL: "Screen, 1920 × 1080 px",
        SIZE: Vector2i(1920, 1080),
        DPI: 72.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    {
        ID: "uhd",
        LABEL: "4K UHD, 3840 × 2160 px",
        SIZE: Vector2i(3840, 2160),
        DPI: 72.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    {
        ID: "a4",
        LABEL: "A4 portrait, 300 dpi",
        SIZE: Vector2i(2480, 3508),
        DPI: 300.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    {
        ID: "a3",
        LABEL: "A3 portrait, 300 dpi",
        SIZE: Vector2i(3508, 4961),
        DPI: 300.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    # A US comic page with its bleed, 6.875 by 10.4375 inches.
    {
        ID: "comic",
        LABEL: "Comic page, 600 dpi",
        SIZE: Vector2i(4125, 6263),
        DPI: 600.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    {
        ID: "sketch",
        LABEL: "Square, 2048 × 2048 px",
        SIZE: Vector2i(2048, 2048),
        DPI: 72.0,
        BACKGROUND: {"kind": &"colour", "color": Color.WHITE, "ground": &""},
    },
    # Ten by eight inches, the canvas board a painter buys most.
    {
        ID: "canvas",
        LABEL: "Painting on canvas, linear",
        SIZE: Vector2i(3000, 2400),
        DPI: 300.0,
        SPACE: &"linear_srgb",
        BACKGROUND: {"kind": &"colour", "color": PRIMED, "ground": &"canvas"},
    },
    {
        ID: "texture",
        LABEL: "Texture, 2048 × 2048 px, linear",
        SIZE: Vector2i(2048, 2048),
        DPI: 72.0,
        SPACE: &"linear_srgb",
        BACKGROUND: {"kind": &"transparent", "color": Color.WHITE, "ground": &""},
    },
]

## The folder the saved templates are read from and written to. A test points
## this somewhere disposable and puts it back, the only reason it is a variable.
static var root: String = default_root()


## The folder under the data root when no test moved it.
static func default_root() -> String:
    return SaDataRoot.path(FOLDER)


## Every template, the shipped ones and then the saved ones by name, each
## with its label in the painter's language.
static func listed() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for shipped: Dictionary in SHIPPED:
        var record := shipped.duplicate(true)
        record[LABEL] = SaPage.translated(String(shipped[LABEL]))
        out.append(record)
    out.append_array(saved())
    return out


## The Template row's entries for *records*.
static func choices_of(records: Array[Dictionary]) -> Array:
    return records.map(func(record: Dictionary) -> Dictionary: return {"id": record[ID], "label": record[LABEL]})


## The record of *records* called *id*, empty when none is.
static func find_in(records: Array[Dictionary], id: String) -> Dictionary:
    for record: Dictionary in records:
        if String(record[ID]) == id:
            return record
    return {}


## Whether *id* is a template the painter saved, which is the only kind that
## can be deleted.
static func is_saved(id: String) -> bool:
    return id.begins_with(SAVED_PREFIX)


## The space *record* names, or null when it names none. A shipped template
## names a preset and no depth, so it keeps *depth*, the one the row shows.
static func space_of(record: Dictionary, depth: int) -> SaColorSpace:
    if record.has(HEADER):
        var header: Dictionary[String, Variant] = {"color_space": record[HEADER]}
        return SaColorSpace.from_header(header)
    if not record.has(SPACE):
        return null
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.id == StringName(record[SPACE]):
            return preset.with_depth(depth as SaColorSpace.Depth)
    return null


## Whether every row *record* names still says what the dialog's rows say,
## the *size*, the *dpi*, the *space* and the *background* they describe. The
## colour is compared as the swatch shows it, so a file's rounding is not a
## change the painter made.
static func matches(record: Dictionary, size: Vector2i, dpi: float, space: SaColorSpace, background: Dictionary) -> bool:
    if record.has(SIZE) and record[SIZE] != size:
        return false
    if record.has(DPI) and not is_equal_approx(float(record[DPI]), dpi):
        return false
    var named := space_of(record, space.depth)
    if named != null and not named.matches(space):
        return false
    if not record.has(BACKGROUND):
        return true
    var want: Dictionary = record[BACKGROUND]
    var have := background
    if StringName(want[SaDocumentBackground.KIND]) != have[SaDocumentBackground.KIND]:
        return false
    if have[SaDocumentBackground.KIND] == SaDocumentBackground.TRANSPARENT:
        return true
    var colour: Color = want[SaDocumentBackground.COLOR]
    return (
        colour.to_html(false) == (have[SaDocumentBackground.COLOR] as Color).to_html(false)
        and StringName(want[SaDocumentBackground.GROUND]) == have[SaDocumentBackground.GROUND]
    )


## The dialog's rows, the *size*, the *dpi*, the *space* and the
## *background* they describe, as a saved template holds them.
static func record_of(size: Vector2i, dpi: float, space: SaColorSpace, background: Dictionary) -> Dictionary:
    return {SIZE: size, DPI: dpi, HEADER: space.to_header(), BACKGROUND: background}


## Every saved template under [member root], sorted by name. A file that is not
## one is passed over with a warning rather than taking the row down with it.
static func saved() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if not DirAccess.dir_exists_absolute(root):
        return out
    var files := Array(DirAccess.get_files_at(root)).filter(func(file: String) -> bool: return file.ends_with(EXTENSION))
    files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
    for file: String in files:
        var record := _read(root.path_join(file))
        if record.is_empty():
            push_warning("NewDocumentTemplates: %s is not a template, passing over it." % file)
            continue
        record[ID] = SAVED_PREFIX + file.get_basename()
        out.append(record)
    return out


## The name of the saved template whose file *wanted* would write, empty when
## no file holds that name yet. Asked of the file and not of the name typed,
## because two names the sanitiser folds to one stem, "a/b" and "a:b", write
## one file. A file that is no readable template answers its stem, since a
## save would still write over it.
static func taken_by(wanted: String) -> String:
    var stem := SaPresetStore.sanitize_name(wanted)
    if stem.is_empty():
        return ""
    var path := root.path_join(stem + EXTENSION)
    if not FileAccess.file_exists(path):
        return ""
    return String(_read(path).get(LABEL, stem))


## Writes *record* as the template *wanted*, over one of that name, and
## answers its id, or empty when the name holds nothing a file can be called
## or the file could not be written.
static func save(wanted: String, record: Dictionary) -> String:
    var stem := SaPresetStore.sanitize_name(wanted)
    if stem.is_empty():
        return ""
    DirAccess.make_dir_recursive_absolute(root)
    var file := FileAccess.open(root.path_join(stem + EXTENSION), FileAccess.WRITE)
    if file == null:
        push_warning("NewDocumentTemplates: could not write %s (%s)." % [stem, error_string(FileAccess.get_open_error())])
        return ""
    var size: Vector2i = record[SIZE]
    var background: Dictionary = record[BACKGROUND]
    var colour: Color = background[SaDocumentBackground.COLOR]
    var written := {
        LABEL: wanted.strip_edges(),
        SIZE: [size.x, size.y],
        DPI: float(record[DPI]),
        HEADER: record[HEADER],
        BACKGROUND:
        {
            "kind": String(background[SaDocumentBackground.KIND]),
            "color": [colour.r, colour.g, colour.b],
            "ground": String(background[SaDocumentBackground.GROUND]),
        },
    }
    file.store_string(JSON.stringify(written, "  ", false, true))
    file.close()
    return SAVED_PREFIX + stem


## Moves the saved template *id* to the system trash, as a file manager would,
## and answers whether it went. A shipped template is not a file and stays.
static func delete(id: String) -> bool:
    if not is_saved(id):
        return false
    var path := root.path_join(id.trim_prefix(SAVED_PREFIX) + EXTENSION)
    if not FileAccess.file_exists(path):
        return false
    return OS.move_to_trash(ProjectSettings.globalize_path(path)) == OK


## The record the file at *path* holds in the shape [constant SHIPPED] is,
## empty when it holds no size.
static func _read(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary or not (parsed as Dictionary).get(SIZE) is Array:
        return {}
    var raw: Dictionary = parsed
    var size: Array = raw[SIZE]
    if size.size() < 2:
        return {}
    var record := {
        LABEL: String(raw.get(LABEL, path.get_file().get_basename())),
        SIZE: Vector2i(int(size[0]), int(size[1])),
    }
    if raw.has(DPI):
        record[DPI] = float(raw[DPI])
    if raw.get(HEADER) is Dictionary:
        record[HEADER] = SaTyped.strings(raw[HEADER])
    if raw.get(BACKGROUND) is Dictionary:
        var background: Dictionary = raw[BACKGROUND]
        var channels: Array = background.get("color", [1.0, 1.0, 1.0])
        record[BACKGROUND] = {
            SaDocumentBackground.KIND: StringName(str(background.get("kind", SaDocumentBackground.COLOUR))),
            SaDocumentBackground.COLOR: Color(float(channels[0]), float(channels[1]), float(channels[2])),
            SaDocumentBackground.GROUND: StringName(str(background.get("ground", ""))),
        }
    return record


## The row under Template: a name, Save as template, and Delete, which only
## a saved template can be.
class SaveRow:
    extends HBoxContainer

    var name_field: LineEdit = null
    var save_button: Button = null
    var delete_button: Button = null

    ## *saving* is called with the typed name, *deleting* with nothing.
    func _init(saving: Callable, deleting: Callable) -> void:
        name = "TemplateSaver"
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_theme_constant_override("separation", SaUI.px(6))
        name_field = LineEdit.new()
        name_field.name = "TemplateName"
        name_field.placeholder_text = SaPage.translated("Name")
        name_field.custom_minimum_size.x = SaUI.px(100)
        name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_field.text_submitted.connect(func(_text: String) -> void: saving.call(name_field.text))
        add_child(name_field)
        save_button = Button.new()
        save_button.name = "SaveTemplate"
        save_button.text = SaPage.translated("Save")
        save_button.tooltip_text = SaPage.translated("Save these settings as a template with this name.")
        save_button.pressed.connect(func() -> void: saving.call(name_field.text))
        add_child(save_button)
        delete_button = Button.new()
        delete_button.name = "DeleteTemplate"
        delete_button.text = SaPage.translated("Delete")
        delete_button.tooltip_text = SaPage.translated("Move the selected template to the trash.")
        delete_button.pressed.connect(deleting)
        add_child(delete_button)
