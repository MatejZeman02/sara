## The layouts Sara ships, and everything a preset holds beyond geometry.
##
## Three things at once: a list a fresh profile can already
## pick from, a preset that carries the font scale and each docker's element
## state as well as its windows, and shipped presets that fork rather than being
## written over. Each is a test here, and the scenario proves the first two on
## the running app.
##
## **There is no exception to the fork.** No `user` preset has an edit-in-place
## rule, since whatever layout a painter is in, an edit must not answer with
## `user`. The cases below pin the rule.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const HOST := Vector2i(1200, 800)
## The rows a fresh profile hides that Useful ships on. Default and a fresh
## profile take the Colour Picker down to its shape and its pair, and Useful and
## Full keep their switches, so Useful still shows these three.
const USEFUL_SHOWS: Array[String] = ["ColorPicker/Swatches", "ColorPicker/Recent Colours", "ColorPicker/Hex Input"]
## The engine that paints under the Brush and adds rows of its own to the bar,
## which the fixture registry does not load. Loaded rather than preloaded, the
## way the fixtures load a module, so the suite parses in a checkout without it.
const NOISE_ENGINE := "res://modules/sara-noise-brush-engine/module.gd"
static var scratch_layout_path: String = SaDataRoot.path("test_layout_presets.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

var _root: Node = null
var _viewport: SubViewport = null
var _docker: Window = null
var _store: DockerLayoutStore = null
## What `_bar_specs` read, kept for the rest of the suite.
var _bar_specs_read: Array[SaOptionSpec] = []

## The whole of what a preset writes, so a test that loads one puts every
## category back rather than the two keys it happened to name. Loading `full`
## writes an element visibility for every category there is, and a suite that
## restored three of them left the rest of the run reading a shipped preset's
## profile: `test_stabilizer_toggle` failed on it, three suites later.
var _saved_state := ConfigFile.new()


func before_each() -> void:
    _saved_state = ConfigFile.new()

    _root = Node.new()
    _root.name = "LayoutPresetsTestHost"
    EventBus.add_child(_root)
    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)
    var host := Control.new()
    host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(host)
    _docker = Window.new()
    _docker.size = Vector2i(200, 150)
    host.add_child(_docker)

    _store = DockerLayoutStore.new()
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": _docker}]
    _store.save_allowed = func() -> bool: return true
    _store.presets().capture(_saved_state)


func after_each() -> void:
    _store.presets().apply(_saved_state)
    if is_instance_valid(_store):
        _store.free()
    var dir := DirAccess.open(scratch_presets_dir)
    if dir != null:
        for file_name in dir.get_files():
            DirAccess.remove_absolute(scratch_presets_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_layout_path)
    # Freed now rather than queued: the runner goes on to the next suites in the
    # same frame, and a queued host kept its docker window visible and focused
    # for them, which `test_one_press_one_answer.gd` reads as a window holding
    # the keyboard if this suite runs ahead of it.
    if is_instance_valid(_root):
        _root.free()


## The submenu was empty because none shipped, so the layouts are files under
## `res://`, listed in a fixed order.
func test_every_shipped_layout_leads_the_list() -> void:
    var listed := _store.list_presets()
    assert_eq(
        SaDockerLayoutPresets.SHIPPED.size(),
        8,
        "Eight ship, Procreate and Clip Studio Paint among them, and `user` is gone with its exception"
    )
    assert_false(SaDockerLayoutPresets.SHIPPED.has("user"), "and `user` is not one of them")
    assert_true(listed.size() >= SaDockerLayoutPresets.SHIPPED.size(), "The list holds at least those seven")
    for i in SaDockerLayoutPresets.SHIPPED.size():
        assert_eq(listed[i], SaDockerLayoutPresets.SHIPPED[i], "and they lead it in the shipped order")
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(_store.presets().read_path(listed[i])), OK, "'%s' is a file that parses" % listed[i])


## What each shipped layout is for is a claim about which dockers it opens, and
## a list of identical layouts would be a list in name only.
func test_the_shipped_layouts_differ_in_what_they_open() -> void:
    var open_count := {}
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        var count := 0
        for section in cfg.get_sections():
            if not String(section).begins_with("_") and bool(cfg.get_value(section, "visible", false)):
                count += 1
        open_count[preset_name] = count
    assert_true(open_count["minimalistic"] < open_count["default"], "minimalistic opens fewer than default")
    assert_true(open_count["default"] < open_count["useful"], "useful opens more than default")
    assert_true(open_count["useful"] < open_count["full"], "and full opens the most")


## A preset holds the font scale and each category's element state, which the
## note names beside the geometry and which the layout file never carried.
func test_a_preset_carries_the_scale_and_the_element_state() -> void:
    SaSettings.ui_scale = 0.8
    SaSettings.set_element_visible("LayersDocker", "Opacity", false)
    SaSettings.set_layout_order("LayersDocker", ["Drag Handle", "Resizer", "Opacity", "Layer List"])
    assert_true(_store.save_preset("Small"), "The save goes through")

    SaSettings.ui_scale = 1.4
    SaSettings.set_element_visible("LayersDocker", "Opacity", true)
    SaSettings.set_layout_order("LayersDocker", ["Drag Handle", "Resizer", "Layer List", "Opacity"])

    assert_true(_store.load_preset("Small"), "and the load reports success")
    assert_almost_eq(SaSettings.ui_scale, 0.8, 1e-6, "The font scale comes back")
    assert_false(SaSettings.get_element_visible("LayersDocker", "Opacity"), "the hidden element comes back hidden")
    var order: Array = SaSettings.get_layout_order("LayersDocker")
    assert_eq(
        order.slice(0, 4),
        ["Drag Handle", "Resizer", "Opacity", "Layer List"],
        "and the order comes back as it was saved, with the rows it did not name after it"
    )


## "The defaults cannot be overwritten." Every shipped name forks, with no
## exception, and the shipped file is untouched because `res://` is not
## writable.
func test_saving_over_a_shipped_preset_forks_it() -> void:
    assert_true(_store.save_preset("minimalistic"), "Saving under a shipped name reports success")
    assert_eq(_store.current_preset(), "minimalistic (custom)", "but the layout in use is the fork")
    assert_true(_store.list_presets().has("minimalistic"), "and the shipped row is still offered")
    assert_true(_store.list_presets().has("minimalistic (custom)"), "beside the painter's own copy")

    for shipped: String in SaDockerLayoutPresets.SHIPPED:
        assert_true(_store.load_preset(shipped), "'%s' loads" % shipped)
        assert_eq(_store.current_preset(), shipped, "and is in use")
        assert_true(_store.save_preset(shipped), "saving over it reports success")
        assert_eq(_store.current_preset(), shipped + SaDockerLayoutPresets.FORK_SUFFIX, "as the fork of it")


## A painter's own name is theirs, so an edit under one writes it in place
## rather than making `my layout (custom)` and then `my layout (custom) (custom)`.
func test_a_painters_own_name_is_edited_in_place() -> void:
    assert_true(_store.save_preset("my layout"), "The save goes through")
    assert_eq(_store.current_preset(), "my layout", "under the name the painter typed")
    assert_eq(_store.fork_for_painter_edit(), "my layout", "and an edit stays in it")
    assert_false(_store.list_presets().has("my layout (custom)"), "with no fork of it anywhere")

    # The name `user` is one of these now, and nothing about it is special.
    assert_true(_store.save_preset("user"), "A layout saved as `user` saves")
    assert_eq(_store.current_preset(), "user", "under that name, because it is the painter's own")
    assert_eq(_store.fork_for_painter_edit(), "user", "and it is edited in place like any other")


## A profile that has never chosen a layout is in `default`, and its first edit
## makes `default (custom)`.
##
## **A live file with no preset key is the case to hold.** The Workspace page
## must not call that "Unsaved layout" with an edit under it forking nothing, or
## the only name a painter ever sees is `user`.
func test_a_profile_with_no_preset_is_in_default_and_forks_it() -> void:
    DirAccess.remove_absolute(scratch_layout_path)
    assert_eq(_store.current_preset(), "default", "A profile with no layout file is in default")

    _store.save()
    assert_eq(_store.current_preset(), "default", "and still is once the live layout is written")

    assert_eq(_store.fork_for_painter_edit(), "default (custom)", "The first edit forks the default")
    assert_eq(_store.current_preset(), "default (custom)", "which is what is in use afterwards")
    assert_true(_store.list_presets().has("default"), "and the shipped default is still a row")


## The fork happens on the painter's edit rather than on every save, and a
## second edit goes on writing the fork rather than making a fork of the fork.
func test_an_edit_under_a_shipped_preset_forks_once() -> void:
    _store.load_preset("useful")
    assert_eq(_store.current_preset(), "useful", "The shipped preset is in use")

    assert_eq(_store.fork_for_painter_edit(), "useful (custom)", "The first edit forks it")
    assert_eq(_store.current_preset(), "useful (custom)", "and the fork is what is in use")
    assert_eq(_store.fork_for_painter_edit(), "useful (custom)", "A second edit stays in the fork")
    assert_false(_store.list_presets().has("useful (custom) (custom)"), "so nothing forks a fork")


## Applying a preset writes settings, and every one of those writes announces
## itself. Without the guard the load would read as an edit and fork the preset
## it had just loaded, before the painter touched anything.
func test_loading_a_preset_does_not_fork_it() -> void:
    _store.load_preset("full")
    assert_eq(_store.current_preset(), "full", "The shipped preset is in use after the load")
    assert_false(_store.list_presets().has("full (custom)"), "and nothing forked while it was applied")


## Deleting a painter's copy of a shipped name puts the shipped row back rather
## than taking the row out of the list.
func test_deleting_a_forked_shipped_name_leaves_the_shipped_one() -> void:
    assert_true(_store.save_preset("useful"), "The save forks the shipped name")
    assert_true(_store.delete_preset("useful (custom)"), "and the delete of the fork reports success")
    assert_true(_store.list_presets().has("useful"), "and useful is still a row, because it ships")
    assert_false(_store.list_presets().has("useful (custom)"), "while the fork is gone")


## The Workspace page saves, loads and deletes a layout without the Dockers menu
## hearing, and the menu is filled only when something tells it to. So the store
## says so itself, once per change that took, and not for one that did not.
func test_a_save_a_load_and_a_delete_each_say_the_layouts_changed() -> void:
    var heard: Array[int] = [0]
    _store.presets_changed.connect(func() -> void: heard[0] += 1)

    assert_true(_store.save_preset("mine"), "a painter's layout saves")
    assert_eq(heard[0], 1, "and the store says the layouts changed")
    assert_true(_store.load_preset("useful"), "a shipped layout loads")
    assert_eq(heard[0], 2, "and says so again")
    assert_true(_store.delete_preset("mine"), "the painter's layout is forgotten")
    assert_eq(heard[0], 3, "and a third time")
    assert_false(_store.load_preset("no such layout"), "a load of a name nobody saved fails")
    assert_eq(heard[0], 3, "and says nothing")


## A shipped preset writes an explicit visibility for every element, so
## switching from one to another puts back what the last one hid. That makes
## each of them a claim about the app's own defaults, and all but "full" have
## to agree with `DEFAULT_HIDDEN` or picking "default" turns on rows a fresh
## profile hides.
##
## The run this cost was red three suites later, in `test_stabilizer_toggle`:
## the scenario had loaded a preset, the preset had written
## `TopMenuBar/stabilizer_mode` on, and the settings file it wrote is the one
## the offscreen suite reads.
## What a fresh profile hides in *category*: the skeleton's `DEFAULT_HIDDEN`,
## and on the top bar every option a tool's spec hides there, which has lived
## on the spec rather than in the skeleton.
func _hidden_by_default(category: String) -> Array:
    var out: Array = SaSettings.DEFAULT_HIDDEN[category].duplicate()
    if category != "TopMenuBar":
        return out
    for spec: SaOptionSpec in _bar_specs():
        if spec.bar_hidden and not out.has(String(spec.key)):
            out.append(String(spec.key))
    return out


## Every option a shipped tool puts on the bar: the stamp brush's and the base
## module's through the fixture registry, and the noise engine's, whose Strength
## and Thickness rows a layout that missed them left at the end of the bar.
##
## Read once for the suite and kept. A tool registry made by the fixture holds
## its modules' registrations in reference cycles, through a captured lambda,
## that last until the run ends, and this was asked for every element of every
## category of every layout: about a thousand registries, 168,000 objects and
## 750 MiB of the run's memory.
func _bar_specs() -> Array[SaOptionSpec]:
    if not _bar_specs_read.is_empty():
        return _bar_specs_read
    var out: Array[SaOptionSpec] = _bar_specs_read
    var registry: SaToolRegistry = Fixtures.make_tool_registry()
    for descriptor: SaToolDescriptor in registry.list_descriptors():
        for spec: SaOptionSpec in descriptor.options:
            if spec.bar:
                out.append(spec)
    var noise := load(NOISE_ENGINE) as Script
    if noise != null:
        for spec: SaOptionSpec in noise.call("options"):
            if spec.bar:
                out.append(spec)
    return out


## The rows a fresh profile has in *category*, which a shipped layout's order
## has to name every one of: the skeleton's own and, on the top bar, every key a
## tool puts there. A row the order lacks is put after everything else when
## the layout loads, which is how Tools ended up after Help.
func _fresh_rows(category: String) -> Array[String]:
    var out: Array[String] = []
    out.assign(SaSettings.DEFAULT_ORDERS[category])
    if category == "TopMenuBar":
        for spec: SaOptionSpec in _bar_specs():
            if not out.has(String(spec.key)):
                out.append(String(spec.key))
    return out


func test_only_full_shows_what_the_app_hides_by_default() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        for category: String in SaSettings.DEFAULT_HIDDEN:
            for element: String in _hidden_by_default(category):
                var key := "%s/%s" % [category, element]
                if not cfg.has_section_key(SaDockerLayoutPresets.VISIBILITY_SECTION, key):
                    continue
                var shown := bool(cfg.get_value(SaDockerLayoutPresets.VISIBILITY_SECTION, key))
                var ships_on := preset_name == "full" or (preset_name == "useful" and USEFUL_SHOWS.has(key))
                assert_eq(shown, ships_on, "'%s' in %s" % [key, preset_name])


## Every shipped preset places every docker it names, open or closed, inside
## 1920 by 1080, and no two of them overlap.
##
## "full" is the one that makes this a rule rather than a nicety: it opens
## every docker, and a file that carried geometry for only six of them would pile
## the other four up in the top left the moment anything opened them. The
## picker's own test pins it against the Layers docker in `docker_layout_default.cfg` for the same reason, one pair at
## a time. The closed ones are held to it as well, so a docker the Window menu
## opens lands clear of the open ones.
func test_no_two_dockers_of_a_shipped_preset_overlap() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        var rects: Array[Rect2i] = []
        var names: Array[String] = []
        for section in cfg.get_sections():
            if String(section).begins_with("_"):
                continue
            var pos: Vector2i = cfg.get_value(section, "position", Vector2i.ZERO)
            var size: Vector2i = cfg.get_value(section, "size", Vector2i.ZERO)
            assert_true(size.x > 0 and size.y > 0, "%s in %s has a size" % [section, preset_name])
            assert_true(pos.x + size.x <= 1920 and pos.y + size.y <= 1080, "%s in %s fits 1920 by 1080" % [section, preset_name])
            for i in rects.size():
                assert_false(rects[i].intersects(Rect2i(pos, size)), "%s and %s overlap in %s" % [names[i], section, preset_name])
            rects.append(Rect2i(pos, size))
            names.append(String(section))


## The built-in dockers *cfg* has no section for. A docker a layout leaves out
## is not closed by loading it: it stays where the last layout put it, open if
## that one opened it, which is how Brush Presets stood over Useful's Minimap.
static func _missing_dockers(cfg: ConfigFile) -> Array[String]:
    var out: Array[String] = []
    for docker_id: StringName in SaDockerIds.ALL:
        if not cfg.has_section(String(docker_id)):
            out.append(String(docker_id))
    return out


## Whether *cfg*'s top bar order opens with the menus in the order the bar
## builds them. A menu the order lacks is put after every other element, which
## put Tools after Help in Useful and Full.
static func _menus_in_bar_order(cfg: ConfigFile) -> bool:
    var order: Array = cfg.get_value(SaDockerLayoutPresets.ORDER_SECTION, "TopMenuBar", [])
    return order.slice(0, TopMenuBar.MENU_NAMES.size()) == TopMenuBar.MENU_NAMES


## Each shipped layout names all thirteen built-in dockers.
func test_every_shipped_layout_names_every_built_in_docker() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(_store.presets().read_path(preset_name)), OK, "'%s' reads" % preset_name)
        assert_eq(_missing_dockers(cfg), [] as Array[String], "%s places every built-in docker" % preset_name)


## And writes the menus where the bar has them, Tools between Select and Filter.
func test_every_shipped_layout_keeps_the_menu_bars_order() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        assert_true(_menus_in_bar_order(cfg), "%s opens its top bar with the menus in the bar's order" % preset_name)


## The two checks above fail a layout that breaks them, so a pass is a claim
## about the files rather than about the checks.
func test_a_layout_missing_a_docker_or_the_menu_order_fails() -> void:
    var cfg := ConfigFile.new()
    cfg.load(_store.presets().read_path("useful"))
    cfg.erase_section(String(SaDockerIds.BRUSH_PRESETS))
    assert_eq(
        _missing_dockers(cfg),
        [String(SaDockerIds.BRUSH_PRESETS)] as Array[String],
        "A layout without Brush Presets is missing it"
    )
    var order: Array = cfg.get_value(SaDockerLayoutPresets.ORDER_SECTION, "TopMenuBar")
    order.erase("Tools")
    order.insert(order.find("Help") + 1, "Tools")
    cfg.set_value(SaDockerLayoutPresets.ORDER_SECTION, "TopMenuBar", order)
    assert_false(_menus_in_bar_order(cfg), "and one with Tools after Help breaks the menu order")


## Every element order a shipped layout writes names every row a fresh profile
## has, the skeleton's own in the skeleton's sequence, and no row the app no
## longer builds. Each of them carries a visibility too, so loading the layout
## puts back what the last one hid.
##
## The rows once found missing were Tools, the patch and liquify tools,
## the Info docker's Build section and the noise engine's two rows, each put
## at the end of its list by a load. The stale ones were the Dockers menu and
## the colour picker's Picker Type, which every load wrote back into the
## profile its migrations had taken them out of.
func test_every_shipped_order_names_the_rows_a_fresh_profile_has_and_no_other() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        for category: String in SaSettings.DEFAULT_ORDERS:
            var fresh := _fresh_rows(category)
            var order: Array = cfg.get_value(SaDockerLayoutPresets.ORDER_SECTION, category, [])
            var where := "%s's %s" % [preset_name, category]
            for element: Variant in order:
                assert_true(fresh.has(String(element)), "%s names '%s', which no fresh profile has" % [where, element])
            for element: String in fresh:
                assert_true(order.has(element), "%s names '%s'" % [where, element])
                var key := "%s/%s" % [category, element]
                assert_true(
                    cfg.has_section_key(SaDockerLayoutPresets.VISIBILITY_SECTION, key), "and says whether '%s' shows" % key
                )
            var skeletons: Array = order.filter(
                func(element: Variant) -> bool: return SaSettings.DEFAULT_ORDERS[category].has(element)
            )
            assert_eq(skeletons, SaSettings.DEFAULT_ORDERS[category], "%s keeps the skeleton's rows in their order" % where)
        for key: String in cfg.get_section_keys(SaDockerLayoutPresets.VISIBILITY_SECTION):
            var parts := key.split("/", false, 1)
            if SaSettings.DEFAULT_ORDERS.has(parts[0]):
                assert_true(
                    _fresh_rows(parts[0]).has(parts[1]),
                    "%s says whether '%s' shows, which no fresh profile has" % [preset_name, key]
                )


## No shipped layout sets the UI scale, so loading one keeps the painter's.
## Minimalistic drew at nine tenths of whatever the painter had chosen, and the
## other three put a painter at 1.25 back to 1.
func test_a_shipped_layout_keeps_the_painters_scale() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        cfg.load(_store.presets().read_path(preset_name))
        assert_false(cfg.has_section_key(SaDockerLayoutPresets.UI_SECTION, "ui_scale"), "%s sets no UI scale" % preset_name)
    SaSettings.ui_scale = 1.25
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        assert_true(_store.load_preset(preset_name), "'%s' loads" % preset_name)
        assert_almost_eq(SaSettings.ui_scale, 1.25, 1e-6, "and the painter's scale stays after %s" % preset_name)


## What a load leaves in the profile: the menus in the bar's order and no
## Picker Type row, which is what the Preferences page then lists.
func test_loading_a_shipped_layout_leaves_the_menus_in_the_bars_order() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        assert_true(_store.load_preset(preset_name), "'%s' loads" % preset_name)
        var order := SaSettings.get_layout_order("TopMenuBar")
        assert_eq(
            order.slice(0, TopMenuBar.MENU_NAMES.size()),
            TopMenuBar.MENU_NAMES,
            "%s leaves the menus where the bar has them" % preset_name
        )
        assert_false(SaSettings.get_layout_order("ColorPicker").has("Picker Type"), "and no Picker Type row behind it")
