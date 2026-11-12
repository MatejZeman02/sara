## Centralized user settings manager: the door the rest of Sara reads and
## writes a preference through.
##
## Handles loading/saving preferences to ~/.config/sara/ on Linux,
## %APPDATA%/sara/ on Windows, and ~/Library/Application Support/sara/ on macOS.
##
## **The preferences themselves are the class this extends**.
## `SaSettingsValues` declares every preference once, typed, with its clamping
## and its doc comment, so `SaSettings.ui_scale` is that property and not a
## forward to it. What this adds is what the values are not: `SaSettingsFile`,
## the profile on disk and the migrations behind it, `SaSettingsLayout`, the
## reorderable layout, and `SaSettingsProofs`, which answers what a stored view
## transform id can be shown as. It was once a facade over the same objects, 55
## properties of six lines that each forwarded one preference, 14 constants
## re-declared and five signals relayed.
##
## `SaSettingsApply`, what a changed preference does to the running application,
## is its own autoload because `core` naming `ui` is what it existed to do.
@tool
extends SaSettingsValues

## An element gained a view after something may already have listed what can be
## placed. Relayed from `SaElementViews`, which says when it fires.
signal element_view_registered(category: String, element: String)

const SETTINGS_FILE := SaSettingsFile.SETTINGS_FILE
## Bumped when a stored value changes meaning. See `SaSettingsMigrations` for
## what each version past 1 changed.
const SETTINGS_VERSION: int = SaSettingsFile.SETTINGS_VERSION
const BACKUP_SUFFIX := SaSettingsFile.BACKUP_SUFFIX
const BROKEN_SUFFIX := SaSettingsFile.BROKEN_SUFFIX

## The reorderable layout registry: what a category holds, what it is called,
## and what the painter hid or moved. `SaSettingsLayout` owns all of it.
##
## The four dictionaries are aliased here rather than left behind, because
## `SaSettings.DEFAULT_ORDERS`, `ROW_SENTINEL` and `CATEGORY_TITLES` are read
## by that name from the top menu bar, the Preferences layout page and five
## suites, and a cut moves code without moving a name anyone types.
const DEFAULT_HIDDEN := SaSettingsLayout.DEFAULT_HIDDEN
const ROW_SENTINEL := SaSettingsLayout.ROW_SENTINEL
const DEFAULT_ORDERS := SaSettingsLayout.DEFAULT_ORDERS
const CATEGORY_TITLES := SaSettingsLayout.CATEGORY_TITLES

## The elements that are where things go rather than things, never placed in
## another docker. See [constant SaElementViews.PLACES].
const ELEMENT_PLACES := SaElementViews.PLACES

## The two top bar elements Page Edges took the place of, for the bar and a
## layout's readers outside this package. See
## [constant SaSettingsMigrations.PAGE_EDGES_RETIRED].
const PAGE_EDGES_RETIRED := SaSettingsMigrations.PAGE_EDGES_RETIRED

## The reorderable layout, handed the file it reads its three sections from.
var _layout: SaSettingsLayout

## The profile on disk, and the migrations behind it.
var _file: SaSettingsFile

## Whether a stored view transform id is one the registry still holds, and the
## two colour spaces the display chain asks for. Public so the Display page's
## Monitor profile row can ask it what the system said for the monitor the
## window is on, [method SaSettingsProofs.system_reading], and written here
## only.
var proofs: SaSettingsProofs

## Which layout elements can be placed in another docker, and how a second view
## of one is built.
var _views: SaElementViews


func _init() -> void:
    SaBootMarks.mark(&"settings_init_begin")
    _file = SaSettingsFile.new()
    _layout = SaSettingsLayout.new(_file, self)
    proofs = SaSettingsProofs.new()
    _views = SaElementViews.new(_layout)
    _layout.profile_changed.connect(profile_changed.emit)
    _views.view_registered.connect(element_view_registered.emit)
    changed.connect(_write)
    SaBootMarks.mark(&"settings_init_end")


## The parsed profile. Read by the Preferences pages and the suites, and
## replaced by the suite that models a first launch.
var config: ConfigFile:
    set(val):
        _file.config = val
    get:
        return _file.config

## Where the profile is. Written from outside by the test runner alone, which
## points every suite at a scratch file rather than the painter's own.
var settings_path: String:
    set(val):
        _file.settings_path = val
    get:
        return _file.settings_path


## Where the settings file and the docker layout live. See
## [method SaSettingsFile.directory].
func get_settings_dir() -> String:
    return SaSettingsFile.directory()


## Reads the profile, migrating it first when an older build wrote it.
func load_settings() -> void:
    _file.load_from_disk(self)


## Writes the profile, keeping the previous file as the backup.
func save_settings() -> void:
    _file.save()


## Puts every preference back to its default and empties the stored layout.
func reset_to_defaults() -> void:
    _file.reset(self)


## A module's own preference, *default* when the profile holds none. A
## module reaches it through `SaContext.preference`, which knows its id.
## *formerly* is where the skeleton kept it once, see [method
## SaSettingsFile.module_value].
func module_preference(module_id: StringName, key: StringName, default: Variant = null, formerly: Array = []) -> Variant:
    return _file.module_value(module_id, key, default, formerly)


## Stores a module's own preference and announces it on [signal changed] as
## the module id, a slash and the key, so a watcher tells two modules' keys of
## one name apart. Nothing is announced when the value is the one stored.
func set_module_preference(module_id: StringName, key: StringName, value: Variant) -> void:
    if _file.set_module_value(module_id, key, value):
        changed.emit(StringName("%s/%s" % [module_id, key]))


## The stored order and the stored visibility, under the names they carried
## while they were fields of this file. Both hand back the registry's own
## dictionary rather than a copy, because `test_sa_settings` erases an entry
## of the second one in place. Written by `SaSettingsFile` when a profile is
## read or reset.
var layout_orders: Dictionary[String, Array]:
    set(value):
        _layout.orders = value
    get:
        return _layout.orders

@warning_ignore("unused_private_class_variable")
var _layout_visibilities: Dictionary[String, Dictionary]:
    set(value):
        _layout.visibilities = value
    get:
        return _layout.visibilities

## The stored per-docker option values, the shape `layout_orders` above carries:
## the file half fills it from the profile and empties it on a reset. Plain
## because the suites that set an option without saving the profile write it
## from outside, and everything else uses the calls below.
var layout_docker_options: Dictionary[String, Dictionary]:
    set(value):
        _layout.docker_option_values = value
    get:
        return _layout.docker_option_values

## The top bar's order, as a property so a script or a scenario can set it.
var top_bar_order: Array:
    set(value):
        set_layout_order("TopMenuBar", value.duplicate())
    get:
        return get_layout_order("TopMenuBar")

# The calls from here to `display_profile_space` are a facade on purpose: hundreds of
# readers call them by this name, so each forwards to the layout, whose class and
# element views are private here, or combines the proof and display fields the
# proofs need. What only a test asked of the proofs is read on `proofs`, which is
# public, and has no forwarder.


## Gives `category_id` a reorderable Preferences page, for as long as *holder*
## lasts when one is named.
func register_layout_category(category_id: String, title: String, elements: Array, holder: Object = null) -> bool:
    return _layout.register_layout_category(category_id, title, elements, holder)


## Takes a runtime category back, for a test or an unloading module.
func unregister_layout_category(category_id: String) -> void:
    _layout.unregister_layout_category(category_id)


## Gives *element* a place in *category*'s list and a title in Preferences.
##
## *view* builds a fresh control showing and driving the element's state, and
## an element registered with one can be placed in a docker other than its
## own, as every placeable element of a custom docker is. A module's element
## takes one through this same call. See [SaElementViews].
func register_layout_element(
    category: String, element: String, title: String, hidden := false, after := "", view := Callable()
) -> void:
    _layout.register_layout_element(category, element, title, hidden, after)
    if view.is_valid():
        _views.register(category, element, view)


## Takes *element* back, its view with it.
func unregister_layout_element(category: String, element: String) -> void:
    _layout.unregister_layout_element(category, element)
    _views.unregister(category, element)


## Whether *element* of *category* can be placed in another docker: it was
## registered with a view, and it is not a drag bar, a grip or the bar's
## Second Row.
func is_placeable(category: String, element: String) -> bool:
    return _views.placeable(category, element)


## Every placeable element by category, with the titles Preferences shows. See
## [method SaElementViews.placeable_elements] for the shape.
func placeable_elements() -> Array[Dictionary]:
    return _views.placeable_elements()


## A fresh view of *element*, or null when it is not placeable.
func build_element_view(category: String, element: String) -> Control:
    return _views.build(category, element)


## The row label Preferences shows for *element*.
func element_title(category: String, element: String) -> String:
    return _layout.element_title(category, element)


## The same label in the painter's language, the one place an element's title
## meets a catalogue. A module registers its own elements' titles and a stored
## name with no title is shown as it is, so no reading of the source holds them all.
func translated_element_title(category: String, element: String) -> String:
    return TranslationServer.translate(element_title(category, element))


## Every reorderable category, in declaration order, as (id, title) pairs.
func reorderable_categories() -> Array[Dictionary]:
    return _layout.reorderable_categories()


## The order *category* is in, always a copy.
func get_layout_order(category: String) -> Array:
    return _layout.get_layout_order(category)


func set_layout_order(category: String, order: Array) -> void:
    _layout.set_layout_order(category, order)


func get_element_visible(category: String, element: String) -> bool:
    return _layout.get_element_visible(category, element)


func set_element_visible(category: String, element: String, visible: bool) -> void:
    _layout.set_element_visible(category, element, visible)


## Orders and switches of a whole layout written as one save and one
## `profile_changed`. See [method SaSettingsLayout.set_many].
func set_layout_many(orders: Dictionary, shown: Array) -> void:
    _layout.set_many(orders, shown)


## Whether *category* has a shipped arrangement to go back to. See
## [method SaSettingsLayout.ships].
func layout_ships(category: String) -> bool:
    return _layout.ships(category)


## Puts one category's order and hidden elements back as shipped, or as its
## module registered them, the Reset to shipped of a docker's Elements… page.
func reset_layout_category(category: String) -> void:
    _layout.reset_category(category)


## Gives *category* a per-docker option: a setting on that docker's Preferences
## page that is not a row in its element list.
func register_docker_option(category: String, key: String, spec: Dictionary) -> bool:
    return _layout.register_docker_option(category, key, spec)


func unregister_docker_option(category: String, key: String) -> void:
    _layout.unregister_docker_option(category, key)


## Every per-docker option *category* registered, in registration order.
func docker_options(category: String) -> Array[Dictionary]:
    return _layout.docker_options(category)


## What a per-docker option is set to, or its default.
func get_docker_option(category: String, key: String) -> Variant:
    return _layout.get_docker_option(category, key)


func set_docker_option(category: String, key: String, value: Variant) -> void:
    _layout.set_docker_option(category, key, value)


## The proof gamut as a colour space: a preset, or the device's ICC file, and
## sRGB when that file cannot be read. See [method SaSettingsProofs.proof_space].
func proof_profile_space() -> SaColorSpace:
    return proofs.proof_space(proof_profile, proof_profile_file, proof_custom_space)


## The display profile as a colour space, for the matrix the view finishes with:
## a preset, or the monitor's own ICC file, and sRGB when that file cannot be
## read. See [method SaSettingsProofs.display_space].
func display_profile_space() -> SaColorSpace:
    return proofs.display_space(display_profile, display_profile_file, display_custom_space)


## While the system's profile is the display's, the view is told when the window
## crosses to another screen, so the space follows it to the next monitor's
## profile, and when the system's answer arrives after the first frame.
func _process(_delta: float) -> void:
    if Engine.is_editor_hint() or display_profile != DISPLAY_PROFILE_SYSTEM:
        return
    if proofs.screen_moved(DisplayServer.window_get_current_screen()):
        EventBus.tonemap_changed.emit(tonemap_highlights)


## What a stored proof mode is shown as: a mode the registry holds, or the
## fallback. The values answer the stored id itself, having no registry.
func _proof_read(stored_id: String, fallback: String) -> String:
    return proofs.resolved(stored_id, fallback)


## A preference moved, so the profile writes what is stored for it.
func _write(property: StringName) -> void:
    _file.write(property, stored(String(property)))


## `settings_loaded` is the end mark of this `_ready`.
func _ready() -> void:
    SaBootMarks.mark(&"settings_ready_begin")
    settings_path = get_settings_dir().path_join(SETTINGS_FILE)
    load_settings()
    SaBootMarks.mark(&"settings_loaded")
    # The sweep calibration's table sits beside the settings file rather than
    # in it, because it is 256 numbers, and it is read here so the first stroke
    # of a session already goes through it.
    SaTablet.load_correction()


## *order* with a retired element turned into Page Edges, once, which a saved
## layout and a custom docker are read through as they load. See
## [method SaSettingsMigrations.page_edges_order].
static func page_edges_order(order: Array) -> Array:
    return SaSettingsMigrations.page_edges_order(order)
