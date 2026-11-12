## The Modules window: every module this start found down the left, and the
## chosen module's page on the right.
##
## A module's row in Modules > Active Modules opens it on that module. The page
## says what the module's `manifest.cfg` says of it, its name, version and the
## commit it was built from, its authors, licence and website and its sentence,
## and whether it runs, is off or was refused, and why. Under that is its
## `README.md` drawn by `SaMarkdown`, the manual's renderer, so a module's
## author writes one page that reads the same on GitHub and in Sara. A module
## of a repository of several, the base modules' `kaleidoscope`, has a README
## in its own folder or shows the repository's.
##
## The switch stays on Preferences > Modules, because a module is switched on or
## off for the next start and that page says so. The window offers it in the
## button beside the page, which opens Preferences there.
@tool
class_name SaModulesWindow
extends SaDialogWindow

## The file a module's folder or its repository's holds to be shown.
const README := "README.md"

## The least the window is made, in logical units, the manual's floor, since
## both are a list and a scrolling page.
const FLOOR := SaManualWindow.FLOOR

## The module list down the left, one row per module, by its name.
var module_list: ItemList = null
## The chosen module's page.
var page_view: RichTextLabel = null
## The modules as `SaModulesPage.entries()` gives them, in the list's order.
var entries: Array[Dictionary] = []
## The row showing, or -1 before the first module is turned to.
var current: int = -1
## The page drawn last, held because it holds the pictures read from their
## files, which the resource cache keeps only while something does.
var drawn: SaMarkdown = null


func _init() -> void:
    _init_dialog("ModulesWindow", tr("Modules"), Vector2i(960, 680), FLOOR)
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    var row := SaMake.row(column, "Row", SaTheme.GAP)
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL

    module_list = ItemList.new()
    module_list.name = "ModuleRows"
    # As wide as its longest name, measured again on every reshape, as the
    # manual's page list is.
    module_list.auto_width = true
    module_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    module_list.item_selected.connect(show_module)
    row.add_child(module_list)

    page_view = RichTextLabel.new()
    page_view.name = "ModulePage"
    page_view.bbcode_enabled = true
    page_view.scroll_active = true
    page_view.selection_enabled = true
    page_view.focus_mode = Control.FOCUS_CLICK
    page_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page_view.meta_clicked.connect(_on_link)
    page_view.resized.connect(_draw_page)
    row.add_child(page_view)
    SaMarkdown.set_faces(page_view)

    var buttons := pinned_buttons(column)
    var switch := SaMake.button(
        buttons,
        "SwitchModulesButton",
        tr("Turn Modules On or Off..."),
        tr("Opens Preferences, Modules, where a module is switched on or off for the next start.")
    )
    switch.pressed.connect(_on_switch)
    default_button = SaMake.button(buttons, "CloseModulesButton", tr("Close"))
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(hide)


## Shows the window held under *parent*, built on first ask, with the module
## list read again, turned to *module_id*'s page, or kept on the page it showed
## when the id is empty or no module has it. `MainDialogs` asks this when a
## module's row in Modules > Active Modules is pressed.
static func open_in(parent: Node, module_id: StringName = &"") -> SaModulesWindow:
    var window := parent.get_node_or_null("ModulesWindow") as SaModulesWindow
    if window == null:
        window = SaModulesWindow.new()
        parent.add_child(window)
    window.fill(module_id)
    window.popup_centered()
    return window


## The list read again from the loader, since a reload of the painter's
## modules changes it, and the page turned to *module_id*.
func fill(module_id: StringName = &"") -> void:
    var was := String(entries[current]["id"]) if current >= 0 and current < entries.size() else ""
    entries = SaModulesPage.entries()
    module_list.clear()
    for entry: Dictionary in entries:
        module_list.add_item(String(entry["name"]))
    var wanted := String(module_id) if not String(module_id).is_empty() else was
    current = -1
    show_module(maxi(index_of(wanted), 0))


## The row of *module_id*, or -1.
func index_of(module_id: String) -> int:
    for index: int in entries.size():
        if String(entries[index]["id"]) == module_id:
            return index
    return -1


## Turns to the module in row *index*.
func show_module(index: int) -> void:
    if index < 0 or index >= entries.size():
        return
    current = index
    if not module_list.is_selected(index):
        module_list.select(index)
    _draw_page()
    page_view.scroll_to_line(0)


## The facts a capture's dump carries, or an empty dictionary before the
## window was first opened: the modules listed, the one showing, what the
## painter reads on its page, the README it came from, the pictures drawn and
## those only named, anything that did not resolve and the HTML tags the README
## wrote with what each became.
static func capture_state(root: Window) -> Dictionary:
    var window := root.find_child("ModulesWindow", true, false) as SaModulesWindow
    if window == null:
        return {}
    var showing := window.entries[window.current] if window.current >= 0 else {}
    var said := window.drawn
    return {
        "visible": window.visible,
        "modules": window.entries.map(func(entry: Dictionary) -> String: return String(entry["id"])),
        "current": String(showing.get("id", "")),
        "readme": readme_of(String(showing.get("id", ""))),
        "text": window.page_view.get_parsed_text(),
        "pictures": Array(said.pictures) if said != null else [],
        "web_pictures": Array(said.web_pictures) if said != null else [],
        "problems": Array(said.problems) if said != null else [],
        "tags": said.tags if said != null else {},
    }


func _on_ui_font_scale_changed(font_scale: float) -> void:
    super(font_scale)
    _draw_page()


func _draw_page() -> void:
    if current < 0 or current >= entries.size() or page_view == null:
        return
    SaMarkdown.set_faces(page_view)
    var width := int(page_view.size.x) - SaUI.px(24)
    var page := render(entries[current], width)
    drawn = page["markdown"]
    page_view.text = String(page["bbcode"])


func _on_switch() -> void:
    EventBus.settings_page_requested.emit(SaModulesPage.TITLE)


## A link to the web opens the browser. One to a file of the module, a
## changelog or a licence, opens it in the program the desktop gives it.
func _on_link(meta: Variant) -> void:
    var target := str(meta)
    if SaMarkdown.is_web(target):
        SaMenuCommands.open_url(target)
        return
    var readme := readme_of(String(entries[current]["id"])) if current >= 0 else ""
    var path := readme.get_base_dir().path_join(target.get_slice("#", 0))
    if not readme.is_empty() and FileAccess.file_exists(path):
        OS.shell_open(ProjectSettings.globalize_path(path))


## The README a module's page shows: its folder's own, or the one of the
## repository its folder sits in, or "" when there is neither. The skeleton's
## folder is the whole project, and no README sits there.
static func readme_of(module_id: String) -> String:
    var folder := String(ModuleLoader.module_dirs.get(StringName(module_id), ""))
    if folder.is_empty() or folder == "res://":
        return ""
    for candidate: String in [folder, folder.get_base_dir()]:
        var path := candidate.path_join(README)
        if FileAccess.file_exists(path):
            return path
    return ""


## The manifest of *module_id*: the loader's, or read from its folder for a
## module the loader filed no manifest for, which a refusal before the module
## was made is.
static func manifest_for(module_id: String) -> SaModuleManifest:
    var manifest := ModuleLoader.manifest_of(StringName(module_id))
    if manifest != null:
        return manifest
    var folder := String(ModuleLoader.module_dirs.get(StringName(module_id), ""))
    return SaModuleManifest.read(folder) if not folder.is_empty() else null


## The page of *entry*, one of `SaModulesPage.entries()`, as BBCode with
## pictures no wider than *picture_width*: `bbcode`, and `markdown`, the
## `SaMarkdown` its README was drawn with.
static func render(entry: Dictionary, picture_width: int = 0) -> Dictionary:
    var module_id := String(entry["id"])
    var manifest := manifest_for(module_id)
    var heading := SaUI.font_size_for(SaUI.fraction_of(SaMarkdown.HEADING_SIZES[1]))
    var blocks := PackedStringArray(["[font_size=%d][b]%s[/b][/font_size]" % [heading, SaMarkdown.escape(String(entry["name"]))]])
    if manifest != null and not manifest.description.is_empty():
        blocks.append(SaMarkdown.escape(manifest.description))
    blocks.append(_facts(entry, manifest))
    var readme := readme_of(module_id)
    var markdown := SaMarkdown.new(readme.get_base_dir(), picture_width, false)
    if readme.is_empty():
        blocks.append(SaMarkdown.escape(TranslationServer.translate("This module has no README.")))
    else:
        blocks.append("[font_size=%d] [/font_size]" % SaUI.px(4))
        blocks.append(markdown.to_bbcode(FileAccess.get_file_as_string(readme)))
    return {"bbcode": "\n\n".join(blocks), "markdown": markdown}


## The manifest's facts and the module's state as a table of two columns.
static func _facts(entry: Dictionary, manifest: SaModuleManifest) -> String:
    var rows: Array[PackedStringArray] = []
    if manifest != null:
        rows.append(PackedStringArray([TranslationServer.translate("Version"), manifest.version_and_commit()]))
        if not manifest.authors.is_empty():
            rows.append(PackedStringArray([TranslationServer.translate("Authors"), ", ".join(manifest.authors)]))
        if not manifest.license.is_empty():
            rows.append(PackedStringArray([TranslationServer.translate("Licence"), manifest.license]))
    rows.append(PackedStringArray([TranslationServer.translate("State"), _state_of(entry)]))
    var from := TranslationServer.translate("Built into Sara")
    if entry["origin"] != "packaged":
        from = String(ModuleLoader.module_dirs.get(StringName(entry["id"]), ""))
    rows.append(PackedStringArray([TranslationServer.translate("From"), from]))
    var out := "[table=2]"
    for row: PackedStringArray in rows:
        out += "[cell padding=0,2,16,2][b]%s[/b][/cell][cell]%s[/cell]" % [SaMarkdown.escape(row[0]), SaMarkdown.escape(row[1])]
    if manifest != null and not manifest.website.is_empty():
        var site := SaMarkdown.escape(manifest.website)
        out += (
            "[cell padding=0,2,16,2][b]%s[/b][/cell][cell][url=%s]%s[/url][/cell]"
            % [TranslationServer.translate("Website"), site, site]
        )
    return out + "[/table]"


## Whether the module runs at this start, and why not when it does not.
static func _state_of(entry: Dictionary) -> String:
    match String(entry["state"]):
        "off":
            return TranslationServer.translate("Off at this start, %s.") % entry["reason"]
        "refused":
            return TranslationServer.translate("Refused at this start, %s.") % entry["reason"]
    return TranslationServer.translate("Loaded")
