## Persists docker window geometry to docker_layout.cfg in the data root, `SaDataRoot`.
##
## Split out of ui/main/main.gd, which was doing docker lifecycle, layout persistence,
## shortcut routing and the module-facing skeleton API in one 790-line file.
##
## Coordinates are stored normalised to 1x so a layout survives moving between
## displays, and are multiplied back by SaUI.scale() on load.
##
## Why the repeated re-application below: when a top-level Window is mapped on
## Wayland the compositor assigns its own placement (usually centring it), and
## xdg-shell gives a client no way to demand an absolute position. Setting the
## position once, before the window is mapped, is simply discarded. So geometry is
## applied immediately, again deferred to the next idle frame, and then re-checked
## for a bounded number of frames while the compositor settles.
##
## The store is the door every caller uses, and it keeps the layout's own state,
## the cache, the intent and the settle. Three jobs are classes of their own, cut
## out of it by responsibility when it stood at the thousand lines a run fails:
## `SaBorrowedDockers` lends a docker to the pointer, `SaDockerVariantSizes`
## keeps a docker's size per variant of itself, and `SaDockerStoredEntry` reads
## a stored rectangle back into this run. The named layouts are
## `SaDockerLayoutPresets`, and where a docker goes on a host is
## `SaDockerLayoutRefit`.
extends Node

class_name DockerLayoutStore

const DockerDragHandleScript = preload("res://ui/dockers/docker_drag_handle.gd")

## The layout file of a store nobody pointed elsewhere, under the data root.
## The app points it beside the settings file, and this is the file a
## suite's store falls back to.
const FILE_NAME: String = "docker_layout.cfg"
const SHIPPED_DEFAULTS: String = "res://docker_layout_default.cfg"
## The least share of the window's width the shipped default leaves to paint
## in, the fit's, for the scale row outside this folder to warn by.
const PAINTING_SHARE: float = SaDockerLayoutFit.PAINTING_SHARE
## How long to keep re-asserting geometry against the compositor, in frames.
const SETTLE_FRAMES: int = 60

## Which unit system the stored geometry was measured in.
##
## An embedded subwindow's position and size are in the host's logical space, a
## real OS window's are in physical pixels, and the two differ by the display
## scale. A layout written in one and read in the other is off by that factor,
## which is how every docker ended up at its minimum size. A file without this
## key predates the check and is not trusted.
const META_SECTION: String = "_layout_meta_"
const META_EMBEDDED: String = "embed_subwindows"

## The named layout the live file came from, or absent when it came from none.
## In the same section as the units, for the same reason: it describes the file
## rather than any one docker.
const META_PRESET: String = "preset"

## The host a shipped layout was written for, `Vector2i(1920, 1080)` for all
## four. A file with it is placed from the host it opens on while it is still
## the shipped one, which is `SaDockerLayoutRefit.shipped_entries`.
const META_WRITTEN_FOR: String = "written_for"

## A title a built-in docker was registered under before it was renamed, keyed
## by the name it has now, so a file from before both changes still restores.
## The toolbox was "ToolBox" until its name took the docker's own spelling.
const FORMER_TITLES := {"Toolbox": "ToolBox"}

## The pop-up palette's size in a file from before the palette grew by its HUD,
## which every profile that never sized the palette stored. Read once as the size it opens
## at now. A file a save of this build wrote says so under [constant META_HUD]
## and keeps whatever size it holds, since that size is the painter's.
const PALETTE_BEFORE_HUD := Vector2i(360, 384)
const META_HUD: String = "palette_hud"

## Dockers a fresh profile leaves closed: the ones a painter reaches for rather
## than paints with. The Dockers menu opens any of them, and a profile that
## opened one keeps it open. A docker missing from this list opens at the top
## left of a fresh profile, over the menus.
const HIDDEN_UNTIL_ASKED: Array[StringName] = [
    SaDockerIds.INFO,
    SaDockerIds.MINIMAP,
    SaDockerIds.RECORDER,
    SaDockerIds.GRAPH,
    SaDockerIds.HISTORY,
    SaDockerIds.UNDO,
    SaDockerIds.PALETTE,
    SaDockerIds.FILTERS,
    # The Sphere module's docker, by the id it had as a built-in.
    &"SphereDocker"
]

## A named layout was saved, loaded or forgotten, by whichever door, so the
## Dockers menu that lists them hears it from the store.
signal presets_changed

## Where the layout file lives. Reassigning it drops the presets object below,
## which is built from this path, so the next `presets()` call makes a fresh one
## bound to the new file rather than handing back one built for the old.
var path: String = SaDataRoot.path(FILE_NAME):
    set(value):
        path = value
        _presets = null
        _variants = SaDockerVariantSizes.new(value)

## `func() -> Array[Dictionary]` returning {"id": String, "name": String,
## "node": Window} entries. The id is the section the geometry is stored under
## and the name is the title the docker shows. A provider that gives no id, which
## is what a test's throwaway probe looks like, is keyed by its name.
var dockers_provider: Callable = Callable()

## `func() -> bool`. Saving is skipped while this returns false, so the layout is
## not overwritten with half-built geometry during startup.
var save_allowed: Callable = Callable()

## `func() -> int`, the first logical row below the bar, which no docker of the
## default layout is fitted above. Unset reads as the host's top edge.
var top_inset: Callable = Callable()

## Optional menu whose check marks mirror docker visibility. `SaChoicePopup`,
## where the app's menus stopped being `PopupMenu`s.
var dockers_menu: SaChoicePopup = null

## The named layouts, and everything one holds beyond geometry. Built on first
## use rather than in a `_ready`, because a test builds this node without adding
## it to a tree.
var _presets: SaDockerLayoutPresets = null

var _cache: Dictionary = {}

## The sizes a docker keeps per variant of itself, in the file at `path`, built
## again when the path changes.
var _variants := SaDockerVariantSizes.new(path)

## Section -> the position the user chose, which is not always where the window is.
##
## Shrinking the host clamps an embedded subwindow into the viewport, and a docker
## cannot tell that from being dragged. Saving the clamped position made it
## permanent, so growing the window back left every docker stranded in the middle
## of the canvas, somewhere nobody had put it.
##
## Intent is only updated when the window *could* have stayed where the user left
## it. A position the host still has room for and did not keep is a choice. A
## position the host has no room for is the clamp, and the choice is remembered
## instead.
var _intended_positions: Dictionary = {}

## The dockers out on a borrow, each with the address it goes back to. Beside
## the cache rather than in it, because the cache is the layout and a borrow is
## not.
var borrowed := SaBorrowedDockers.new()

## What carries every docker across a switch of embedded subwindows.
var _flip := SaDockerEmbedFlip.new()

## The painter's own rectangle of each docker a fit of their layout moved.
var _painter_rects := SaDockerLayoutRefit.PainterRects.new()


## Each side of the switch hands the flip this store, whose memory it reads and
## whose public methods it writes through.
func _ready() -> void:
    SaSettingsApply.embedding_will_change.connect(_flip.before_the_switch.bind(self))
    SaSettingsApply.embedding_changed.connect(_flip.after_the_switch.bind(self))


func _dockers() -> Array:
    if not dockers_provider.is_valid():
        return []
    return dockers_provider.call()


## Writes every docker's geometry to disk.
##
## *by_painter* is a save the app can attribute to a hand rather than to the
## compositor, and it goes through whatever `save_allowed` says. The gate exists
## to stop the half-built geometry a compositor reports at startup from
## overwriting a stored layout, and it is written as a time window, 1500
## milliseconds from launch. Without *by_painter*, a docker a painter drags
## inside that window would be saved nowhere, and the settle loop this file runs
## after every restore would put it back where it was, once a frame for sixty
## frames.
##
## The distinction is the one `MainDockers._painter_changed_the_layout` draws
## and says out loud: `docker_layout_changed` is emitted by the drag handle and
## the resizer and by nothing else, so a save carrying it is never the
## compositor settling a window.
func save(by_painter: bool = false) -> void:
    if not by_painter and save_allowed.is_valid() and not save_allowed.call():
        return
    # Nothing writes this file while a preset is being installed into it. See
    # `SaDockerLayoutPresets.applying` for the run this cost.
    if _presets != null and _presets.applying:
        return

    var cfg := ConfigFile.new()
    cfg.load(path)
    var before := _cache.duplicate()
    _cache.clear()

    cfg.set_value(META_SECTION, "app_scale", SaUI.scale())
    cfg.set_value(META_SECTION, META_EMBEDDED, SaSettings.embed_subwindows)
    cfg.set_value(META_SECTION, META_HUD, true)

    for config: Dictionary in _dockers():
        var win: Window = config["node"] as Window
        var section: String = section_for(config)
        if win == null:
            continue
        # A docker filling the window is not a geometry the painter chose, so the
        # store never learns it. Skipping leaves the stored rectangle exactly as
        # it was, which is what makes the preset file byte for byte the same
        # across a maximise and a restore.
        if SaDockerMaximise.is_maximised(win):
            continue
        # A borrowed docker is where the pointer asked for it and not where the
        # painter put it, so it is skipped for the same reason as the maximised
        # one above and the preset install at the top. Its cached entry is kept,
        # so the settle loop and `stored_positions` still answer the painter's
        # rectangle after a save of the others. A save the painter made is a
        # drag or a resize of this one too, so the borrow follows the window
        # first.
        if is_borrowed(section):
            if by_painter:
                borrowed.follow(section, win)
            if before.has(section):
                _cache[section] = before[section]
            continue

        # Each window is normalised by its own factor: an embedded subwindow already
        # lives in the host's logical space and must not be divided again.
        var scale_factor := SaUI.window_scale(win)
        var sz := SaDockerStoredEntry.floored(win, win.size)
        # A docker a fit of the painter's layout moved is saved at the painter's
        # size, and the cache keeps the size it shows.
        var stored_sz := sz
        if _painter_rects.moved(section, win):
            stored_sz = SaDockerStoredEntry.floored(win, _painter_rects.painter(section, win, win.position).size)
        var pos := win.position
        var runtime_pos := pos
        var norm_pos := Vector2i()

        # A window reporting (0,0) has usually not been placed by the compositor
        # yet, so keep the stored position rather than overwriting it with a zero.
        if pos == Vector2i(0, 0) and cfg.has_section_key(section, "position"):
            norm_pos = cfg.get_value(section, "position", Vector2i())
            if norm_pos != Vector2i():
                runtime_pos = Vector2i(Vector2(norm_pos) * scale_factor)
        elif pos != Vector2i(0, 0):
            var intended := _intent_for(win, section, pos, by_painter)
            runtime_pos = pos if _painter_rects.moved(section, win) else intended
            norm_pos = Vector2i(Vector2(intended) / scale_factor)

        _cache[section] = {"position": runtime_pos, "size": sz, "visible": win.visible}

        if norm_pos != Vector2i():
            cfg.set_value(section, "position", norm_pos)
        cfg.set_value(section, "size", Vector2i(Vector2(stored_sz) / scale_factor))
        cfg.set_value(section, "visible", SaFocusMode.layout_visible(section, win.visible))
    _note_arranged(_painter_layout(_dockers()), _dockers())

    # A fresh `--settings-dir` has no data root yet, and a save into a folder
    # that is not there fails.
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var err := cfg.save(path)
    if err != OK:
        push_error("Failed to save docker layout: %d" % err)


## What this store holds as each visible docker's position, by section, for a
## capture that has to tell a drag the settle loop is about to undo from a drag
## that never landed.
func stored_positions() -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in _dockers():
        var win: Window = config["node"] as Window
        if win == null or not win.visible:
            continue
        var section: String = section_for(config)
        out[section] = value_for(section, "position", Vector2i())
    return out


## What the user meant this docker's position to be, updating the memory when the
## live position can only be their doing.
##
## **`by_painter` settles it outright**. The rule below is a guess at whose doing
## a position is, and it guesses from geometry: a remembered position that does
## not fit the host means the app reflowed the window, so the live one is the
## app's and the remembered one is kept, which is what carries a docker back when
## the window grows again. The guess is right whenever nobody knows, and it is
## wrong the moment somebody does. A drag emits `docker_layout_changed` and
## nothing else does, so a save carrying that signal knows.
##
## What it cost: a docker dragged anywhere its remembered position stops fitting,
## which on a 1920 host is anywhere off the left edge, froze its intent there.
## Every later drag was written to the window, guessed to be a reflow, dropped
## from the store, and then undone by the settle loop re-asserting the frozen
## value once a frame for sixty frames. Four drags of the Minimap left it where
## the second one put it.
##
## **A painter's save still leaves a pushed docker its memory.** A docker
## standing exactly where [method reflow_to_host] pushed its remembered position
## is the app's doing, and a painter's save is a drag or a show of another one.
## Taking it as the painter's is what made a docker opened at scale 2 strand
## every other docker where scale 2 had pushed it.
func _intent_for(win: Window, section: String, live: Vector2i, by_painter: bool = false) -> Vector2i:
    var intended: Vector2i = _intended_positions.get(section, live)
    if _painter_rects.moved(section, win):
        # Where a fit of the painter's layout put it, which is never theirs.
        return intended
    var pushed := live == _fit_position(win, intended)
    if (by_painter and not pushed) or intended == live or _position_fits(win, intended):
        # There was room for where they left it. So wherever it is now, they put
        # it there.
        intended = live
    _intended_positions[section] = intended
    return intended


## Whether *pos* is a place this window could actually sit in its host.
func _position_fits(win: Window, pos: Vector2i) -> bool:
    return _refit().fits(win, pos)


## The space a window has to sit in: its host viewport when embedded, the screen
## otherwise.
##
## The rule itself is `DockerDragHandle.host_size_of`, because the corner grip's
## resize needs the same answer and two copies of it would drift.
func _host_size(win: Window) -> Vector2i:
    return DockerDragHandleScript.host_size_of(win)


## Puts every docker back where the user left it, as far as the host now allows.
##
## Called when the main window changes size, the UI scale changes or the bar
## grows a row. Shrinking moves a docker in only once a title strip would leave
## the window, below the bar, and growing has to undo it: the user did not move
## them. A shipped layout is fitted again whole, and only the painter's own
## layouts are pushed and put back, which is `SaDockerLayoutRefit`.
func reflow_to_host() -> void:
    var cfg := ConfigFile.new()
    cfg.load(path)
    var dockers := _dockers()
    var fitted := _refit().shipped_entries(cfg, dockers)
    var shipped := not fitted.is_empty()
    var painter := _painter_layout(dockers)
    if not shipped:
        fitted = _refit().painter_entries(cfg, painter, _windows_of(dockers), _painter_rects.arranged_on)
    _note_arranged(painter, dockers)
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        var section: String = section_for(config)
        if win == null or not win.is_inside_tree() or SaDockerMaximise.is_maximised(win):
            continue
        if is_borrowed(section):
            # A borrowed docker stays under the pointer, kept inside the host.
            win.position = _refit().kept(win, borrowed.held(section, "position"))
            continue
        if fitted.has(section) and shipped:
            SaDockerLayoutRefit.put(win, fitted[section])
            note_placement(win)
            continue
        if fitted.has(section):
            # The painter's place stays their intent, so the cache alone learns
            # the fitted one, for the settle loop to hold.
            _painter_rects.put(section, win, fitted[section], painter[section])
            _cache[section] = {"position": win.position, "size": win.size, "visible": win.visible}
            continue
        var was_moved := _painter_rects.moved(section, win)
        _painter_rects.put_back(section, win)
        var intended: Vector2i = _intended_positions.get(section, Vector2i())
        if intended != Vector2i():
            _refit().put_back(win, intended)
        if was_moved:
            # Or the settle loop puts the fitted rectangle back from the cache,
            # and the next save takes it for the painter's, which is where the
            # Reference stayed after a trip to 1.25 and back.
            _cache[section] = {"position": win.position, "size": win.size, "visible": win.visible}


## The painter's rectangle of each open embedded docker of *dockers*, by
## section, for [method SaDockerLayoutRefit.painter_entries]. A borrowed or a
## maximised docker is not where the painter put it and is left out.
func _painter_layout(dockers: Array) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        var section: String = section_for(config)
        if win == null or not win.visible or not win.is_inside_tree() or not win.is_embedded():
            continue
        if is_borrowed(section) or SaDockerMaximise.is_maximised(win):
            continue
        out[section] = _painter_rects.painter(section, win, _intended_positions.get(section, win.position))
    return out


func _windows_of(dockers: Array) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in dockers:
        if config["node"] is Window:
            out[section_for(config)] = config["node"]
    return out


## Whether every rectangle of *painter*, by section of *dockers*, stands on the
## host where it is, so the host is one the painter's layout was arranged on.
func _all_inside(painter: Dictionary, dockers: Array) -> bool:
    var wins := _windows_of(dockers)
    for section: String in painter:
        var rect: Rect2i = painter[section]
        if not _refit().whole_on_host(wins[section], rect):
            return false
    return not painter.is_empty()


## Remembers the host as the one the painter's layout was arranged on when
## every rectangle of *painter* stands on it. A restore, a save and a reflow
## all look, so a fork made at 1.0 is known to fit there before the change of
## scale that fits it.
func _note_arranged(painter: Dictionary, dockers: Array) -> void:
    if not _all_inside(painter, dockers):
        return
    for config: Dictionary in dockers:
        var win: Window = config["node"] as Window
        if win != null and painter.has(section_for(config)):
            _painter_rects.arranged_on = _host_size(win)
            return


## *pos*, moved as little as possible to keep a part of the window's title
## strip on its host, the bar's rows included, [method SaDockerLayoutRefit.reached].
func _fit_position(win: Window, pos: Vector2i) -> Vector2i:
    return _refit().reached(win, pos)


func _refit() -> SaDockerLayoutRefit:
    return SaDockerLayoutRefit.new(top_inset, SaDockerStoredEntry.floored)


## Apply the stored layout to every docker, falling back to its built-in geometry.
func restore_all() -> void:
    if not FileAccess.file_exists(path) and FileAccess.file_exists(SHIPPED_DEFAULTS):
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var dir := DirAccess.open(path.get_base_dir())
        if dir != null:
            dir.copy(SHIPPED_DEFAULTS, path)

    # A layout applied whole puts every docker where it says, a borrowed one
    # included, so no return address is left pointing at a layout that is gone.
    borrowed.forget_all()
    _painter_rects.forget()

    # The file may be the shipped one just copied, and the migration below moves
    # sections, so the variant sizes are read again from what it says now.
    _variants.forget()
    var cfg := ConfigFile.new()
    var has_cfg := cfg.load(path) == OK and _units_match(cfg)
    var usable_rect := SaDockerStoredEntry.all_screens_rect() if has_cfg else Rect2i()

    var dockers := _dockers()
    var moved := has_cfg and _adopt_title_sections(cfg, dockers)
    if (has_cfg and _grow_the_old_palette(cfg)) or moved:
        cfg.save(path)
    var fitted := _refit().shipped_entries(cfg, dockers) if has_cfg else {}
    # A live file naming a shipped layout is the shipped one, since an edit forks
    # it, so a docker in it that says how tall its content is opens at that.
    # The four Sara ships have it from their fit, and a layout of the
    # painter's is restored as saved.
    var named := String(cfg.get_value(META_SECTION, META_PRESET, "")) if has_cfg else ""
    var held := _refit().shipped_heights(presets().shipped_path(named), dockers) if presets().is_shipped(named) else {}
    # The dockers the file has no section for whose registration names a side,
    # placed once every docker it names has its rectangle.
    var unnamed: Array = []
    var opened: Dictionary = {}
    for i in dockers.size():
        var config: Dictionary = dockers[i]
        var win: Window = config["node"] as Window
        var section: String = section_for(config)
        if win == null:
            continue
        # A docker filling the window is not a geometry the painter chose, so the
        # store never learns it. Skipping leaves the stored rectangle exactly as
        # it was, which is what makes the preset file byte for byte the same
        # across a maximise and a restore.
        if SaDockerMaximise.is_maximised(win):
            continue

        var entry: Dictionary
        if has_cfg and cfg.has_section(section):
            entry = SaDockerStoredEntry.scaled(section, win, cfg, usable_rect)
        elif not String(config.get("side", "")).is_empty():
            unnamed.append(config.merged({"index": i}))
            continue
        else:
            # A composed docker is in every layout, and one that does not name
            # it has never opened it, so it opens closed. So does a docker a
            # module registers, which no list of the skeleton may name.
            var by_module := not String(config.get("module", "")).is_empty()
            var asked := HIDDEN_UNTIL_ASKED.has(win.name) or SaComposedDockers.is_composed(win.name) or by_module
            entry = {"position": win.position, "size": win.size, "visible": not asked}
        if fitted.has(section):
            entry.merge(SaDockerLayoutRefit.taken(win, fitted[section]), true)
        elif held.has(section):
            entry["size"] = _held_size(win, entry["size"], held[section])

        # Its strip kept in reach as a resize keeps it, with the file's place
        # remembered for a host that has room for it again.
        var placed: Vector2i = entry["position"]
        if placed != Vector2i() and not fitted.has(section) and win.is_embedded():
            entry["position"] = _refit().reached(win, placed, entry["size"])
        _cache[section] = entry
        _apply(win, section, entry)
        if placed != Vector2i():
            _intended_positions[section] = placed
        if bool(entry["visible"]):
            opened[section] = Rect2i(entry["position"], entry["size"])
        _tick(i, bool(entry["visible"]))
    var places := SaDockerDefaultPlace.new(opened, top_inset)
    for config: Dictionary in SaDockerDefaultPlace.in_order(unnamed):
        var win: Window = config["node"]
        var entry := places.entry_for(win, StringName(config["side"]), _host_size(win))
        _cache[section_for(config)] = entry
        _apply(win, section_for(config), entry)
        _tick(int(config["index"]), true)
    _note_arranged(_painter_layout(dockers), dockers)
    SaDockerLayoutRefit.follow_the_floors(_refit(), self, dockers)


## Ticks the Window menu's row of the docker at *index* as *open*, without
## announcing it: the docker's geometry was restored, the row is catching up,
## and a signal here would toggle it back.
func _tick(index: int, open: bool) -> void:
    if dockers_menu == null:
        return
    var row := StringName("docker_%d" % index)
    var holder := SaMenu.list_holding(dockers_menu, row)
    var box := holder.check_box(row) if holder != null else null
    if box != null:
        box.set_pressed_no_signal(open)


## *given* with the height *shipped* gives it, made what *win*'s content needs,
## or *given* as saved when the content does not say. Measured at the width the
## window opens at after the clamp, because a toolbox dragged into a row and
## then given a shipped layout opens that wide, on the base as well, and a
## height measured at the shipped width cut it into a row again.
func _held_size(win: Window, given: Vector2i, shipped: int) -> Vector2i:
    var width := SaDockerStoredEntry.floored(win, given).x
    var opened := SaDockerLayoutRefit.opening_height(win, Vector2i(width, shipped))
    return Vector2i(given.x, opened) if opened > 0 else given


## Re-apply one docker's stored geometry, e.g. after it is shown again.
func restore_window(win: Window, section: String) -> void:
    if win == null:
        return
    var entry: Dictionary = _cache.get(section, {})
    if entry.is_empty():
        var cfg := ConfigFile.new()
        if cfg.load(path) != OK or not cfg.has_section(section):
            return
        var screen := DisplayServer.window_get_current_screen()
        entry = SaDockerStoredEntry.scaled(section, win, cfg, DisplayServer.screen_get_usable_rect(screen))

    var pos: Vector2i = entry.get("position", win.position)
    if pos != Vector2i():
        win.position = pos
    win.size = _variants.restored(win, section, SaDockerStoredEntry.floored(win, entry.get("size", win.size)))
    reapply_deferred(win, section)


## One stored field, from the cache if present and from disk otherwise. Records
## where something other than the compositor has just put *win*, so the settle
## loop re-asserts that rather than the position it restored.
##
## A `docker` step writes `window.position` directly, and for sixty frames after
## a restore `_settle_against_compositor` puts the window back where the stored
## layout says. Inside that window a scenario's placement was undone without a
## word, while `SaDockerDriver.docker` printed the position it had asked for, so
## a scenario that placed a docker and then aimed at it aimed at the old
## rectangle. A door session is always inside that window, because the door
## answers its first request as soon as the socket is up.
##
## The cache rather than the file: `save(true)` would do this and would also
## write the profile, and a capture must never write the painter's layout.
## Nothing here touches disk.
func note_placement(win: Window) -> bool:
    if win == null:
        return false
    for config: Dictionary in _dockers():
        if config["node"] as Window != win:
            continue
        var section := section_for(config)
        # A step that moves a borrowed docker moves the borrow, and the layout
        # keeps the painter's rectangle, as it does for a save.
        if is_borrowed(section):
            borrowed.follow(section, win)
            return true
        var entry: Dictionary = _cache.get(section, {})
        entry["position"] = win.position
        entry["size"] = win.size
        entry["visible"] = win.visible
        _cache[section] = entry
        _intended_positions[section] = win.position
        return true
    return false


func value_for(section: String, key: String, fallback: Variant) -> Variant:
    var entry: Dictionary = _cache.get(section, {})
    if entry.has(key):
        return entry[key]

    var cfg := ConfigFile.new()
    if cfg.load(path) == OK and cfg.has_section(section):
        var val: Variant = cfg.get_value(section, key, fallback)
        if (key == "position" or key == "size") and val is Vector2i and val != Vector2i():
            return Vector2i(Vector2(val) * SaUI.scale())  # window-agnostic fallback
        return val
    return fallback


# --- The borrow ------------------------------------------------ A docker shown
# under the pointer with a return address, which `SaBorrowedDockers` keeps. The
# store decides where it lands and its settle loop holds it there.


## Shows *win*, the docker stored under *section*, centred on *point*, and
## remembers where it was. *point* is in the space `win.position` is measured
## in, the host's logical space for an embedded docker. The rectangle is fitted
## into the host, so a borrow asked for near an edge keeps the whole docker on
## screen. Borrowing a docker already borrowed moves it and keeps the first
## address, because that is where the painter left it.
func borrow(win: Window, section: String, point: Vector2i) -> bool:
    if win == null or section.is_empty():
        return false
    borrowed.lend(win, section, _refit().kept(win, point - Vector2i(Vector2(win.size) * 0.5)))
    # The settle loop reads `_placed_value`, so what it re-asserts from here is
    # the borrowed rectangle rather than the stored one, and no note is made in
    # the cache, which is the layout.
    reapply_deferred(win, section)
    return true


## Puts the docker borrowed under *section* back where the borrow found it,
## position, size and visibility, and forgets the address. Writes nothing, as
## the borrow wrote nothing.
func give_back(section: String) -> bool:
    return borrowed.give_back(section)


## Whether the docker stored under *section* is out on a borrow.
func is_borrowed(section: String) -> bool:
    return borrowed.has(section)


## Where the settle loop and a reapply should hold a docker: the borrowed
## rectangle while one is live, the layout otherwise.
func _placed_value(section: String, key: String, fallback: Variant) -> Variant:
    var held: Variant = borrowed.held(section, key)
    return held if held != null else value_for(section, key, fallback)


# --- Internals ----------------------------------------------------------------


func _apply(win: Window, section: String, entry: Dictionary) -> void:
    if entry["position"] != Vector2i():
        # The file is the user's last word on where this belongs, so it seeds the
        # memory before the host has had a chance to clamp anything.
        _intended_positions[section] = entry["position"]
        win.position = entry["position"]
    win.size = _variants.restored(win, section, SaDockerStoredEntry.floored(win, entry["size"]))
    win.visible = entry["visible"] and not SaBootCover.holds_back(win)
    reapply_deferred(win, section)


## Re-assert geometry after the compositor has had a chance to place the window.
func reapply_deferred(win: Window, section: String) -> void:
    if win == null or not is_inside_tree():
        return

    var pos := _refit().held(win, _placed_value(section, "position", win.position))
    if pos != Vector2i():
        win.position = pos
        win.set_deferred("position", pos)

    var sz := _held_now(win, section)
    win.size = sz
    win.set_deferred("size", sz)

    if DisplayServer.get_name() != "headless":
        _settle_against_compositor(win, section)


func _settle_against_compositor(win: Window, section: String) -> void:
    if win == null or not is_inside_tree() or DisplayServer.get_name() == "headless":
        return

    for _frame in SETTLE_FRAMES:
        if not is_inside_tree() or not is_instance_valid(win):
            return
        await get_tree().process_frame
        if not is_inside_tree() or not is_instance_valid(win):
            return
        if not win.visible:
            continue

        var pos := _refit().held(win, _placed_value(section, "position", win.position))
        var sz := _held_now(win, section)
        var window_id := win.get_window_id()
        var has_id := owns_os_window(win)

        if pos != Vector2i():
            var drifted := win.position != pos
            if has_id and DisplayServer.window_get_position(window_id) != pos:
                drifted = true
            if drifted:
                win.position = pos
                if has_id:
                    DisplayServer.window_set_position(pos, window_id)

        var resized := win.size != sz
        if has_id and DisplayServer.window_get_size(window_id) != sz:
            resized = true
        if resized:
            win.size = sz
            if has_id:
                DisplayServer.window_set_size(sz, window_id)


## The size the settle loop and a reapply hold *win* at, the borrowed or
## stored one floored, or the one stored for the variant it shows.
func _held_now(win: Window, section: String) -> Vector2i:
    return _variants.restored(win, section, SaDockerStoredEntry.floored(win, _placed_value(section, "size", win.size)))


## Files *win*'s size now as the size for *variant* of it, under *section*. Its
## own write rather than [method save], which takes every docker's position too.
func save_variant_size(win: Window, section: String, variant: String) -> void:
    _variants.save(win, section, variant)


## The size stored for *variant* of *win* in this run's pixels, or `Vector2i()`
## for one nobody has sized.
func variant_size(win: Window, section: String, variant: String) -> Vector2i:
    return _variants.size_of(win, section, variant)


## The section a docker's geometry lives under: its id, or its name for a
## provider that gave none.
static func section_for(config: Dictionary) -> String:
    return String(config.get("id", config["name"]))


## Moves sections named by a docker's title onto its id, in memory, and says
## whether anything moved so the caller can write the file back.
##
## A section named by the title the docker shows is orphaned by a translated or
## renamed title, so the id names it. An older file has a `[Layers]` section
## and no `[LayersDocker]` one, and this is the whole of the migration: read it
## under the old name once, and save it under the new. Idempotent, because the
## old section is gone after the first run.
func _adopt_title_sections(cfg: ConfigFile, dockers: Array) -> bool:
    var moved := false
    for config: Dictionary in dockers:
        if not config.has("id"):
            continue
        var title := String(config["name"])
        title = FORMER_TITLES.get(title, title) if not cfg.has_section(title) else title
        var section := section_for(config)
        if title == section or not cfg.has_section(title) or cfg.has_section(section):
            continue
        for key in cfg.get_section_keys(title):
            cfg.set_value(section, key, cfg.get_value(title, key))
        cfg.erase_section(title)
        moved = true
    return moved


## Moves a palette stored at [constant PALETTE_BEFORE_HUD] by a file from before
## the HUD to the size it opens at now, in memory, and says whether it did.
func _grow_the_old_palette(cfg: ConfigFile) -> bool:
    var section := String(SaDockerIds.PALETTE)
    if cfg.has_section_key(META_SECTION, META_HUD) or cfg.get_value(section, "size", Vector2i()) != PALETTE_BEFORE_HUD:
        return false
    cfg.set_value(section, "size", PaletteDocker.DEFAULT_SIZE)
    return true


## Whether this window is one the DisplayServer can be told about.
##
## An embedded subwindow has no OS window of its own, and `get_window_id()` hands
## back the *host's* id rather than an invalid one. So a check for a valid id
## passes, and the geometry meant for a docker goes to the main window instead.
##
## Nobody saw it because Sara starts maximised and a maximised window ignores a
## size change. Unmaximise, and the settle loop drives the main window down to a
## docker's size and then keeps going: 900x560 to 50x64 to 26x32 to 2x2, one
## step per pass.
static func owns_os_window(win: Window) -> bool:
    return win != null and not win.is_embedded() and win.get_window_id() != DisplayServer.INVALID_WINDOW_ID


## Whether the stored layout was written in the unit system now in force.
##
## Only an explicit mismatch is rejected. A file with no recorded mode is not
## assumed wrong: the shipped defaults have none, and neither does any layout
## written before this key existed. Those are caught by the implausible size
## `SaDockerStoredEntry.scaled` refuses instead, which is what actually
## distinguishes corrupt geometry from merely old.
func _units_match(cfg: ConfigFile) -> bool:
    if not cfg.has_section_key(META_SECTION, META_EMBEDDED):
        return true
    return bool(cfg.get_value(META_SECTION, META_EMBEDDED)) == bool(SaSettings.embed_subwindows)


# --- Named layouts --------------------------------------------------------- A
# preset is the layout file under another name. Nothing about the format changes,
# so a preset saved today opens as the live layout tomorrow, and the live layout
# can be saved as a preset without being converted.


## The preset half of this store, which owns the named layouts and the three
## things a preset holds beyond geometry.
##
## **Everything about a preset lives there and nothing here**, because this
## file's subject is geometry. The forwarders below are what the Dockers menu,
## the Workspace page and the capture step call.
##
## Built with this store's own path rather than a reference back to the store: a
## change to the live file reaches back through `live_replaced` and
## `live_applied` instead of a call into it, and the path setter above drops
## this object so a path assigned late is the path the next one is built with.
func presets() -> SaDockerLayoutPresets:
    if _presets == null:
        _presets = SaDockerLayoutPresets.new(path)
        _presets.live_replaced.connect(forget_cached_geometry)
        _presets.live_applied.connect(restore_all)
    return _presets


## Every named layout, in the order a menu should list them: the ones that ship
## first, then the painter's own.
func list_presets() -> Array[String]:
    return presets().list()


## The preset the live layout came from, which is never nothing.
func current_preset() -> String:
    return presets().current()


## Writes the live layout out under *preset_name*, and makes it the current one.
func save_preset(preset_name: String) -> bool:
    save()
    return _announced(presets().save_as(preset_name))


## Makes *preset_name* the live layout and puts every docker where it says, at
## the UI scale and with the element state it was saved with.
func load_preset(preset_name: String) -> bool:
    return _announced(presets().load_into_live(preset_name))


## [method load_preset] spread over the frames of *tree*: the element state in
## this one, the geometry in the next and the announcement in the one after, so
## no frame holds all three. Awaited, it answers what
## [method load_preset] answers.
func load_preset_spread(preset_name: String, tree: SceneTree) -> bool:
    if not presets().begin_load(preset_name):
        return false
    await tree.process_frame
    presets().finish_load()
    await tree.process_frame
    return _announced(true)


## Writes the painter's edit into the live file and into the file of the layout
## in use, forking it first when the painter cannot write over it, and answers
## the name in use afterwards.
func fork_for_painter_edit() -> String:
    save()
    return presets().fork_for_edit()


## Forgets *preset_name*. The live layout is left exactly as it is: deleting the
## preset a painter is working in should not move their dockers.
func delete_preset(preset_name: String) -> bool:
    return _announced(presets().forget(preset_name))


func _announced(changed: bool) -> bool:
    if changed:
        presets_changed.emit()
    return changed


## Drops what this store remembers about where each docker is, which a preset
## load has to do before it reads the new one.
##
## Here rather than two `clear()` calls in the sibling, because the two
## dictionaries are this file's and a caller reaching into them is a caller that
## has to be updated when a third one arrives.
func forget_cached_geometry() -> void:
    _cache.clear()
    _intended_positions.clear()
    _painter_rects.forget()
    _variants.forget()
