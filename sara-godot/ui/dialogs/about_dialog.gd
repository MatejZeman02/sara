## About: the build, the engine, the GPU, the display and the modules, as text
## a bug report can carry.
##
## The same facts the boot header prints, on screen, because a desktop launch
## has no terminal to read them from and a report that cannot name its commit
## is a report nobody can act on. The window leads with the name and the
## version, keeps the machine's facts in a muted block under the tagline and
## folds the modules and the font licences away, because those are the long
## part and the one a painter reads least. `report_text()` is the whole of it as
## plain text, licence paths included, which the Copy button puts on the
## clipboard and a test reads: a bug report wants the paths the window leaves
## out.
##
## A second fold, "Built by", shows four portraits of the builders. The report
## does not carry them, because a bug report has no use for a portrait.
@tool
class_name SaAboutDialog
extends SaDialogWindow

const REPOSITORY_URL := "https://github.com/MatejZeman02/sara"

## The call the link makes, `OS.shell_open` in everything but a suite.
##
## A `Callable` rather than the engine call named at the press site so the suite
## can press the link and read the address it opened: a real press on the
## machine running the gate would put a browser on its painter's desktop.
## Test seam. A suite that replaces it puts `OS.shell_open` back.
static var opener: Callable = OS.shell_open

var heading: Label = null
var details: Label = null
var fold: FoldableContainer = null
var copy_button: Button = null
var repository_link: LinkButton = null
var built_by: SaBuiltByFold = null

var _modules: Label = null
var _fonts: Label = null


func _init() -> void:
    _init_dialog("AboutDialog", tr("About Sara"), Vector2i(560, 400), Vector2i(420, 300))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    heading = SaMake.label(column, "Title", heading_text())
    SaUI.size_text(heading, SaUI.fraction_of(22))
    SaMake.label(column, "Tagline", tr("GPU-first digital painting, GPLv3."))
    # A scroll view around the body, because the body is the one part that
    # grows: a module name each, a font licence each once the fold is open. On a
    # screen 1024 high it made the window taller than the room it had and the
    # buttons went under the bottom edge, and a screen shorter than that cannot
    # be helped by moving the window. The base fits the scroll to the host.
    var scroll := SaMake.scroll(column, "ReportScroll")
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scrolling_body = scroll
    var body := SaMake.column(scroll, "Body", 10)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    details = _wrapping_label(body, "Details")
    SaTheme.bind_font(details, "text_muted")
    fold = FoldableContainer.new()
    fold.name = "ModulesAndLicences"
    fold.title = tr("Modules and licences")
    fold.folded = true
    fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    fold.folding_changed.connect(_refit_after_layout)
    body.add_child(fold)
    var fold_body := SaMake.column(fold, "FoldBody", 8)
    _modules = _wrapping_label(fold_body, "Modules")
    _fonts = _wrapping_label(fold_body, "Fonts")
    # Under the licences, so opening it moves nothing a painter reads above it.
    built_by = SaBuiltByFold.new()
    built_by.folding_changed.connect(_refit_after_layout)
    body.add_child(built_by)
    # Outside the scroll, so a screen too short for the body still shows the
    # address, and only as wide as its text, so the whole row is not a link.
    repository_link = LinkButton.new()
    repository_link.name = "RepositoryLink"
    repository_link.text = REPOSITORY_URL
    repository_link.tooltip_text = tr("Open the repository in the browser.")
    repository_link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    repository_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    repository_link.pressed.connect(func() -> void: opener.call(REPOSITORY_URL))
    column.add_child(repository_link)

    var buttons := pinned_buttons(column)
    copy_button = SaMake.button(buttons, "CopyButton", tr("Copy Details"), tr("Everything above, as text for a bug report"))
    copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(report_text()))
    var close := SaMake.button(buttons, "CloseButton", tr("Close"))
    close.pressed.connect(hide)
    default_button = close


## Asks every wrapping label for its height again before the base reads the
## body's. The base asks the scroll's one child, and a label a level below it
## keeps the lines it last wrapped, which for a label laid out after it was
## built is the lines of a width of one character.
func fit_opening_size() -> void:
    for label: Label in [details, _modules, _fonts] + built_by.lines:
        label.update_minimum_size()
    super.fit_opening_size()


## The window was fitted to the body folded, so an open fold asks for the room
## it now needs, once the body has laid itself out again. A deferred call is not
## late enough: the fold sorts its children, and the body sorts the fold, in
## messages that queue behind it, so the labels still hold the lines of a width
## of one character and the window grew to the whole screen.
func _refit_after_layout(_is_folded: bool) -> void:
    if not is_inside_tree():
        return
    await get_tree().process_frame
    fit_opening_size()


## Re-read on every open: the modules can change at runtime and the display
## can move between screens.
func refresh() -> void:
    if details == null:
        return
    heading.text = heading_text()
    details.text = details_text()
    _modules.text = modules_text()
    _fonts.text = fonts_text()


## The whole report as plain text, the facts and then the repository's address.
## What Copy Details puts on the clipboard.
static func report_text() -> String:
    return facts_text() + "\n" + REPOSITORY_URL


## The name and the version, bare, the heading's text: "Sara 0.17.2". The
## build's commit and where it came from are in `details_text()`.
static func heading_text() -> String:
    return "Sara " + SaBuildInfo.version()


## What the window shows under the tagline, one fact a line: the build and then
## the engine, the renderer, the device, the display and the OS.
static func details_text() -> String:
    var lines := PackedStringArray(["Build: " + SaBuildInfo.describe(SaBuildInfo.read())])
    lines.append_array(machine_lines())
    return "\n".join(lines)


## The line of loaded modules, each with its version and the commit it was
## built from, or the sentence that says why there are none.
static func modules_line() -> String:
    var modules := module_entries()
    if modules.is_empty():
        return "Modules: none, so the toolbox is empty. Tools ship in sara-base-modules."
    return "Modules: " + ", ".join(modules)


## The fold's block of loaded modules, one a line, as the fonts are.
static func modules_text() -> String:
    var modules := module_entries()
    if modules.is_empty():
        return modules_line()
    return "Modules\n" + "\n".join(modules)


## "Sara Base Tools 1.0.0-alpha.1 f2cb63a" for each loaded module, its name, version
## and commit as its manifest gives them.
static func module_entries() -> PackedStringArray:
    var modules := PackedStringArray()
    for module_id: StringName in ModuleLoader.loaded_modules:
        var manifest: SaModuleManifest = ModuleLoader.manifest_of(module_id)
        modules.append("%s %s" % [manifest.name, manifest.version_and_commit()])
    return modules


## The font licences as the fold shows them, a family a line with its holder and
## its licence and no path, because a painter has no use for a `res://` file.
static func fonts_text() -> String:
    return "Fonts\n" + "\n".join(SaFonts.licence_lines(false))


## The facts, one per line, in the order the boot header prints them, every
## licence with the path of its file. The address that ends the report is not
## among them, the link shows it.
static func facts_text() -> String:
    var lines := PackedStringArray(["Sara " + SaBuildInfo.describe(SaBuildInfo.read())])
    lines.append_array(machine_lines())
    lines.append(modules_line())
    lines.append("Fonts: " + ", ".join(SaFonts.licence_lines()))
    return "\n".join(lines)


## The engine, the renderer, the device, the display and the OS, a line each.
static func machine_lines() -> PackedStringArray:
    var lines := PackedStringArray()
    var info := Engine.get_version_info()
    lines.append("Godot %s.%s.%s %s (%s)" % [info.major, info.minor, info.patch, info.status, str(info.hash).substr(0, 9)])
    lines.append(
        (
            "Renderer: %s %s, %s"
            % [SaBootHeader.driver_name(), RenderingServer.get_video_adapter_api_version(), SaBootHeader.rendering_method()]
        )
    )
    lines.append("Device: " + RenderingServer.get_video_adapter_name())
    var screen := DisplayServer.screen_get_size()
    lines.append("Display: %s, %dx%d at %.2fx" % [DisplayServer.get_name(), screen.x, screen.y, SaUI.scale()])
    lines.append("OS: %s %s" % [OS.get_name(), OS.get_version()])
    return lines


static func _wrapping_label(parent: Node, label_name: String) -> Label:
    var label := SaMake.label(parent, label_name)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return label
