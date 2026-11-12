## A page's path row: the path label over its two buttons, the label trimmed
## from its start, and the folder picker the Choose button opens.
##
## Out of `sa_page.gd`, because the row is the one kind of the page with a
## control of its own, a picker and a label that trims itself, and none of it
## reads the page. The page hands it the write a button makes and asks it to
## show a value, and that is the whole of what they share.
class_name SaPathRow
extends RefCounted


## The path label over its two buttons, the settings folder's row. *write* takes
## the chosen folder, or "" for Use Default, and *host_box* is where the picker
## opens.
##
## The path above the buttons rather than beside them, because the control
## column is not wide enough for a home directory and two buttons on one line
## and a path clipped to "/home/pai" says nothing.
static func make(write: Callable, host_box: Container) -> Control:
    var box := SaMake.column(null, "PathBox", 6)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var shown := PathLabel.new()
    shown.name = "PathLabel"
    shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(shown)
    # A turning row, so in a docker Use Default goes under Choose when the two
    # do not fit side by side, rather than widening the docker past its edge.
    var buttons := SaMake.turning_row(box, "PathButtons", SaTheme.GAP)
    var choose := SaMake.button(buttons, "ChooseButton", SaPage.translated("Choose..."))
    choose.pressed.connect(func() -> void: _choose(write, host_box))
    SaMake.button(buttons, "DefaultButton", SaPage.translated("Use Default")).pressed.connect(write.bind(""))
    return box


## Shows *value* in the row *control* that [method make] answered.
static func show(control: Control, value: String) -> void:
    var label := control.find_child("PathLabel", true, false) as PathLabel
    if label != null:
        label.show_path(value)


## The folder picker, asked for by *host_box* the way the Files page asks for
## it from the page. The platform's own where it has one, which a scenario
## answers through its `file_picker` step, and the row's value is writable
## through the binding as well.
static func _choose(write: Callable, host_box: Container) -> void:
    SaFilePicker.open(host_box, SaFilePicker.Mode.OPEN_DIR, PackedStringArray(), write)


## The path row's label, trimmed from its start with an ellipsis so the folder's
## own name stays in sight, and the whole path in its tooltip. The engine
## trims only from the end, which kept "/home/pai" and dropped the part a painter
## reads.
class PathLabel:
    extends Label

    ## What the row holds, of which `text` shows as much as fits.
    var full_path: String = ""

    func _init() -> void:
        clip_text = true
        mouse_filter = Control.MOUSE_FILTER_PASS
        resized.connect(_trim)

    func show_path(path: String) -> void:
        full_path = path
        tooltip_text = path
        _trim()

    ## Drops characters from the start until the rest and the ellipsis fit. A
    ## label with no width yet, off the tree, shows the path whole.
    func _trim() -> void:
        var room := size.x
        if room <= 0.0 or _width(full_path) <= room:
            text = full_path
            return
        var cut := 1
        while cut < full_path.length() and _width("…" + full_path.substr(cut)) > room:
            cut += 1
        text = "…" + full_path.substr(cut)

    func _width(shown: String) -> float:
        return get_theme_font(&"font").get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size(&"font_size")).x
