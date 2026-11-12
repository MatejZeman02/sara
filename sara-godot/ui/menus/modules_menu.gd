## The Modules menu: what is loaded, what the loaded things offer to do, and
## last, under Develop, the rows for someone writing a module or letting a
## script in.
##
## Named for what it lists. "Extensions" was a second word for the same concept
## the whole loader, the API and the docs call a module, and the menu underneath
## it then said "Active Submodules", which was a third.
##
## The action list is Krita's Tools > Scripts: a module ships an action that has
## nowhere else to live, and this is where it appears, under the name of the
## module that registered it. Nothing here by default, and that is the intended
## state rather than a stub, because every built-in command already has a home.
##
## **Develop holds the developer's rows**, rather than scattering them through
## Filter and Help, where a painter reads past them every time and one of them
## opens a port from the menu a painter opens for help. It is a section at the
## end of this menu, so every row about writing a module or
## letting a script in is under one heading here and none is in Filter or Help.
class_name SaModulesMenu
extends SaMenu

## Menu ids for module-registered actions start here, high enough that no menu's
## hand-assigned ids can collide with them.
const ACTION_ID_BASE: int = 900

## The row that opens the user's modules folder.
const ID_OPEN_USER_FOLDER: int = 800

## The row that starts a module from scratch: it opens the New Module dialog,
## which writes a starter into the user's folder and points the painter there.
const ID_NEW_MODULE: int = 801

## The row that puts down every module from the user's folders and reads them
## again, so a painter writing a module sees an edit without a restart. One row
## rather than one per module, because what is wanted is one entry and a painter
## editing a module wants the folder as it now is, new modules and fixed
## refusals included.
const ID_RELOAD: int = 802

## The four rows of the Develop section. Their ids count on from the three
## above, because an id belongs to the menu it was minted in.
const ID_RELOAD_SHADERS: int = 803
const ID_COPY_PROMPT: int = 804
## Local Server, a tick while a door listens in this Sara.
const ID_LOCAL_SERVER: int = 805
const ID_DOCUMENTATION: int = 806

## The row under the list that opens Preferences > Modules, where a module is
## switched on or off for the next start.
const ID_SWITCH_MODULES: int = 807

## The Develop section's rows, in the order `_add_develop_rows` draws them.
const DEVELOP_ROWS: Array = [
    [ID_DOCUMENTATION, &"help_documentation"],
    [ID_NEW_MODULE, &"modules_new"],
    [ID_OPEN_USER_FOLDER, &"modules_open_folder"],
    [ID_RELOAD, &"modules_reload"],
    [ID_RELOAD_SHADERS, &"modules_reload_shaders"],
    [ID_COPY_PROMPT, &"filter_copy_prompt"],
    [ID_LOCAL_SERVER, &"help_connect_agent"],
]

## The documentation on the public repository, where the manual's pages read
## with their pictures and the source they describe sits beside them.
const DOCUMENTATION_URL := SaAboutDialog.REPOSITORY_URL + "/tree/main/sara-godot/manual"

## The contract a language model is handed, beside the generator that writes
## the kernel around a pixel function. A committed file rather than a string
## in this class, because it is prose about a language and it is edited by
## whoever changes that language, not by whoever changes this menu.
const PROMPT_PATH := "res://core/custom-shader/kernel_prompt.txt"

## Where the module rows themselves start. They do nothing when pressed, and
## each still needs an id of its own: a `PopupMenu` took -1 for every one of
## them, and `SaChoicePopup` keys a row by its id, so a shared id would be one
## row.
const MODULE_ROW_BASE: int = 700

## The row that opens the Active Modules list beside the menu.
const ID_ACTIVE_MODULES: int = 808

## The list the Active Modules row opens beside the menu, one for the menu and
## filled again on every open. Read by the suites and the harness, which press
## its rows.
var module_list: ModuleList = null


## The modules as a list of their own, beside the menu. A menu of its own
## because it is one: rows with hints, tooltips and dims, a press that closes it
## and an id that says what was pressed. Its presses go back to the Modules
## menu's handler, which owns what a module row's id means. Its popup is the
## Modules menu's child list, so it opens beside the row with the menu still
## open, and a row picked from it closes both.
class ModuleList:
    extends SaMenu

    ## The module each row of the list stands for: row id -> module id.
    var row_modules: Dictionary[int, StringName] = {}

    var _press_back: Callable

    func _init(list_popup: SaChoicePopup, pressed: Callable) -> void:
        super(list_popup)
        _press_back = pressed

    # Loaded rows at full strength, refusals dimmed with their reason, each
    # saying at its right where the module came from.
    #
    # **No row carries a tick box.** It said unticking unloaded the module and
    # went back on a press, a control that lied. A module is switched on or off
    # for the next start on Preferences > Modules, which the row under the list
    # opens. A press on a module's row opens the Modules window on its page,
    # which offers the switch beside it.
    func _add_items() -> void:
        row_modules.clear()
        var row_id := MODULE_ROW_BASE
        for module_id: StringName in ModuleLoader.loaded_modules:
            var mod: SaModule = ModuleLoader.loaded_modules[module_id]
            _add_module_row(row_id, mod.get_name(), module_id, false)
            row_id += 1
        for module_id: StringName in ModuleLoader.failed_modules:
            _add_module_row(row_id, "%s: %s" % [module_id, ModuleLoader.failed_modules[module_id]], module_id, true)
            row_id += 1
        for module_id: StringName in ModuleLoader.off_modules:
            var off_name := String(ModuleLoader.module_names.get(module_id, module_id))
            add_item(tr("%s: off") % off_name, row_id, false, tr("Off"))
            row_modules[row_id] = module_id
            var why: String = ModuleLoader.off_modules[module_id]
            set_item_tooltip(row_id, tr("Left out of this start, %s. Switched on in Preferences, Modules.") % why)
            row_id += 1
        if row_id == MODULE_ROW_BASE:
            add_item(tr("No modules found"), row_id, true)
        add_separator()
        add_item(tr("Turn Modules On or Off..."), ID_SWITCH_MODULES)
        set_item_tooltip(
            ID_SWITCH_MODULES, tr("Opens Preferences, Modules, where a module is switched on or off for the next start.")
        )

    func _pressed(id: int) -> void:
        _press_back.call(id)

    ## One module's row, "Built in" at its right or the name of the folder
    ## outside the build it was read from, which the painter opens to edit it.
    func _add_module_row(item_id: int, text: String, module_id: StringName, disabled: bool) -> void:
        var dir := ProjectSettings.globalize_path(str(ModuleLoader.module_dirs.get(module_id, ""))).trim_suffix("/")
        var built_in: bool = ModuleLoader.origins.get(module_id, "packaged") == "packaged"
        add_item(text, item_id, disabled, tr("Built in") if built_in else dir.get_file())
        row_modules[item_id] = module_id
        set_item_tooltip(item_id, tr("Built into Sara.") if built_in else tr("From the folder %s") % dir)


## Builds the module list as a child window of the menu's own popup, so the menu
## frees it with itself and the engine keeps the menu open while the list holds
## the keyboard.
func _init(menu_popup: SaChoicePopup) -> void:
    super(menu_popup)
    var list := SaChoicePopup.new(true, false)
    list.name = "ModulesList"
    module_list = ModuleList.new(list, on_id_pressed)
    if menu_popup != null:
        menu_popup.add_child(list)


## A list nobody holds is this menu's to free, since no tree will.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and module_list != null:
        var list := module_list.popup
        if is_instance_valid(list) and list.get_parent() == null:
            list.free()


## The popup's `branched` is connected here rather than in `_init`, because the
## popup is handed over before the bar has it in the tree and `populate` is the
## one call every path makes. A press on the Active Modules row, a pointer
## resting on it or the right arrow asks for its list without closing the menu,
## and `SaMenu` hears only the presses that close it.
func populate() -> void:
    super()
    if popup != null and not popup.branched.is_connected(_on_list_asked):
        popup.branched.connect(_on_list_asked)


func _on_list_asked(row_id: StringName) -> void:
    on_id_pressed(id_of(row_id))


## **The modules in a list of their own**, rather than a heading and its rows,
## because the list can get long, and every module a painter added would push
## the actions they opened the menu for further down. One row opens it, first,
## and the actions and the Develop rows follow.
func _add_items() -> void:
    popup.add_branch_row(key(ID_ACTIVE_MODULES), tr("Active Modules"))
    set_item_tooltip(ID_ACTIVE_MODULES, tr("Every module this start found, loaded, refused or switched off."))
    _add_module_actions()
    _add_develop_rows()


## Fills the module list and opens it beside the Active Modules row, and answers
## the list, which a suite reads without a tree. A menu that is closed has no
## row to open beside, so the list is filled and left shut.
func show_modules() -> SaChoicePopup:
    module_list.commands = commands
    module_list.populate()
    var list := module_list.popup
    popup.open_child(list, key(ID_ACTIVE_MODULES))
    return list


## The Active Modules row opens its list, deferred because the list takes the
## focus. A module's row opens the Modules window on its page, and the row under
## the list opens Preferences on the Modules page, where the switches are.
func _pressed(id: int) -> void:
    if id == ID_ACTIVE_MODULES:
        show_modules.call_deferred()
        return
    if module_list.row_modules.has(id):
        EventBus.module_page_requested.emit.call_deferred(module_list.row_modules[id])
        return
    var page := page_for(id)
    if not page.is_empty():
        EventBus.settings_page_requested.emit.call_deferred(page)


## The Preferences page a press on *id* opens, Modules for the row under the
## list, and "" for every other row, a module's row included, which opens the
## Modules window. Public, so a suite reads where a row leads without waiting a
## frame for the deferred emit.
static func page_for(id: int) -> String:
    return SaModulesPage.TITLE if id == ID_SWITCH_MODULES else ""


## The last section, in the order a module is written: what the pages say,
## the module started and its folder opened, the edit read in, a kernel's
## contract for a language model, and the local server a notebook or a script
## paints through.
##
## Reload Modules is here and not under the list it rereads, because a painter
## who edits a module presses it beside Reload Shaders, and two reloads in two
## sections would be the scatter this section was made to end. The heading is
## drawn only over rows, so a bar nobody bound shows the list alone.
func _add_develop_rows() -> void:
    if DEVELOP_ROWS.all(func(row: Array) -> bool: return _descriptor(row[1]) == null):
        return
    add_heading(tr("Develop"))
    add_commands(DEVELOP_ROWS)


## Appends one labelled group of items per module that registered an action.
##
## Separated by owner and labelled with the module's name, because "which module
## added this" is the first question anyone asks of an entry they did not expect,
## and a flat list cannot answer it.
func _add_module_actions() -> void:
    if commands == null:
        return
    var grouped := commands.list_menu_commands()
    var next_id := ACTION_ID_BASE
    for module_id: StringName in grouped:
        add_heading(module_display_name(module_id))
        for descriptor: SaCommandDescriptor in grouped[module_id]:
            # The module's own sentence when it wrote one, which is what the
            # descriptor carries: a module's action is explained here the way a
            # built-in is explained in the menu it belongs to.
            add_command(next_id, descriptor.id)
            if descriptor.sentence.is_empty():
                # A module that said nothing about its action leaves only what is
                # true of every one of them: who added it. Nothing here is
                # invented about what the action does, which only its module
                # knows. Set directly rather than through `explain`, because the
                # sentence is filled in after the translation rather than before it.
                set_item_tooltip(next_id, tr("Added by %s.") % module_display_name(module_id))
            next_id += 1


## The prompt file's text, or "" when it cannot be read.
##
## Read on the press rather than held, because it is fifty lines read once in a
## while and a copy in memory would be a second place for it to be stale.
static func prompt_text() -> String:
    var file := FileAccess.open(PROMPT_PATH, FileAccess.READ)
    if file == null:
        SaProblems.report("SaModulesMenu", "cannot read the kernel prompt at %s." % PROMPT_PATH)
        return ""
    return file.get_as_text()


## Reads a kernel prompt's output: the clipboard and the file it touches,
## `{"kernel_prompt": "clipboard"}` prints what the text clipboard holds,
## `{"kernel_prompt": "file"}` what the committed file holds and
## `{"kernel_prompt": "clear"}` empties the clipboard first, so a scenario can say
## the press put the one in the other rather than that it was already there.
## `{"kernel_prompt": "image"}` reads the desktop clipboard's picture the way
## Paste does.
##
## A step of its own because the `clipboard` step is the pixel clipboard, which
## is a different thing under the same word, and because nothing else in the dump
## reads `DisplayServer`.
##
## `clipboard_has` is printed beside the length because the two answers a
## scenario has to tell apart are "the clipboard is empty" and "this display
## server never took the offer", and only that one separates them. Under the
## Wayland offscreen runner it is always the second, because a window on no
## monitor is never given the selection.
static func capture(spec: Variant) -> String:
    var what := String(spec)
    match what:
        "clipboard":
            return (
                "SaCapture: the clipboard has %s and %s"
                % [DisplayServer.clipboard_has(), _measured(DisplayServer.clipboard_get())]
            )
        "file":
            return "SaCapture: the kernel prompt %s" % _measured(prompt_text())
        "clear":
            DisplayServer.clipboard_set("")
            return "SaCapture: the clipboard was emptied, has %s" % DisplayServer.clipboard_has()
        "image":
            return _clipboard_image()
    return "SaCapture: no kernel_prompt command '%s'" % what


## What `{"kernel_prompt": "image"}` prints: whether the engine says the
## desktop clipboard holds a picture, the size of the one it hands over, and
## what Sara's own reader found, the engine's picture or one a clipboard
## program or a `file://` address gave.
##
## The probe that settled which half of a silent paste failed. A value of
## this step rather than a step of its own, because one more kind took the
## door's list of step kinds past its budget, and both read `DisplayServer`'s
## clipboard. The engine's two answers are printed apart because "it says no
## picture" and "it says one and hands over an empty one" are different
## faults, and a size alone reads the same for both.
static func _clipboard_image() -> String:
    var image := DisplayServer.clipboard_get_image()
    var handed := "nothing" if image == null else "%dx%d" % [image.get_width(), image.get_height()]
    var picture := SaDesktopPicture.read()
    var found := "nothing"
    if picture != null:
        found = "%dx%d from %s" % [picture.image.get_width(), picture.image.get_height(), picture.source]
    return (
        "SaCapture: the desktop clipboard has an image %s, the engine hands over %s, its text %s, and Sara's reader finds %s"
        % [DisplayServer.clipboard_has_image(), handed, _measured(DisplayServer.clipboard_get()), found]
    )


## *text* as a length and a first line, which is all a dump wants of fifty lines
## of prose.
static func _measured(text: String) -> String:
    var lines := text.split("\n")
    return "holds %d character(s) in %d line(s), first line: %s" % [text.length(), lines.size(), lines[0]]
