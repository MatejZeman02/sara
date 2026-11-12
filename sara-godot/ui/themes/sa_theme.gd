## The interface's colours and the styleboxes built from them, read from the
## active `SaPalette` and switched in place.
##
## The colours are the fields of `palette`, read at the moment of use rather
## than constants, so a theme switch reaches them. A stylebox or a
## font colour that wants to follow a switch registers what it reads through
## `bind()` and `bind_font()`: `use()` then writes the new colours into the
## same objects, and Godot redraws whatever holds them. Nothing is rebuilt.
class_name SaTheme
extends Object

## Id -> the palette file. The ids are what `SaSettings.theme_name` has always
## stored, so a profile written before this reads the theme it named.
const PALETTES := {
    "default": "res://ui/themes/palettes/sara_green.tres",
    "photoshop": "res://ui/themes/palettes/photoshop_dark.tres",
    "krita": "res://ui/themes/palettes/krita_grey.tres",
    "solarized": "res://ui/themes/palettes/solarized_dark.tres",
    # After the four dark ones rather than among them, so a profile that stored
    # a key still finds what it named and the dropdown's order does not move
    # under a painter who knows where theirs sits.
    "paper": "res://ui/themes/palettes/paper_white.tres",
    # Made on the Colour Themes page and shipped as it was saved, so it holds
    # three states of its own where the others derive all of theirs. Last for
    # the reason Paper White is after the dark ones.
    "pink": "res://ui/themes/palettes/pink.tres",
    # The near black of Procreate's interface, for "I'm coming from". After Pink, so no palette a painter knows moves in the list.
    "procreate": "res://ui/themes/palettes/procreate_dark.tres",
    # Drawn after Clip Studio Paint's dark interface for "I'm coming from", and
    # after Procreate's for the same reason.
    "clip_studio": "res://ui/themes/palettes/clip_studio_dark.tres",
}

## A custom palette's id is this prefix and its file name, and the file is a
## `.tres` under `themes/` in the settings folder. The prefix keeps a fork out
## of `PALETTES` and a stored id readable at a glance.
const CUSTOM_PREFIX := "custom:"
const CUSTOM_SUFFIX := " (custom)"

## The ramps a palette is made of, and the reason the Colour Themes page is
## twelve rows rather than twenty-one. A group is a base colour, the shade under
## it, the shade over it, and any further colour cut from the same cloth.
##
## **While a group is linked only its base is the painter's**. The other members
## are read-only on the Colour Themes page, and the base's own move is what
## carries them, through [method slide]. Unlinking the group frees every member,
## and the page's own `is_swatch_editable` is the one function both the widget
## and a scenario ask.
##
## Only a ramp that holds in all four shipped palettes is here. The accents are
## not a group, because `accent_gauge` is a green beside Sara Green's orange
## and a cyan beside Solarized's red, so it is not a shade of the accent at
## all. `border_drag`, `accent_ceiling`, `text_shadow` and the two grips are
## independent for the same reason. Text has a shadow and no highlight, since
## no palette holds a text colour brighter than `text_primary`.
const GROUPS := {
    "background":
    {
        "title": "Background",
        "base": "bg_primary",
        "shadow": "bg_secondary",
        "highlight": "bg_panel",
        "extra": ["bg_sidebar", "bg_slider", "bg_input", "bg_track"],
    },
    "border":
    {
        "title": "Border",
        "base": "border_primary",
        "shadow": "border_secondary",
        "highlight": "border_selected",
        "extra": [],
    },
    "text":
    {
        "title": "Text",
        "base": "text_primary",
        "shadow": "text_muted",
        "highlight": "",
        "extra": [],
    },
}

static var palette: SaPalette = SaPalette.new()
static var palette_id: String = "default"

## The three spacings the interface asks for by name, in logical pixels, so a
## gap or a margin is one word. Picked by counting the tree: 12 is the margin of
## every dialog, 8 the commonest gap, and 4 the tight gap of a bar. `SaMake`
## scales them through `SaUI.px`, and a value none of them fits stays a number.
const GAP_TIGHT: int = 4
const GAP: int = 8
const PAD: int = 12

## How a name or a line too long for its control is cut, for every label and
## button that cuts one. The FORCE kind, because the plain
## `OVERRUN_TRIM_ELLIPSIS` ends a cut text in "…" only while the text it keeps
## is six characters or more, so "Group 3" would be cut to "Group" with nothing
## to say a character was gone, at every width from its own down, and a longer
## name would lose the mark in the last few pixels before it. Where a label
## wraps to lines, the mark ends the last line it keeps.
const TEXT_CUT: TextServer.OverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE

const COLOR_TRANSPARENT := Color(0, 0, 0, 0)
const COLOR_DEFAULT_BG := Color(0.5, 0.5, 0.5, 1.0)

## Bound styleboxes, `{instance id of the StyleBox: {property: palette key}}`.
## An id, so a freed style is never kept alive here, and not a `WeakRef`: a
## list of those kept thousands of them alive for every document opened.
static var _bound_styles: Dictionary[int, Dictionary] = {}
## How many entries the last sweep of `_bound_styles` left, as
## `_bound_fonts_swept` does.
static var _bound_styles_swept: int = 0
## Bound font colours, `{instance id of the Control: {theme name: palette
## key}}`. An id, so a bind allocates no object, and keyed so a bind costs the
## same however many are bound: a list scanned whole on every bind had made 59
## rebuilds of the welcome picture's layer rows take 70 seconds.
static var _bound_fonts: Dictionary = {}
## How many entries the last sweep of `_bound_fonts` left. A bind sweeps again
## once the table has doubled, spreading a sweep over the binds that grew it.
static var _bound_fonts_swept: int = 0
## The switch painting its bound boxes and font colours a slice a frame, or
## null when none is under way. See [method use_named_in_slices].
static var _slices: Slices = null

## True while the active palette holds a colour its file does not.
static var _unsaved: bool = false


## Every palette on offer, as `{id, name}`: the shipped ones in a fixed
## order, then the painter's own from the settings folder, by file name.
static func available() -> Array[Dictionary]:
    var out: Array[Dictionary] = builtin()
    for id: String in custom_ids():
        var loaded := _load_custom(id)
        if loaded != null:
            out.append({"id": id, "name": loaded.display_name})
    return out


## The shipped palettes alone, as `{id, name}`.
static func builtin() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for id: String in PALETTES:
        var loaded := load(PALETTES[id]) as SaPalette
        out.append({"id": id, "name": loaded.display_name if loaded != null else id.capitalize()})
    return out


## Switches to the palette *id* names, or to the default for an id nobody has.
static func use_named(id: String) -> void:
    # The switch to *id* painting in slices ends in what this would paint, so
    # the settings writer that follows it does not paint it all again at once.
    if _slices != null and _slices.palette_id == id:
        return
    use(_load_named(id))


## Switches to the palette *id* names as [method use_named] does, except that
## the work is spread over the frames of *tree* after this one, *budget_usec*
## of it a frame.
##
## A switch in one frame took a quarter of a second from Quick settings, and as
## long again for the walk of every window. So the shared theme stays hushed
## until the switch ends: its colours are painted now, the bound boxes and font
## colours in slices, and then the controls are told of the change in slices of
## the tree, as the walk would have told them. [method repainting] answers true
## until the last slice. Every box and control ends as [method use] leaves it,
## and one built meanwhile reads the new palette already. A [method use] or a
## second switch meanwhile takes over, so the last one asked for is painted.
static func use_named_in_slices(id: String, budget_usec: int, tree: SceneTree) -> void:
    var next := _load_named(id)
    next.derive_states()
    palette = next
    var shared := SaUI.shared_theme
    if shared != null:
        shared.set_block_signals(true)
    SaThemeDefaults.paint_colors(shared)
    SaThemeDefaults.paint_slider_icons(shared)
    _prune_bound_styles()
    _prune_bound_fonts()
    SaThemeDefaults.boxes_hold(null)
    var told: Array = []
    for node: Node in tree.root.find_children("*", "Control", true, false):
        told.append(node.get_instance_id())
    for node: Node in [tree.root] + tree.root.find_children("*", "Window", true, false):
        told.append(node.get_instance_id())
    var slices := Slices.new(id, _bound_styles.keys(), _bound_fonts.keys(), told, budget_usec)
    _slices = slices
    EventBus.theme_changed.emit(palette_id)
    _paint_slices(slices, tree)


## Whether a switch in slices still has work left.
static func repainting() -> bool:
    return _slices != null


## One slice a frame of *slices* until it is painted or another switch took
## over, which then speaks for the shared theme itself.
static func _paint_slices(slices: Slices, tree: SceneTree) -> void:
    while _slices == slices:
        await tree.process_frame
        if _slices != slices:
            return
        if slices.paint(palette):
            _slices = null
            # Every control has been told, so the end says nothing more.
            if SaUI.shared_theme != null:
                SaUI.shared_theme.set_block_signals(false)


## The palette *id* names, or the default for an id nobody has, with
## `palette_id` set to the id it resolved to.
static func _load_named(id: String) -> SaPalette:
    var loaded: SaPalette = null
    var resolved := "default"
    if PALETTES.has(id):
        loaded = load(PALETTES[id]) as SaPalette
        resolved = id
    elif is_custom(id):
        loaded = _load_custom(id)
        if loaded != null:
            resolved = id
    if loaded == null:
        loaded = load(PALETTES["default"]) as SaPalette
    if loaded == null:
        loaded = SaPalette.new()
    palette_id = resolved
    return loaded


## Where the painter's palettes live: `themes/` under the settings folder.
static func custom_dir() -> String:
    return SaSettings.get_settings_dir().path_join("themes")


## Where a deleted palette goes: `themes/deleted/`, beside the palettes.
##
## A subfolder rather than a sibling of the settings folder, because
## [method custom_ids] lists through `DirAccess.get_files_at` and a directory is
## not a file, so a palette in here does not come back on the dropdown. Moving
## the file up one level by hand is the undo.
static func deleted_dir() -> String:
    return custom_dir().path_join("deleted")


## *file_name* under [method deleted_dir], numbered when that name is already
## taken there: `sara-green.tres`, then `sara-green-2.tres`, then
## `sara-green-3.tres`. Nothing in that folder is ever written over, which is
## the whole point of keeping the file at all.
static func free_deleted_path(file_name: String) -> String:
    var directory := deleted_dir()
    var chosen := directory.path_join(file_name)
    var stem := file_name.get_basename()
    var extension := file_name.get_extension()
    var counter := 2
    while FileAccess.file_exists(chosen):
        chosen = directory.path_join("%s-%d.%s" % [stem, counter, extension])
        counter += 1
    return chosen


static func is_custom(id: String) -> bool:
    return id.begins_with(CUSTOM_PREFIX) and id.length() > CUSTOM_PREFIX.length()


static func custom_path(id: String) -> String:
    return custom_dir().path_join(id.trim_prefix(CUSTOM_PREFIX) + ".tres")


## The ids of every palette file in the settings folder, sorted.
static func custom_ids() -> Array[String]:
    var out: Array[String] = []
    var directory := custom_dir()
    if not DirAccess.dir_exists_absolute(directory):
        return out
    for file_name in DirAccess.get_files_at(directory):
        if file_name.get_extension() == "tres":
            out.append(CUSTOM_PREFIX + file_name.get_basename())
    out.sort()
    return out


## Read fresh from disk every time, because the file is what a swatch edit
## just wrote and the loader's cache would hand back the palette from before.
##
## The file is repaired before the load. A palette saved before the palette's
## script moved names it directly under `ui` with no `uid`, and Godot fails the
## whole parse on the one dead line, so the painter's theme would vanish from
## the dropdown. The repair is the one the preset store runs, `SaResourceFinder`'s,
## which points the line at wherever the script lives now and adds the `uid`
## that makes the next move harmless.
static func _load_custom(id: String) -> SaPalette:
    var path := custom_path(id)
    if not FileAccess.file_exists(path):
        return null
    SaResourceFinder.repair_resource_paths(path)
    return ResourceLoader.load(path, "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette


## The palette's colour fields, in declaration order: what the swatches on
## the Colour Themes page are, so a field added to SaPalette gets a swatch
## with no edit there.
static func color_keys(of: SaPalette = palette) -> Array[String]:
    var out: Array[String] = []
    for property: Dictionary in of.get_property_list():
        if property["type"] == TYPE_COLOR and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
            out.append(String(property["name"]))
    return out


## A copy of the active palette saved as the painter's own under *name*, and
## made active. The id is the name as a file name. Forking a built-in is how
## every custom palette starts, since a shipped file is never written.
##
## A shipped palette cannot be rewritten, so a *name* that is one of their
## display names is numbered instead: "Sara Green 2", then "Sara Green 3". A
## shipped `.tres` lives in the resource tree and a fork under the settings
## folder, so the two never collide on disk, and without this the dropdown would
## grow a second entry wearing the same words as the first. A name of the
## painter's own is written over, which is what Save As onto your own palette
## means and how a palette is updated. A file another palette holds is never
## written over, [SaThemeFileName] numbers the name until its file is free.
static func fork(name: String) -> String:
    var copy := palette.duplicate() as SaPalette
    var chosen := SaThemeFileName.free_name(free_name(name), palette_id, palette.display_name)
    copy.display_name = chosen
    var id := SaThemeFileName.id_of(chosen)
    DirAccess.make_dir_recursive_absolute(custom_dir())
    var error := ResourceSaver.save(copy, custom_path(id))
    if error != OK:
        push_error("SaTheme: could not write %s (%s)" % [custom_path(id), error_string(error)])
        return palette_id
    palette_id = id
    use(copy)
    return id


## *name* as typed, unless a shipped palette already answers to it, in which
## case the lowest "<name> N" from two up that no palette on offer answers to.
##
## The comparison ignores case and surrounding space, because the slug the file
## is named from does too: "sara green" and "Sara Green" are one file, so
## letting one of them through would overwrite the other's fork rather than
## making a second palette. The painter's own capitalisation is kept in the
## name that comes back, since the only thing being corrected is the collision.
static func free_name(name: String) -> String:
    if not _is_builtin_name(name):
        return name
    var taken := _taken_names()
    var counter := 2
    while taken.has(_fold("%s %d" % [name, counter])):
        counter += 1
    return "%s %d" % [name, counter]


## True when one of the four shipped palettes is called *name*.
static func _is_builtin_name(name: String) -> bool:
    var wanted := _fold(name)
    for entry: Dictionary in builtin():
        if _fold(String(entry["name"])) == wanted:
            return true
    return false


## Every display name on offer, shipped and custom, folded, as a set.
static func _taken_names() -> Dictionary:
    var out := {}
    for entry: Dictionary in available():
        out[_fold(String(entry["name"]))] = true
    return out


static func _fold(name: String) -> String:
    return name.strip_edges().to_lower()


## Every key of *group*, in the order the page shows them: the base first,
## then the shadow, the highlight and whatever else rides on it.
static func group_keys(group: String) -> Array[String]:
    if not GROUPS.has(group):
        return []
    var out: Array[String] = [String(GROUPS[group]["base"])]
    out.append_array(group_members(group))
    return out


## The keys of *group* that follow its base, so the base itself is not among
## them. A group with no highlight contributes none.
static func group_members(group: String) -> Array[String]:
    if not GROUPS.has(group):
        return []
    var spec: Dictionary = GROUPS[group]
    var out: Array[String] = []
    for key: String in [String(spec["shadow"]), String(spec["highlight"])]:
        if not key.is_empty():
            out.append(key)
    for key: Variant in spec["extra"]:
        out.append(String(key))
    return out


## The group *key* belongs to, as a base or as a member, and "" for a colour
## that stands on its own.
static func group_of(key: String) -> String:
    for group: String in GROUPS:
        if group_keys(group).has(key):
            return group
    return ""


## Whether *group*'s members follow its base in the active palette.
static func is_linked(group: String) -> bool:
    return palette.linked_groups.has(group)


## Links or unlinks *group* in the active palette, which has to be the
## painter's own, and saves. Answers false for a shipped palette, which a
## caller forks first exactly as a swatch does.
static func set_linked(group: String, linked: bool) -> bool:
    if not is_custom(palette_id) or not GROUPS.has(group):
        return false
    var groups := Array(palette.linked_groups)
    if linked and not groups.has(group):
        groups.append(group)
    elif not linked:
        groups.erase(group)
    groups.sort()
    palette.linked_groups = PackedStringArray(groups)
    _write_active()
    use(palette)
    return true


## *color* moved by the Oklab difference between *before* and *after*: what a
## linked group's members do when its base is dragged somewhere else.
##
## A rigid slide rather than a fixed lightness step, because the four shipped
## palettes hold ramps of four different tightnesses and a step would flatten
## every one of them into the same ramp. The relationship on screen is the
## relationship kept, and nothing here recomputes a shade from its base: there
## is no formula to recompute it with, only a difference to carry.
##
## That is why a member edited while the group was unlinked keeps its own colour
## when the group is linked again, and slides from there. Editing a member is
## how the relationship is redefined, and it is done with the link off, because
## while the link is on the page refuses the write.
##
## The alpha is the member's own, and a slide that leaves the sRGB cube is
## clamped on the way back, so dragging a base to black cannot fold a ramp
## through the far side.
static func slide(color: Color, before: Color, after: Color) -> Color:
    return _from_oklab(_to_oklab(color) + _to_oklab(after) - _to_oklab(before), color.a)


static func _to_oklab(color: Color) -> Vector3:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
    return OkhsvConversions.linear_srgb_to_oklab(linear)


static func _from_oklab(lab: Vector3, alpha: float) -> Color:
    var linear := OkhsvConversions.oklab_to_linear_srgb(lab)
    var clamped := Vector3(clampf(linear.x, 0.0, 1.0), clampf(linear.y, 0.0, 1.0), clampf(linear.z, 0.0, 1.0))
    var srgb := OkhsvConversions.srgb_transfer_function(clamped)
    return Color(srgb.x, srgb.y, srgb.z, alpha)


## Writes *color* into *key* of the active palette, which has to be a custom
## one, recolours everything bound, and saves the file unless *save* is false,
## when [method save_unsaved] writes it later. Answers false for a built-in,
## which a caller forks first.
##
## Writing a linked group's base slides every member of that group with it, so
## a background and its six shades stay one ramp under a single picker.
static func set_color(key: String, color: Color, save := true) -> bool:
    if not is_custom(palette_id) or not color_keys().has(key):
        return false
    var group := group_of(key)
    if group != "" and is_linked(group) and String(GROUPS[group]["base"]) == key:
        var before: Color = palette.get(key)
        for member: String in group_members(group):
            palette.set(member, slide(palette.get(member), before, color))
    palette.set(key, color)
    palette.hold_state(key)
    _unsaved = not save
    if save:
        _write_active()
    use(palette, false)
    return true


## Writes the active palette when a [method set_color] left it unsaved: what a
## picker's drag ends with, so the file is written once rather than per motion.
static func save_unsaved() -> void:
    if _unsaved and is_custom(palette_id):
        _write_active()


static func _write_active() -> void:
    _unsaved = false
    var error := ResourceSaver.save(palette, custom_path(palette_id))
    if error != OK:
        push_error("SaTheme: could not write %s (%s)" % [custom_path(palette_id), error_string(error)])


## Takes the painter's palette *id* off the dropdown and moves its file into
## [method deleted_dir]. A built-in cannot be deleted, and deleting the active
## one falls back to the default.
##
## Moved rather than removed, so a palette built swatch by swatch is still on
## disk after the button comes up, and rebuilding one from screenshots is the
## cost this removes. The move is why this answers true with the file kept.
static func delete_custom(id: String) -> bool:
    if not is_custom(id) or not FileAccess.file_exists(custom_path(id)):
        return false
    var source := custom_path(id)
    DirAccess.make_dir_recursive_absolute(deleted_dir())
    var target := free_deleted_path(source.get_file())
    var error := DirAccess.rename_absolute(source, target)
    if error != OK:
        push_error("SaTheme: could not move %s to %s (%s)" % [source, target, error_string(error)])
        return false
    if palette_id == id:
        use_named("default")
    return true


## Makes *next* the active palette: the static colours, every bound stylebox
## and every bound font colour follow, and the bus announces it so a control
## that draws with these colours can redraw. *whole* false is one colour
## edited rather than a switch, see [method _refresh_bound].
static func use(next: SaPalette, whole := true) -> void:
    if next == null:
        return
    _slices = null
    next.derive_states()
    palette = next
    _refresh_bound(whole)
    EventBus.theme_changed.emit(palette_id)


## Binds *style*'s properties to palette keys, `{"bg_color": "bg_primary"}`,
## writes them now, and rewrites them on every switch. Answers the style, so
## a call can sit inside an expression.
static func bind(style: StyleBox, bindings: Dictionary) -> StyleBox:
    for property: String in bindings:
        style.set(property, palette.get(bindings[property]))
    var id := style.get_instance_id()
    if not _bound_styles.has(id):
        _bound_styles[id] = {}
    _bound_styles[id].merge(bindings, true)
    SaThemeDefaults.forget_boxes()
    if _bound_styles.size() > 2 * _bound_styles_swept + 64:
        _prune_bound_styles()
    return style


## How many styleboxes have a property bound, the freed ones swept out first.
static func bound_style_count() -> int:
    _prune_bound_styles()
    return _bound_styles.size()


## Drops every `_bound_styles` entry whose style is gone.
static func _prune_bound_styles() -> void:
    for id: int in _bound_styles.keys():
        if not is_instance_valid(instance_from_id(id)):
            _bound_styles.erase(id)
    _bound_styles_swept = _bound_styles.size()


## Binds a Control's theme colour override, `font_color` unless said
## otherwise, to a palette key, now and on every switch.
##
## A second bind of the same colour on the same control replaces the first,
## because a layer row binds its locks again each time its selection changes.
## A settings page with an explained row can be built and freed many times
## with no theme switch in between, so the entries of freed controls are swept
## whenever the table has doubled.
static func bind_font(control: Control, key: String, theme_name: String = "font_color") -> void:
    control.add_theme_color_override(theme_name, palette.get(key))
    var id := control.get_instance_id()
    if not _bound_fonts.has(id):
        _bound_fonts[id] = {}
    (_bound_fonts[id] as Dictionary)[theme_name] = key
    if _bound_fonts.size() > 2 * _bound_fonts_swept + 64:
        _prune_bound_fonts()


## How many controls have a font colour bound, the freed ones swept out first.
static func bound_font_count() -> int:
    _prune_bound_fonts()
    return _bound_fonts.size()


## Drops every `_bound_fonts` entry whose control is gone.
static func _prune_bound_fonts() -> void:
    for id: int in _bound_fonts.keys():
        if not is_instance_valid(instance_from_id(id)):
            _bound_fonts.erase(id)
    _bound_fonts_swept = _bound_fonts.size()


## Writes the palette into the shared theme's colours, every bound stylebox and
## every bound font colour.
##
## **The shared theme is hushed and announces once.** Each colour or box set on
## it emits `changed`, and each window answers with a walk of its whole tree, so
## a switch of hundreds would stall for seconds. One `changed` is one walk a
## window. *whole* false is one edited colour: the theme stays quiet and
## [method SaThemeDefaults.retell] tells only what the colour moved.
static func _refresh_bound(whole: bool) -> void:
    var shared := SaUI.shared_theme
    if shared != null:
        shared.set_block_signals(true)
    var moved := _repaint_bound(whole)
    if shared != null:
        shared.set_block_signals(false)
    if not whole:
        SaThemeDefaults.retell(Engine.get_main_loop() as SceneTree, moved)
    elif shared != null:
        shared.emit_changed()


## Writes each colour of the palette that differs, the boxes hushed since a
## box's `changed` tells every control drawing it, and answers the types moved.
## An edit writes only the boxes whose key moved, through
## [method SaThemeDefaults.paint_edited_boxes].
static func _repaint_bound(whole: bool) -> Array[String]:
    # A Color on a Theme is a value, so the defaults cannot follow a switch the
    # way a bound stylebox does and have to be written again.
    var moved := SaThemeDefaults.paint_colors(SaUI.shared_theme)
    moved.append_array(SaThemeDefaults.paint_slider_icons(SaUI.shared_theme))
    if whole:
        _prune_bound_styles()
        SaThemeDefaults.boxes_hold(palette)
    else:
        SaThemeDefaults.paint_edited_boxes(_bound_styles)
    # Each key read once rather than per box, a box being one of thousands.
    var values := {}
    for id: int in _bound_styles if whole else {}:
        var style := instance_from_id(id) as StyleBox
        var bindings: Dictionary = _bound_styles[id]
        style.set_block_signals(true)
        for property: String in bindings:
            var key: String = bindings[property]
            if not values.has(key):
                values[key] = palette.get(key)
            style.set(property, values[key])
        style.set_block_signals(false)
    _prune_bound_fonts()
    for id: int in _bound_fonts:
        var control := instance_from_id(id) as Control
        var colours: Dictionary = _bound_fonts[id]
        for theme_name: String in colours:
            var color: Color = palette.get(colours[theme_name])
            if not control.has_theme_color_override(theme_name) or control.get_theme_color(theme_name) != color:
                control.add_theme_color_override(theme_name, color)
    return moved


## Create the StyleBoxFlat used by docker drag bars
static func make_drag_bar_style(vertical: bool = false) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    bind(style, {"bg_color": "title_bar", "border_color": "border_drag"})
    style.set_border_width_all(1)
    style.border_width_bottom = 0
    _pad(style, SaUI.BASE_MARGIN, 3)
    style.corner_radius_top_left = 5
    if vertical:
        style.corner_radius_bottom_left = 5
    else:
        style.corner_radius_top_right = 5
    return style


## Pads *style* by *x* logical pixels at the sides and *y* above and below.
static func _pad(style: StyleBox, x: int, y: int) -> void:
    style.set_content_margin_all(float(SaUI.px(y)))
    style.content_margin_left = float(SaUI.px(x))
    style.content_margin_right = float(SaUI.px(x))


## Create the StyleBoxFlat used by docker window backgrounds
static func make_docker_background_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    bind(style, {"bg_color": "bg_primary", "border_color": "border_primary", "shadow_color": "shadow"})
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    style.shadow_size = SaUI.px(8)
    style.shadow_offset = Vector2(0, SaUI.px(3))
    return style


## Create row styleboxes for Layers list rows
static func make_row_style(selected: bool) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    if selected:
        bind(style, {"bg_color": "border_primary", "border_color": "border_selected"})
        style.border_width_left = 2
    else:
        bind(style, {"bg_color": "bg_secondary"})

    _pad(style, 4, 2)
    return style


## The states a dropdown's rim is drawn in, which are Button's four plus focus.
const DROPDOWN_STATES := ["normal", "hover", "pressed", "focus", "disabled"]

## How wide the dropdown arrow is allowed to draw, in logical pixels.
##
## The global theme caps every button's icon at `SaUI.BASE_ICON_SIZE`, which is
## twenty and is right for a toolbox glyph. An arrow at twenty took a third of
## the preset button and clipped "Presets" to "Prese", so a dropdown asks for
## less.
const DROPDOWN_ARROW_WIDTH: int = 12


## One state's box for a dropdown. Public so a page that wants to show what a
## dropdown looks like can draw one without opening a window.
##
## Bound to the palette rather than fixed, so the rim follows a theme switch
## with everything else. The five states and their grounds are
## `SaPalette.DROPDOWN_BOXES`, and the bases of those fields are the colours
## this function matched on by hand, so the frame does not move.
static func make_dropdown_style(state: String) -> StyleBoxFlat:
    var style := _state_box(SaPalette.DROPDOWN_BOXES, state, "normal", 4, 2)
    # Room on the right for the arrow, which is drawn as the button's icon and
    # would otherwise sit against the rim.
    style.content_margin_right = float(SaUI.px(2))
    return style


## A box bound to *state*'s row of *table*, or *fallback*'s, with a rim of one
## pixel, corners of three and *x* and *y* of padding: the face a dropdown, a
## toggle, a tab and a menu row are each cut from.
static func _state_box(table: Dictionary, state: String, fallback: String, x: int, y: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    bind(style, table.get(state, table[fallback]) as Dictionary)
    style.set_border_width_all(1)
    style.set_corner_radius_all(3)
    _pad(style, x, y)
    return style


## Makes *button* read as a dropdown: a rim in every state, and the arrow the
## `OptionButton` class already carries.
##
## This is the one door for it. `OptionButton` draws a border and an arrow for
## itself and `MenuButton` does not: Godot builds a `MenuButton` flat, and it
## draws no arrow at all, which is why the preset button read as a label rather
## than as something to press.
##
## The boxes are overrides on the control rather than a theme type variation.
## A variation is what this wants to be, and Godot will not resolve one from a
## `Window.theme`: it builds a control's type list from the *project default*
## theme or from `ThemeDB`'s, and `SaUI` is deliberate about touching neither.
## The boxes still come from one palette-bound factory, so this is a shared
## definition every dropdown asks for by name and not a box built for one
## control.
##
## The arrow is fetched the way `ui/widgets/blend_mode_button.gd` fetches it, from the
## theme rather than from `assets/icons/`, so it is the one Godot's own dropdowns
## draw. It is asked for again on every theme change, because a control built
## before the theme pass keeps the default one.
static func make_dropdown(button: Button) -> void:
    if button == null:
        return
    # A MenuButton is flat by default, and a flat button draws no stylebox at
    # all, so the boxes below would be set and never seen.
    button.flat = false
    for state: String in DROPDOWN_STATES:
        button.add_theme_stylebox_override(state, make_dropdown_style(state))
    button.add_theme_constant_override("icon_max_width", SaUI.px(DROPDOWN_ARROW_WIDTH))
    button.expand_icon = false
    button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _refresh_dropdown_arrow(button)
    if not button.theme_changed.is_connected(_refresh_dropdown_arrow.bind(button)):
        button.theme_changed.connect(_refresh_dropdown_arrow.bind(button))


static func _refresh_dropdown_arrow(button: Button) -> void:
    if button != null and button.has_theme_icon(&"arrow", &"OptionButton"):
        button.icon = button.get_theme_icon(&"arrow", &"OptionButton")


## The states a toggle's box is set for. The same five a dropdown takes, and the
## list is separate because the two are separate looks and a shared constant
## would tie them together for no reason but that they match today.
const TOGGLE_STATES := ["normal", "hover", "pressed", "focus", "disabled"]


## One state's box for a toggle button.
##
## **The pressed box is the accent.** Godot's own default pressed box is a shade
## or two off the normal one, which against Sara's dark panels is a difference
## nobody can see. Pressed here is `accent_primary`, which is the one
## palette colour that is not a shade of the background in any of the four
## shipped palettes, so the difference survives a theme switch rather than being
## tuned for the green one.
##
## Bound to the palette the way `make_dropdown_style` is, so a theme switch moves
## it with everything else. The grounds are the palette's own state fields, which
## derive from the colours named here, so a palette nobody edited draws the
## box those colours give.
static func make_toggle_style(state: String) -> StyleBoxFlat:
    return _state_box(SaPalette.TOGGLE_BOXES, state, "normal", 4, 2)


## Makes *button* read as a toggle: a box in every state, with the pressed one
## visibly apart from the rest. The one door for it, the way `make_dropdown` is
## the one door for a dropdown.
##
## Per-control overrides rather than a theme type variation for the reason
## `make_dropdown` records: Godot resolves a variation from the project default
## theme or from `ThemeDB` and `SaUI` touches neither. A plain `Button` entry in
## the window's own theme would resolve, and is not what this wants either: it
## would restyle every button in Sara, and a `Theme` cannot tell a toggle from a
## button that is pressed for a frame while a painter holds it.
##
## `flat` is written off, because a flat button draws no stylebox at all and the
## boxes below would be set and never seen. That includes the layer row's
## locks: a flat toggle is one a painter cannot read as on or off.
static func make_toggle(button: Button) -> void:
    if button == null:
        return
    button.flat = false
    for state: String in TOGGLE_STATES:
        button.add_theme_stylebox_override(state, make_toggle_style(state))


## The parts of a slider, in the order `SaPalette.SLIDER_BOXES` names them.
const SLIDER_PARTS := ["track", "handle", "hover"]


## One part of a slider, bound to the palette.
##
## `FactorSlider` draws the track and the handle, and the engine's own `HSlider`,
## `VSlider` and `ProgressBar` draw all three through `SaThemeDefaults`. *margin*
## is the content margin on every side, which is what makes an engine slider's
## track as thick as it is, and 0 for a box that is only drawn.
static func make_slider_style(part: String, margin: int = 0) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    bind(style, SaPalette.SLIDER_BOXES.get(part, SaPalette.SLIDER_BOXES["track"]) as Dictionary)
    style.set_content_margin_all(float(SaUI.px(margin)))
    if part != "track":
        # The fill sits inside the track, so its left corners round with it and
        # its right ones are the pair `FactorSlider` drew.
        style.corner_radius_top_left = SaUI.px(4)
        style.corner_radius_bottom_left = SaUI.px(4)
        style.corner_radius_top_right = SaUI.px(2)
        style.corner_radius_bottom_right = SaUI.px(2)
        return style
    style.set_border_width_all(1)
    style.set_corner_radius_all(SaUI.px(4))
    return style


## The four states a tab is drawn in, under the engine's own stylebox names
## (`tab_selected` and not `selected`), because a theme sets a stylebox by the
## name the control's class asks for.
const TAB_STATES := ["tab_unselected", "tab_hovered", "tab_selected", "tab_disabled"]


## One state's box for a tab. Hand it the name the engine's `TabBar` uses.
##
## Nothing in the tree builds a tab today, so this door is what a module's or a
## page's first one walks through, and the ramps its fields start from are the
## ones every other control face is cut from.
static func make_tab_style(state: String) -> StyleBoxFlat:
    return _state_box(SaPalette.TAB_BOXES, state, "tab_unselected", 8, 4)


## The four states a row of a menu is drawn in.
const MENU_ROW_STATES := ["normal", "hover", "checked", "disabled"]


## One state's box for a row of a menu or of a `SaChoicePopup`.
static func make_menu_row_style(state: String) -> StyleBoxFlat:
    return _state_box(SaPalette.MENU_ROW_BOXES, state, "normal", 4, 2)


## Makes *button* read as a row of a list: hovered, chosen and disabled are the
## palette's own fields.
##
## **The resting box is not set here**, though the table has one. A
## `SaChoicePopup` row rests flat on the popup's panel, and
## `SaChoiceRow.set_highlighted` owns the button's `normal` slot: it overrides it
## while the keyboard rests on the row and removes the override when it leaves,
## which would take this one with it. The strip draws the resting state, and the
## panel behind a row is `menu_row`'s base, so the two agree in colour either way.
##
## The engine draws a toggle row's chosen state as `pressed`, so the table's
## `checked` field is bound there.
##
## **Every state is as tall as the resting one.** A `Button` is as tall as the
## box of the state it is in, and a row's hovered, chosen and disabled boxes had
## two pixels top and bottom where the push button's resting box has four, so a
## menu with greyed rows among live ones stepped under them. The three take the
## resting margin here rather than in [method make_menu_row_style], whose boxes
## are also the samples the strip and the Colour Themes page draw at their own
## size. `align_to_largest_stylebox` holds the one box this cannot reach, the
## keyboard mark `SaChoiceRow.set_highlighted` puts in the `normal` slot, which
## has no margin at all and stood a row at 29 pixels among rows of 33.
static func make_menu_row(button: Button) -> void:
    if button == null:
        return
    button.add_theme_constant_override("align_to_largest_stylebox", 1)
    button.add_theme_stylebox_override("hover", _menu_row_box("hover"))
    button.add_theme_stylebox_override("pressed", _menu_row_box("checked"))
    button.add_theme_stylebox_override("disabled", _menu_row_box("disabled"))


## One state's box for a row of a list, as tall as the push button's resting box.
static func _menu_row_box(state: String) -> StyleBoxFlat:
    var style := make_menu_row_style(state)
    style.content_margin_top = float(SaUI.px(SaThemeDefaults.MARGIN_Y))
    style.content_margin_bottom = float(SaUI.px(SaThemeDefaults.MARGIN_Y))
    return style


## The bound boxes, font colours and controls a switch in slices has still to
## paint and tell, and how long a frame it works for.
class Slices:
    extends RefCounted

    ## The id the switch was asked for, which a writer asking for it again meets.
    var palette_id: String
    var _style_ids: Array
    var _font_ids: Array
    var _told_ids: Array
    var _budget_usec: int
    var _next_style: int = 0
    var _next_font: int = 0
    var _next_told: int = 0

    func _init(id: String, style_ids: Array, font_ids: Array, told_ids: Array, budget_usec: int) -> void:
        palette_id = id
        _style_ids = style_ids
        _font_ids = font_ids
        _told_ids = told_ids
        _budget_usec = budget_usec

    ## Works in *with* until the frame's budget is spent, the boxes first, then
    ## the font colours, then telling the controls, and answers whether all of
    ## it is done.
    func paint(with: SaPalette) -> bool:
        var stop := Time.get_ticks_usec() + _budget_usec
        while _next_style < _style_ids.size():
            var style_id: int = _style_ids[_next_style]
            _next_style += 1
            var style := instance_from_id(style_id) as StyleBox
            var bindings: Dictionary = SaTheme._bound_styles.get(style_id, {})
            if style != null:
                for property: String in bindings:
                    style.set(property, with.get(bindings[property]))
            if Time.get_ticks_usec() >= stop:
                return false
        while _next_font < _font_ids.size():
            var id: int = _font_ids[_next_font]
            _next_font += 1
            var control := instance_from_id(id) as Control
            # The table as it is now rather than as it was, since a control
            # bound again meanwhile was bound to another key in the new palette.
            var colours: Dictionary = SaTheme._bound_fonts.get(id, {})
            if control != null:
                for theme_name: String in colours:
                    control.add_theme_color_override(theme_name, with.get(colours[theme_name]))
            if Time.get_ticks_usec() >= stop:
                return false
        while _next_told < _told_ids.size():
            var node := instance_from_id(_told_ids[_next_told]) as Node
            _next_told += 1
            # What the walk of a window that wears the theme sends each node.
            if node != null and node.is_inside_tree():
                node.notification(Control.NOTIFICATION_THEME_CHANGED)
            if Time.get_ticks_usec() >= stop:
                return false
        return true
