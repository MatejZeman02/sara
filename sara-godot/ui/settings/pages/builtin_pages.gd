## The eleven built-in Preferences pages' registration: `register_builtins` with
## the factory of each page, and [PageParts], the column the pages made of
## several parts are drawn in.
##
## It was the tail of `SaSettingsWindow`, which keeps the list, `FIXED_PAGES`,
## and the sidebar that draws what a registry holds. This is the one place that
## says how each of the eleven is made, so a page moves between groups or into
## parts here, and a row between the parts of a page in the part's own class.
## `SaSettingsWindow.register_builtins` is the line that calls it.
class_name SaBuiltinPages
extends RefCounted

## The pages built once and kept for the window's life rather than built on
## every open, by their titles: the two whose build held a painter's frame over
## a tenth of a second. See [SaSettingsKeptPages].
const KEPT_PAGES: Array[String] = ["Keyboard shortcuts", "Canvas and colour"]


## Registers the eleven through the public door, each under its group, and hands
## the registry back, making one when it is given none, which is how a window
## built off the tree by a suite goes through the door as well. Asked twice of
## one registry it registers nothing the second time, so the window may ask
## whatever its maker did.
##
## A static rather than an instance method, and its page factories below the
## same, because a registry may be shared: a module registers into the host's
## registry once at boot, and the factory a window later calls has to answer for
## whichever window asks it rather than for whichever window happened to
## register it (hard rule 6).
##
## Two of the ten are several pages drawn as one, see [PageParts]. Which rows
## each part holds is its own class's, so a row moves between pages there and
## not here.
static func register_builtins(registry: SaUIRegistry) -> SaUIRegistry:
    if registry == null:
        registry = SaUIRegistry.new()
    var factories := {
        SaSettingsWindow.INTERFACE_PAGE: [&"interface", _interface_page],
        SaDockersPage.TITLE: [&"interface", _dockers_page],
        "Keyboard shortcuts": [&"interface", _shortcuts_page],
        SaLanguagesPage.TITLE: [&"interface", _languages_page],
        "Brushes": [&"painting", _brushes_page],
        "Pen and tablet": [&"painting", func(_window: Node) -> Control: return SaTabletPage.new()],
        "Canvas and colour": [&"painting", func(_window: Node) -> Control: return SaDisplayPage.new()],
        "Files": [&"files_and_system", func(_window: Node) -> Control: return SaFilesPage.new()],
        "Performance": [&"files_and_system", func(_window: Node) -> Control: return SaPerformancePage.new()],
        "Recorder": [&"files_and_system", func(_window: Node) -> Control: return SaRecorderPage.new()],
        SaModulesPage.TITLE: [&"files_and_system", func(_window: Node) -> Control: return SaModulesPage.new()],
    }
    for page_title: String in SaSettingsWindow.FIXED_PAGES:
        var page_id := StringName(page_title.to_snake_case())
        if not registry.has_settings_page(page_id):
            var made: Array = factories[page_title]
            registry.register_settings_page(page_id, page_title, made[1], &"", made[0])
    return registry


## Interface: the size and font, the colour theme with Edit colours… beside it,
## then General's pen door, undo depth, advanced options and what shows at start.
## The Workspace part asks the window to build the page again when its font changes.
static func _interface_page(window: Node) -> Control:
    var workspace := SaWorkspacePage.new()
    var edit := Callable()
    if window != null and window.has_method("rebuild_current_page"):
        workspace.rebuild_requested.connect(Callable(window, "rebuild_current_page"))
    if window != null and window.has_method("show_colours"):
        edit = Callable(window, "show_colours")
    var pen := Callable(window, "show_page").bind("Pen and tablet", &"calibration") if edit.is_valid() else Callable()
    return PageParts.new([workspace, SaColorThemesPage.ThemeChoice.new(edit), SaGeneralPage.new(pen)])


## Brushes: the ten slots and the pop-up palette's switch, then the Krita
## import, the one button the Presets page held.
static func _brushes_page(_window: Node) -> Control:
    return PageParts.new([SaBrushSlotsPage.new(), SaBrushPresetsPage.new()])


## Layouts and dockers asks the window for a docker's part, since the window
## owns the page area it is drawn in.
static func _dockers_page(window: Node) -> Control:
    var page := SaDockersPage.new()
    if window != null and window.has_method("show_docker"):
        page.docker_wanted.connect(Callable(window, "show_docker"))
    return page


## The Keyboard Shortcuts page names a module's tool the way its own toolbox
## button does, a module's filter the way its menu row does, and a command by
## its title, from the three registries the window was handed.
##
## A page the window builds to show builds its rows a slice a frame, and one the
## search builds to index builds them all at once.
static func _shortcuts_page(window: Node) -> Control:
    if window == null:
        return SaShortcutsPage.new()
    return SaShortcutsPage.new(
        window.get("tools_registry") as SaToolRegistry,
        window.get("filters_registry") as SaFilterRegistry,
        window.get("commands_registry") as SaCommandRegistry,
        bool(window.get("building_to_show"))
    )


## Languages lists the catalogues of the registry the window was handed, and
## asks the window to draw it again once a pick has switched the language.
static func _languages_page(window: Node) -> Control:
    var registry: SaTranslationRegistry = null
    if window != null:
        registry = window.get("translations_registry") as SaTranslationRegistry
    var languages := SaLanguagesPage.new(registry)
    if window != null and window.has_method("rebuild_current_page"):
        languages.rebuild_requested.connect(Callable(window, "rebuild_current_page"))
    return languages


## One page of the sidebar made of several pages, each declared by its own
## class and stacked in one column with the gap a page keeps between its
## sections, so the parts read as one page.
##
## The Interface page is three parts and Brushes two. A part keeps its own class
## because each holds state of its own, and because a row that moves between the
## classes leaves this list unchanged. The search, the row report and a door's
## landing walk a page by its rows, so none knows a page is in parts. Every part
## is a SettingsPage, numbered from the second, so a dump names each the same.
class PageParts:
    extends VBoxContainer

    ## The column a docker or a dialog finds the parts in.
    const NODE_NAME := &"PageParts"

    var parts: Array[Control] = []

    func _init(page_parts: Array[Control]) -> void:
        name = NODE_NAME
        SaSettingsRows.setup_page(self)
        for part: Control in page_parts:
            part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            add_child(part, true)
            parts.append(part)

    ## The part of class *script*, or null for none, for a suite that reads one
    ## part's own members.
    func part_of(script: Script) -> Control:
        for part: Control in parts:
            if is_instance_of(part, script):
                return part
        return null
