## The New Module dialog: one name field and a Create button.
##
## A module is a folder holding a `module.gd`, and a painter who wants to write
## one should not have to copy the source to do it. This takes a name, writes the
## folder and its starter `module.gd` into the user's modules folder, and opens
## that folder so the new file is what the painter sees next. It is read in at
## the next start, the way every module in that folder is, so the hint says so.
##
## It does the writing itself rather than asking Main, because it needs no
## canvas or document: a module is a file on disk, and the user's folder is
## enough to reach it.
@tool
class_name NewModuleDialog
extends SaDialogWindow

## The call that shows the painter the new folder, `OS.shell_open` in everything
## but a suite, the seam the News pane's ask has for the same reason: a real
## call on the machine running the gate puts a file manager on the desktop.
## Test seam. A suite that replaces it puts `OS.shell_open` back.
static var opener: Callable = OS.shell_open

## Where the name is typed and the problem, if any, is read back.
var _name_field: LineEdit
var _status: Label


func _init() -> void:
    # Opens at its floor, because `fit_opening_size` grows a window to what its
    # column needs. At 340 high it opened with a blank band under its buttons.
    _init_dialog("NewModuleDialog", tr("New Module"), Vector2i(520, 240), Vector2i(420, 240))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    SaMake.label(column, "NameLabel", tr("Module name"))
    _name_field = SaMake.line_edit(column, "NameField", "", tr("for example, perlin noise"))
    # Unbound, because `text_submitted` hands the text and `_on_confirmed` reads
    # the field itself: bound bare, Enter in the field would be a call error and
    # create nothing.
    _name_field.text_submitted.connect(_on_confirmed.unbind(1))
    first_focus = _name_field

    # The hint scrolls when the host is shorter than it is, so the buttons stay
    # on it. It prints a folder, and how many lines a folder wraps to is the
    # machine's to say rather than this dialog's: a long folder outside `HOME`
    # wraps the hint far enough to put Cancel and Create under the 335 a 1280 by
    # 800 screen at a scale of 2 leaves below the bar, and a Font size of 1.5
    # does the same to a short one.
    var notes_view := SaMake.scroll(column, "NotesScroll")
    notes_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    # The bar's width is kept whether it shows or not, so the hint wraps at one
    # width. Otherwise it wraps under the bar while the dialog is at its floor and
    # at the whole width once the fit has made room, and a folder whose last word
    # breaks between the two opens the dialog a line taller than its column.
    notes_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
    notes_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = notes_view
    var notes := SaMake.column(notes_view, "Notes", 10)
    notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var folder := ModuleLoader.user_modules_path()
    var shown := from_home(folder, OS.get_environment("HOME"))
    var hint_text := tr("Creates a starter module in %s. Loaded when Sara next starts.") % shown
    var hint := SaMake.label(notes, "HintLabel", hint_text)
    # The whole path is a hover away, for a painter who has to type it somewhere.
    # A label ignores the pointer unless told otherwise, and shows no tooltip.
    hint.tooltip_text = folder
    hint.mouse_filter = Control.MOUSE_FILTER_PASS
    # Anywhere rather than at a space, because a folder has none to break at
    # and ran on under the right edge.
    hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
    SaTheme.bind_font(hint, "text_muted")
    # Outside the scroll, just above the buttons. Under the hint at the floor of
    # 240 high it sat below the fold, and an empty Create seemed to do nothing.
    _status = SaMake.label(column, "StatusLabel")
    _status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
    _status.visible = false
    SaTheme.bind_font(_status, "text_muted")

    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    var create_button := SaMake.button(buttons, "CreateButton", tr("Create"))
    create_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    create_button.pressed.connect(_on_confirmed)
    default_button = create_button


## Opens on a blank field rather than the last name, so a second module is not
## silently a rename of the first.
func reset() -> void:
    _name_field.text = ""
    _status.text = ""
    _status.visible = false


## *path* with the home folder *home* written "~", the way a shell prints it on
## Linux and macOS, or *path* whole when it does not start there or *home* is
## empty. The hint printed the painter's own home folder out in full, a long
## line of what they already know ahead of the part they need.
static func from_home(path: String, home: String) -> String:
    var root := home.trim_suffix("/")
    if root.is_empty():
        return path
    if path == root:
        return "~"
    if path.begins_with(root + "/"):
        return "~" + path.substr(root.length())
    return path


## The name the painter typed, trimmed.
func _requested_name() -> String:
    return _name_field.text.strip_edges()


## Letters with accents or diacritics folded to their base Latin letters, so
## names in languages outside ASCII keep their consonants and vowels in the
## folder and id.
static func _fold_to_base(text: String) -> String:
    if text.is_empty():
        return ""
    var ts := TextServerManager.get_primary_interface()
    if ts != null:
        return ts.strip_diacritics(text)
    return text


## The typed name as a folder and an id, the way the shipped modules spell one
## name two ways: the folder keeps hyphens and the id keeps underscores, so
## `perlin noise` becomes the folder `perlin-noise` and the id `perlin_noise`.
## The letters fold to base Latin letters first, so Czech and other accented
## names keep their letters. The id also never starts with a digit, so it stays
## an identifier if a student names it that way. The pair is empty when the
## name holds no word characters.
func _slug_and_id(raw: String) -> Array:
    var pattern := RegEx.new()
    if pattern.compile("[^a-z0-9]+") != OK:
        return ["", ""]
    var folded := _fold_to_base(raw)
    var slug := pattern.sub(folded.to_lower(), "-", true).trim_prefix("-").trim_suffix("-")
    if slug.is_empty():
        return ["", ""]
    var id := slug.replace("-", "_")
    if id[0] >= "0" and id[0] <= "9":
        id = "_" + id
    return [slug, id]


## The starter a student's first module is born with: an id and a register with
## nothing in it yet, the shape a module template takes.
func _template(id: String) -> String:
    return (
        "# A Sara module. Restart Sara after editing it to load the change.\n"
        + "extends SaModule\n"
        + "\n"
        + "\n"
        + "func get_id() -> StringName:\n"
        + '    return &"'
        + id
        + '"\n'
        + "\n"
        + "\n"
        + "func register(_ctx: SaContext) -> void:\n"
        + "    # Register a filter, a blend mode or a tool here, through _ctx.\n"
        + "    pass\n"
    )


func _on_confirmed() -> void:
    var pair := _slug_and_id(_requested_name())
    var slug: String = pair[0]
    var id: String = pair[1]
    if slug.is_empty():
        _say_problem(tr("Type a name first."))
        if _name_field.is_inside_tree():
            _name_field.grab_focus()
        return
    var dir_path := ModuleLoader.user_modules_path().path_join(slug)
    if DirAccess.dir_exists_absolute(dir_path):
        _say_problem(tr("A module named %s already exists.") % slug)
        return
    if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
        _say_problem(tr("Could not create %s.") % dir_path)
        return
    var file_path := dir_path.path_join("module.gd")
    var file := FileAccess.open(file_path, FileAccess.WRITE)
    if file == null:
        _say_problem(tr("Could not write %s.") % file_path)
        return
    file.store_string(_template(id))
    file.close()
    # A module is read in at the next start, and this is the folder it sits in.
    opener.call(dir_path)
    # The window closing alone would say nothing of what was made.
    var shown := from_home(ModuleLoader.user_modules_path(), OS.get_environment("HOME"))
    SaMessage.notice(tr("Created module %s in %s. Restart Sara to load it.") % [slug, shown])
    hide()


func _say_problem(message: String) -> void:
    _status.text = message
    _status.visible = true
    # The line was hidden and had no width, so the window is grown to take it a
    # frame later, when it does. Shown at the floor without it, the line would
    # push Cancel and Create under the bottom edge.
    if is_inside_tree():
        _fit_next_frame()
