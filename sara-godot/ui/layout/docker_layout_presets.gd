## The named layouts a painter chooses between, and everything one holds beyond
## where the dockers are.
##
## Apart from `DockerLayoutStore` because the store's subject is geometry. The
## store keeps the public names the Dockers menu and the Workspace page call,
## and forwards them here, so its preset half is one-line forwarders. The
## reading, the writing, the fork and the current name live here.
##
## **Built with the live file's path alone, and takes no reference back to the
## store**, because a helper cut from a class owns state of its own and holds
## no reference back to it. `live_replaced` and
## `live_applied` say what happened to the file rather than calling back, so
## the store answers them rather than being asked.
##
## **One rule: an edit the painter makes forks whatever they cannot write over,
## and nothing else does.** A second rule beside it, a shipped preset edited in
## place or a live layout under no preset, would answer an edit under
## `photo_editing` with some other name rather than `photo_editing (custom)`. A
## profile that has never chosen a layout is in [constant DEFAULT_PRESET], the
## first edit makes `default (custom)`, and a painter's own names are theirs and
## are written in place.
##
## A preset carries three things the live layout file does not: the UI scale,
## each category's element visibility, and each category's element order. None of them is geometry, and all three are what
## makes "minimalistic" different from "full" rather than merely differently
## arranged.
class_name SaDockerLayoutPresets
extends RefCounted

## Where the layouts that ship live. Read-only by construction, being inside the
## exported PCK, which is the whole of how "the defaults cannot be overwritten"
## is enforced: nothing here can write to `res://`.
const SHIPPED_DIR: String = "res://layouts"

## The seven that ship, in the menu's order: Sara's four, then Krita's,
## Photoshop's, Procreate's and Clip Studio Paint's for "I'm coming from", rather than
## alphabetically.
##
## **`user` is not among them.** A shipped name a painter's own layout replaced
## rather than forked from would be a second rule beside the fork, and would
## answer every edit with the same name whatever layout the painter was in. A
## name a painter saves under `user` is an ordinary one of their own, in their
## own folder, edited in place because it is theirs.
const SHIPPED: Array[String] = ["default", "minimalistic", "useful", "full", "krita", "photoshop", "procreate", "clip_studio"]
## What a menu row calls each shipped name, spelled out so the template holds
## the words a painter reads.
const SHIPPED_TITLES := {
    "default": "Default",
    "minimalistic": "Minimalistic",
    "useful": "Useful",
    "full": "Full",
    "krita": "Krita",
    "photoshop": "Photoshop",
    "procreate": "Procreate",
    "clip_studio": "Clip Studio",
}

## And a fork of each, the whole of it one message, so a language that puts the
## adjective first or agrees it with the layout's name translates it whole.
const CUSTOM_TITLES: Dictionary = {
    "default": "Default (Custom)",
    "minimalistic": "Minimalistic (Custom)",
    "useful": "Useful (Custom)",
    "full": "Full (Custom)",
    "krita": "Krita (Custom)",
    "photoshop": "Photoshop (Custom)",
    "procreate": "Procreate (Custom)",
    "clip_studio": "Clip Studio (Custom)",
}

## The layout a profile that has never chosen one is in.
##
## A live file with no preset key is in `default` rather than under no name,
## because an edit under no name would fork nothing. `default` is true, is a
## row in the list already, and makes the first edit produce `default (custom)`
## the way an edit under any other shipped name produces its own fork.
const DEFAULT_PRESET: String = "default"

## What a fork of a shipped preset is called. One suffix rather than a dialog,
## because the fork happens on an edit rather than on a decision, and a dialog
## in the middle of dragging a docker interrupts the drag.
const FORK_SUFFIX: String = " (custom)"

## The sections a preset carries beyond the docker geometry. Prefixed and
## underscored like `DockerLayoutStore.META_SECTION`, so no docker id can
## collide with one.
const UI_SECTION: String = "_layout_ui_"
const VISIBILITY_SECTION: String = "_layout_visibility_"
const ORDER_SECTION: String = "_layout_order_"

## True while a preset is being installed, which stops the store writing the
## layout file and stops the fork.
##
## Both matter. `apply` writes `SaSettings.ui_scale`, which emits synchronously
## and reaches the store's own save through `ui_scale_changed`. Unstopped, that
## save would overwrite the preset file just copied into place with the
## geometry of the layout being replaced, before `restore_all` had read a line
## of it, so every preset after the first would load the one ahead of it.
##
## Owned by `DockerLayoutStore.load_preset` rather than set inside `apply`,
## because the region that must not be written to is the apply and the restore
## together.
var applying: bool = false

## Emitted by [method load_into_live], after the new file is written and before
## its scale and element state are applied, so the store can drop what it cached
## about where each docker was before the geometry underneath it changes.
signal live_replaced

## Emitted by [method load_into_live], after [method apply] and while [member
## applying] is still true, so the store can put every docker where the freshly
## applied layout says.
signal live_applied

## Where the live layout file lives, handed in once rather than kept as a
## reference back to the store that built this: a store whose own path changes
## drops this object instead of asking it to follow along.
var _path: String

## Whether this session has said that an edit forked a layout. The store builds
## this object once a run, so the first fork it makes is the session's first.
var _told_of_a_fork: bool = false


func _init(path: String) -> void:
    _path = path


## Where named layouts live: a `layouts/` folder beside the layout file
## itself, so a settings folder the painter moved carries its presets with it.
func presets_dir() -> String:
    return _path.get_base_dir().path_join("layouts")


## Every layout the menu should offer: the ones that ship, then the painter's
## own, with a name that is both listed once.
##
## One list rather than a shipped list and a user list, because the menu, the
## Workspace page and the store all have to agree about what a painter can pick,
## and two lists is where the two doors disagree.
func list() -> Array[String]:
    var out: Array[String] = []
    for preset_name: String in SHIPPED:
        if FileAccess.file_exists(shipped_path(preset_name)):
            out.append(preset_name)
    # The modules' own, after the skeleton's and before the painter's. They are
    # read-only for the same reason the four above are, so they belong with them
    # rather than mixed into a painter's list.
    for listed: String in module_layouts().keys():
        if not out.has(listed):
            out.append(listed)
    var own: Array[String] = []
    var dir := DirAccess.open(presets_dir())
    if dir != null:
        for file_name in dir.get_files():
            if file_name.ends_with(".cfg") and not out.has(file_name.get_basename()):
                own.append(file_name.get_basename())
    own.sort()
    out.append_array(own)
    return out


## Every layout a loaded module ships, as `{"<module id>/<name>": path}`.
##
## Asked of the loader on every call rather than cached, because a module can be
## loaded and unloaded while the app runs and a cached list would offer the
## painter a layout no module is behind. It is a directory listing per module and
## the menu asks once per open.
##
## `ModuleLoader` by name, the way every other file in `ui/` reaches an autoload.
## The first draft asked the tree for it through `Engine.get_main_loop().root`,
## which is a `MainLoop` and has no `root`, so the call failed at run time and
## took the whole of [method list] down with it: the first capture of this listed
## no layouts at all, the four shipped ones included.
func module_layouts() -> Dictionary:
    return ModuleLoader.module_layouts()


## Whether *preset_name* is one of the shipped ones, and therefore not a file
## anything can write over.
##
## A module's layout counts, and for exactly the reason the four do: it lives
## inside the module's folder, which is inside the PCK for a packaged module,
## and an edit to it has to fork rather than fail silently. A module's layout
## is listed and forked the same way as a shipped one, and this is the line
## that makes it forked.
func is_shipped(preset_name: String) -> bool:
    return SHIPPED.has(preset_name) or module_layouts().has(preset_name)


## What an edit under *preset_name* saves as: the painter's own names save under
## themselves, and a shipped one forks.
##
## An empty name stays empty and [method save_as] refuses it. A layout in no
## preset at all needs no case here, because [method current] answers
## `default` for it.
func target_name(preset_name: String) -> String:
    if not is_shipped(preset_name):
        return preset_name
    # Validated, which matters only for a module's layout: it is listed as
    # `<module id>/<name>` and the slash cannot be in a file name, so a fork that
    # kept it would be listed under the name the file got, `layout-fixture_desk
    # (custom)`, while `current` answered `layout-fixture/desk (custom)`. The
    # menu's tick would then be on a row that is not there. The first capture of
    # this showed exactly that pair. The four the skeleton ships are unchanged by
    # validation, so nothing about them moves.
    return (preset_name + FORK_SUFFIX).validate_filename()


## Where the read-only copy of *preset_name* lives: the skeleton's `res://layouts`
## for the four it ships, and the module's own folder for one a module ships.
func shipped_path(preset_name: String) -> String:
    var from_a_module: String = String(module_layouts().get(preset_name, ""))
    if not from_a_module.is_empty():
        return from_a_module
    return SHIPPED_DIR.path_join(preset_name.validate_filename() + ".cfg")


## Where *preset_name* is read from: the painter's own copy when there is one,
## and the shipped file otherwise. A painter's own copy of a shipped name
## shadows the one that ships, which is what makes it theirs.
func read_path(preset_name: String) -> String:
    var own := _preset_path(preset_name.validate_filename())
    return own if FileAccess.file_exists(own) else shipped_path(preset_name)


## What a menu row calls *preset_name*. The four Sara ships, and a fork of one,
## in title case like every other row of a menu rather than as their file
## names. A painter's own name and a module's read as they were
## written: the words are theirs, and a capital on "iPad sketch" would be wrong.
func title(preset_name: String) -> String:
    var shipped := preset_name.trim_suffix(FORK_SUFFIX)
    if not SHIPPED.has(shipped):
        return preset_name
    if shipped == preset_name:
        return tr(SHIPPED_TITLES[shipped])
    return tr(CUSTOM_TITLES[shipped])


## The UI scale loading *preset_name* sets, or 1 for one that sets none or
## cannot be read, which leaves the painter's own alone.
func ui_scale_of(preset_name: String) -> float:
    var cfg := ConfigFile.new()
    if cfg.load(read_path(preset_name)) != OK:
        return 1.0
    return float(cfg.get_value(UI_SECTION, "ui_scale", 1.0))


## Writes the UI scale and every category's element state into *cfg*.
##
## Read from `SaSettings` rather than from the controls, because a docker that
## is closed still has an order and a set of hidden elements, and a preset that
## only recorded what was on screen would lose them.
##
## A composed docker is skipped, since its elements are the library's and a
## layout keeps only its place and shown flag.
func capture(cfg: ConfigFile) -> void:
    cfg.set_value(UI_SECTION, "ui_scale", SaSettings.ui_scale)
    for category: Dictionary in SaSettings.reorderable_categories():
        var id := String(category["id"])
        if SaComposedDockers.is_composed(id):
            continue
        cfg.set_value(ORDER_SECTION, id, SaSettings.get_layout_order(id))
        for element: String in SaSettings.get_layout_order(id):
            cfg.set_value(VISIBILITY_SECTION, "%s/%s" % [id, element], SaSettings.get_element_visible(id, element))


## Puts back what [method capture] wrote. A preset written before one of these
## sections existed simply has none, and leaves that half of the state alone.
## A composed docker's lines, in a file written by hand, are passed over.
func apply(cfg: ConfigFile) -> void:
    if cfg.has_section_key(UI_SECTION, "ui_scale"):
        SaSettings.ui_scale = float(cfg.get_value(UI_SECTION, "ui_scale", SaSettings.ui_scale))
    # Gathered and written at once, one save and one round of the dockers
    # following it rather than one a key.
    var orders := {}
    if cfg.has_section(ORDER_SECTION):
        for id in cfg.get_section_keys(ORDER_SECTION):
            if not SaComposedDockers.is_composed(id):
                orders[String(id)] = cfg.get_value(ORDER_SECTION, id, []) as Array
    if orders.has(SaTopBarPageEdges.CATEGORY):
        @warning_ignore("static_called_on_instance")
        orders[SaTopBarPageEdges.CATEGORY] = SaSettings.page_edges_order(orders[SaTopBarPageEdges.CATEGORY])
    var shown: Array = []
    # A layout saved before Page Edges names the two elements it replaced, and
    # it is shown when either was.
    var page_edges: Variant = null
    if cfg.has_section(VISIBILITY_SECTION):
        for key in cfg.get_section_keys(VISIBILITY_SECTION):
            var parts := String(key).split("/", false, 1)
            if parts.size() != 2 or SaComposedDockers.is_composed(parts[0]):
                continue
            var on := bool(cfg.get_value(VISIBILITY_SECTION, key, true))
            if parts[0] == SaTopBarPageEdges.CATEGORY and SaTopBarPageEdges.RETIRED.has(parts[1]):
                page_edges = on or page_edges == true
                continue
            shown.append([parts[0], parts[1], on])
    if page_edges != null:
        shown.append([SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT, page_edges])
    SaSettings.set_layout_many(orders, shown)


## The preset the live layout came from, which is never nothing.
##
## Kept in the layout file rather than in the settings, because it is a fact
## about that file: copying a preset over it brings the name with it, and a
## profile whose layout file is deleted has no current preset either.
##
## A file with no preset key answers [constant DEFAULT_PRESET] rather than "".
## That is what a fresh profile is in, so the Workspace page never describes a
## painter as being in no layout.
func current() -> String:
    var cfg := ConfigFile.new()
    if cfg.load(_path) != OK:
        return DEFAULT_PRESET
    var stored := String(cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, ""))
    return DEFAULT_PRESET if stored.is_empty() else stored


## Writes the live layout out under *preset_name*, and makes it the current one.
##
## The caller saves the live layout first (`DockerLayoutStore.save_preset`), so
## what the preset holds is where the dockers are now rather than where they
## were when the file was last written. A shipped name saves as a fork instead,
## because `res://` is not writable and the defaults survive being saved over.
func save_as(preset_name: String) -> bool:
    var written := target_name(preset_name)
    var file_name := written.validate_filename()
    if file_name.is_empty():
        return false
    DirAccess.make_dir_recursive_absolute(presets_dir())

    var cfg := ConfigFile.new()
    cfg.load(_path)
    # The name the file gets rather than the one typed, for the reason
    # `target_name` gives about a module's fork: `list` reads the file names, so
    # "Studio: night" kept as typed was current under a name no row carries, and
    # `forget` of the listed "Studio_ night" never cleared it.
    cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, file_name)
    capture(cfg)
    if cfg.save(_path) != OK:
        return false
    return cfg.save(_preset_path(file_name)) == OK


## Makes *preset_name* the live layout and puts every docker where it says, at
## the UI scale and with the element state it was saved with.
##
## A shipped layout's heights are an upper bound for a docker that says how
## tall its content is. The store cuts them in its
## `restore_all`, which `live_applied` reaches, because the content is only
## measured once [method apply] has put the element state the layout carries
## on the dockers, and this class has no window to measure.
func load_into_live(preset_name: String) -> bool:
    if not begin_load(preset_name):
        return false
    finish_load()
    return true


## The first half of [method load_into_live]: the file made live and the
## element state put on the dockers, with the geometry left to
## [method finish_load], which a caller spreading the load over frames calls a
## frame later. Answers false, with nothing changed, for a preset that
## cannot be read or a live file that cannot be written.
func begin_load(preset_name: String) -> bool:
    var cfg := ConfigFile.new()
    if cfg.load(read_path(preset_name)) != OK:
        return false
    cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, preset_name)
    if cfg.save(_path) != OK:
        return false
    # A layout says which dockers are open, so the Tab that hid them is over.
    SaFocusMode.leave()
    # The store's cache is what restore_window and value_for answer from, and
    # every entry in it belongs to the layout that has just been replaced.
    live_replaced.emit()
    applying = true
    # The scale first, so the geometry is restored in the units the preset was
    # written in rather than resized under the dockers afterwards.
    apply(cfg)
    return true


## The second half of [method load_into_live]: every docker put where the live
## layout says.
func finish_load() -> void:
    live_applied.emit()
    applying = false


## Writes the painter's edit into the file of the layout in use, forking it
## first when the painter cannot write over it, and answers the name in use
## afterwards.
##
## Called from the painter's own edits rather than from every `save()`, because
## the compositor settle writes the layout file a dozen times after a load and
## none of those is somebody changing anything. That is also why the file under
## `layouts/` is written here and not by the store's `save`: a load, a settle,
## a resize of the host and a scale change write the live file only, so the
## named layout keeps what the painter last chose.
##
## **One rule and no exception.** An exception for one name would answer an
## edit under any preset with that name. A shipped name forks, a painter's own
## name, a fork included, is written in place on every edit, and there is no
## third case. Writing only on the first edit under a shipped name left a fork
## holding that edit and a painter's own layout holding its save, so coming
## back to either from another layout undid every arrangement made since.
##
## **The first fork of a session says so**, in the corner the refusals use,
## naming the layout the painter is in now, because otherwise a moved docker
## forks the layout without a word and the Window menu is the only place the
## new name shows. Once, because every later edit of the session stays in the fork and
## a line on every drag would be noise.
func fork_for_edit() -> String:
    var name_in_use := current()
    if applying or not save_as(name_in_use) or not is_shipped(name_in_use):
        return name_in_use
    var forked := target_name(name_in_use)
    if not _told_of_a_fork:
        _told_of_a_fork = true
        var line := tr("Your layout is kept as %s. Window > Layouts still has %s as it ships.")
        EventBus.corner_notice.emit(line % [title(forked), title(name_in_use)])
    return forked


## Where the file for *file_name* lives, under [method presets_dir].
func _preset_path(file_name: String) -> String:
    return presets_dir().path_join(file_name + ".cfg")


## Whether [method forget] has a file of the painter's to remove for
## *preset_name*. A shipped name nobody saved over has none, and neither has a
## name that is no file name, so the Delete that reads this is dimmed for both.
func can_forget(preset_name: String) -> bool:
    var file_name := preset_name.validate_filename()
    return not file_name.is_empty() and FileAccess.file_exists(_preset_path(file_name))


## Forgets *preset_name*. The live layout is left exactly as it is: deleting the
## preset a painter is working in should not move their dockers.
##
## A shipped name deletes the painter's own copy of it and leaves the shipped
## file, so the row goes back to what it ships as rather than out of the list.
func forget(preset_name: String) -> bool:
    if not can_forget(preset_name):
        return false
    if DirAccess.remove_absolute(_preset_path(preset_name.validate_filename())) != OK:
        return false
    if current() == preset_name:
        var cfg := ConfigFile.new()
        cfg.load(_path)
        cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, "")
        cfg.save(_path)
    return true
