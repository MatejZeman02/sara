## One thing has one name on screen.
##
## The words that disagreed with each other or with the house rules, read back
## where the app puts them: the command names the Keyboard Shortcuts page lists,
## the Preferences sidebar's docker pages, the undo setting on its two pages,
## the Workspace page's save button, the colour models, the -ize words and the
## Display page's sentence that named a plan. The blurs' window titles and the
## Levels labels are the base module's, and its own suite reads them.
##
## The case rule is the one the page follows: a command's name is a phrase in
## sentence case, "Move the layer up", and its menu words may be title case,
## "Move Up". A proper name inside a phrase keeps its capitals, a docker's
## title and Sara's own name. A filter's command is named by the filter, as its
## menu row is, and is the one family left out.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Capitalised words that are names rather than title case. Blender Live before
## Blender, because the rule takes each name out in turn.
const PROPER_NAMES: Array[String] = [
    "Sara",
    "Blender Live",
    "Blender",
    # A toolbox group named after the tool that heads it, which the Shift
    # chords' rows say whole so a language can decline each.
    "Brush group",
    "Crop group",
    "Eraser group",
    "Eyedropper group",
    "Patch group",
    "Magic Wand group",
    "Fill and Gradient tools",
]


func after_each() -> void:
    ModuleLoader.unload_all()


## Every command the boot registers, in the order `Main._bootstrap_modules`
## does, with the shortcut table's rows and the menus' own. *keep* holds the
## objects whose methods the handlers are, for as long as the caller reads.
func _boot(keep: Array) -> SaCommandRegistry:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(
        registries,
        func(_docker_id: StringName) -> void: pass,
        func() -> Variant: return null,
        func(_docker_id: StringName) -> void: pass
    )
    ModuleLoader.load_and_register_modules(registries.context)
    var table := SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    table.register_into(registries.commands)
    keep.append_array([registries, table])
    return registries.commands


## The docker titles a command name may carry with their capitals, from the
## docker rows' own names.
static func _docker_titles() -> Array[String]:
    var out: Array[String] = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        out.append(String(entry[2]).trim_suffix(" docker"))
    return out


## Whether *name* capitalises a word after its first that is no proper name
## and no acronym, which is what title case looks like beside the phrases.
static func is_title_case(name: String, proper: Array[String]) -> bool:
    var rest := name
    for title: String in proper:
        rest = rest.replace(title, "")
    var words := rest.split(" ", false)
    for i in range(1, words.size()):
        var word := words[i].strip_edges().lstrip("(").rstrip(".,:)")
        if word.length() < 2 or word == word.to_upper():
            continue
        if word[0] == word[0].to_upper() and word[0] != word[0].to_lower():
            return true
    return false


func test_the_rule_tells_title_case_from_a_phrase_with_a_name_in_it() -> void:
    var proper := _docker_titles() + PROPER_NAMES
    for name: String in ["Crop to Selection", "Edit Brush", "Fill with Foreground Colour", "ToolBox Docker"]:
        assert_true(is_title_case(name, proper), "'%s' is title case" % name)
    for name: String in ["Crop to selection", "Summon Tool Options docker and lock it", "About Sara", "Opacity digit 0"]:
        assert_false(is_title_case(name, proper), "'%s' is a phrase" % name)


func test_no_command_is_named_in_title_case() -> void:
    var keep: Array = []
    var registry := _boot(keep)
    var proper := _docker_titles() + PROPER_NAMES
    var titled: Array[String] = []
    var phrases := 0
    for id: StringName in registry.list_ids():
        if String(id).begins_with(SaFilterRegistry.COMMAND_PREFIX):
            continue
        var name := registry.get_descriptor(id).title
        if is_title_case(name, proper):
            titled.append("%s '%s'" % [id, name])
        elif name.contains(" "):
            phrases += 1
    assert_true(phrases > 50, "the boot registered the app's commands, %d of them phrases" % phrases)
    assert_eq(titled, [] as Array[String], "no command's name is title case where the rest are phrases")


func test_the_renamed_commands_keep_their_menu_words() -> void:
    var keep: Array = []
    var registry := _boot(keep)
    var expected := {
        &"edit_brush": ["Edit brush", "Edit Brush..."],
        &"image_canvas_size": ["Canvas size", "Canvas Size..."],
        &"image_size": ["Image size", "Image Size..."],
        &"image_crop_to_selection": ["Crop to selection", "Crop to Selection"],
        &"layer_lock": ["Lock layer", "Lock Layer"],
        &"layer_alpha_lock": ["Lock alpha", "Lock Alpha"],
        &"symmetry_horizontal": ["Mirror horizontally", "Mirror Horizontally"],
        &"symmetry_vertical": ["Mirror vertically", "Mirror Vertically"],
        &"symmetry_radial": ["Radial symmetry", "Radial Symmetry"],
        &"view_mirror_horizontal": ["Flip view horizontally", "Flip View Horizontally"],
        &"view_mirror_vertical": ["Flip view vertically", "Flip View Vertically"],
        &"fill_foreground": ["Fill with foreground colour", "Fill with Foreground Colour"],
        &"modules_reload_shaders": ["Reload shaders", "Reload Shaders"],
        &"brush_toggle_eraser": ["Toggle eraser", "Toggle Eraser"],
        &"docker_tool_options": ["Tool Options docker", "Tool Options docker"],
        &"docker_maximise": ["Maximize the focused docker", "Maximize the focused docker"],
        &"file_save_as": ["Save as", "Save As..."],
    }
    for id: StringName in expected:
        var command := registry.get_descriptor(id)
        assert_not_null(command, "%s is registered" % id)
        if command == null:
            continue
        assert_eq(command.title, expected[id][0], "%s is named as a phrase" % id)
        assert_eq(command.menu_label(), expected[id][1], "and its menu row reads as it did")
    assert_eq(registry.get_descriptor(SaAppCommands.summon_id(&"docker_toolbox")).title, "Summon Toolbox docker", "one Toolbox")


## The bar's Mirror H painted every stroke twice and View's
## Mirror Horizontally on H turned the view over, so two jobs had one name and
## a painter checking a face flipped painted two noses. No name may stand for
## two commands, on the shortcuts page or in a menu.
##
## A menu row is named inside its menu, so the Image menu's Flip Horizontally
## and the Layer menu's are two rows and not one name, which
## the category the row sits under tells apart. The shortcuts page shows the
## title, which is unique across all of them.
func test_no_name_stands_for_two_commands() -> void:
    var keep: Array = []
    var registry := _boot(keep)
    var titles := {}
    var rows := {}
    for id: StringName in registry.list_ids():
        var command := registry.get_descriptor(id)
        titles[command.title] = titles.get(command.title, []) + [String(id)]
        var row := "%s > %s" % [command.category, command.menu_label()]
        rows[row] = rows.get(row, []) + [String(id)]
    var shared: Array[String] = []
    for table: Dictionary in [titles, rows]:
        for name: String in table:
            if (table[name] as Array).size() > 1:
                shared.append("'%s' names %s" % [name, ", ".join(table[name])])
    assert_eq(shared, [] as Array[String], "every name on the shortcuts page and in a menu is one command's")


## And the two jobs keep their two words wherever a painter meets them: the
## commands, the bar's pair, its Preferences rows and the Minimap's buttons.
## The symmetry pair is Mirror, Mirror Horizontally as a command and Mirror H
## where the room is short, the one name the control has wherever it is
## shown, and Flip turns the view and never says Mirror. A filter's
## command is named by the filter and left out, as the case rule leaves it out:
## The Mirror filter reflects a layer's paint about a line, a third job
## with its own menu row.
func test_mirror_paints_and_flip_turns_the_view() -> void:
    var keep: Array = []
    var registry := _boot(keep)
    var mirrors := [&"symmetry_horizontal", &"symmetry_vertical"]
    for id: StringName in mirrors:
        var command := registry.get_descriptor(id)
        assert_true(command.title.begins_with("Mirror ") and command.menu_label().begins_with("Mirror "), "%s says Mirror" % id)
        assert_false(command.title.containsn("symmetry"), "and no second name beside it")
    var radial := registry.get_descriptor(&"symmetry_radial")
    assert_eq(radial.menu_label(), "Radial Symmetry", "Radial keeps its word")
    for id: StringName in [&"view_mirror_horizontal", &"view_mirror_vertical"]:
        var command := registry.get_descriptor(id)
        assert_true(command.title.begins_with("Flip view") and command.menu_label().begins_with("Flip View"), "%s says flip" % id)
        assert_true(command.sentence.begins_with("Flip the view"), "and its sentence too")
        assert_false(command.sentence.containsn("mirror"), "and never says Mirror")
    for id: StringName in registry.list_ids():
        if String(id).begins_with(SaFilterRegistry.COMMAND_PREFIX) or mirrors.has(id):
            continue
        var command := registry.get_descriptor(id)
        assert_false(command.title.containsn("mirror"), "%s '%s' is named by no Mirror" % [id, command.title])

    var bar := ToolOptionsBar.new()
    bar._ready()
    for pair: Array in [[bar.mirror_h_btn, "left to right"], [bar.mirror_v_btn, "top to bottom"]]:
        var button: Button = pair[0]
        assert_not_null(button.icon, "%s shows its icon" % button.name)
        assert_eq(button.text, "", "and no word beside it")
        assert_eq(
            button.tooltip_text, "Paint every stroke again, mirrored %s." % pair[1], "and a tooltip that does not repeat the name"
        )
    bar.free()
    assert_eq(SaSettings.element_title("TopMenuBar", "Mirror H"), "Mirror H", "the pair's Preferences rows")
    assert_eq(SaSettings.element_title("TopMenuBar", "Mirror V"), "Mirror V", "say Mirror as the bar does")

    var minimap := MinimapDocker.new()
    for button_name: String in ["FlipHorizontal", "FlipVertical"]:
        var button := minimap.find_child(button_name, true, false) as Button
        assert_true(button.tooltip_text.begins_with("Flip the view"), "the Minimap's %s says it flips the view" % button_name)
    minimap.free()


func test_each_docker_page_is_named_by_the_dockers_title() -> void:
    var titles := {}
    for entry: Dictionary in SaSettings.reorderable_categories():
        titles[String(entry["id"])] = String(entry["title"])
    assert_eq(titles.get("ColorPicker", ""), "Colour Picker", "the picker's page")
    assert_eq(titles.get("LayersDocker", ""), "Layers", "the layers' page")
    assert_eq(titles.get("ToolBoxDocker", ""), "Toolbox", "the toolbox's page, in the docker's spelling")
    assert_eq(titles.get("InfoDocker", ""), "Info", "the info page")
    for id: String in titles:
        assert_false(String(titles[id]).ends_with(" Docker"), "'%s' carries no Docker the others lack" % titles[id])


func test_the_preferences_rows_say_one_thing_once() -> void:
    var window := SaSettingsWindow.new()
    var interface := SaSettingsWindow.INTERFACE_PAGE
    for page: String in [interface, "Performance"]:
        window.show_page(page)
        var names: Array[String] = []
        for entry: Dictionary in SaSettingsRowReport.report(window)["rows"] as Array:
            names.append(String(entry["title"]))
        assert_eq(names.has("Undo steps"), page == interface, "%s: the undo setting has its one row, on Interface" % page)
        assert_false(names.has("Undo depth") or names.has("Whole-canvas steps"), "and by no second name")

    window.show_page("Canvas and colour")
    var shape_hint := ""
    for entry: Dictionary in SaSettingsRowReport.report(window)["rows"] as Array:
        if String(entry["section"]) == "Shape check" and String(entry["title"]) == "Method":
            shape_hint = String(entry["hint"])
    for method: String in ["Blocks", "Masses", "None", "Grey masses", "Notan"]:
        assert_true(shape_hint.contains(method + " "), "the Shape check's Method row says what %s does" % method)
    assert_false(shape_hint.contains("plan "), "and names no plan")

    window.show_page(SaDockersPage.TITLE)
    var save := window.content_container.find_child("WorkspacePresetSave", true, false) as Button
    assert_eq(save.text if save != null else "", "Save As", "the layout's save button reads like every other")
    window.free()


func test_the_colour_models_are_spelled_one_way() -> void:
    for label: String in SaPickerShape.KIND_LABELS:
        assert_false(label.contains("OK-"), "'%s' spells its model without a hyphen" % label)
    assert_true(SaPickerShape.KIND_LABELS.has("OKHSL, disc"), "OKHSL as OKHSV is")
    assert_eq(SaSettings.element_title("ColorPicker", "OK-HSV Sliders"), "OKHSV Sliders", "the sliders' row says OKHSV")
    assert_eq(SaSettings.element_title("ColorPicker", "HSV Wheel"), "Picker Shape", "and the shape's names no model")


func test_the_ize_words() -> void:
    var dockers := SaDockersPage.new()
    var maximise := dockers.page.row(&"maximise_button")
    assert_eq(
        maximise.label if maximise != null else "", "Maximize button", "Maximize, as the window buttons' own sentence spells it"
    )
    dockers.free()

    var docker := ReferenceDocker.new()
    var normalize := docker.find_child("NormaliseButton", true, false) as Button
    assert_true(normalize != null and normalize.tooltip_text.begins_with("Normalize\n"), "and Normalize on the board's icon")
    var reference_titles: Array[String] = []
    for option: Dictionary in SaSettings.docker_options(SaDockerIds.REFERENCE):
        reference_titles.append(String(option.get("title", "")))
    assert_true(reference_titles.has("Normalize to"), "on its Preferences row as well")
    docker.free()

    # The shown words that once said -ise, read where the
    # app puts them. Identifiers such as `NormaliseButton` stay as they are.
    var top_bar := SaDockersPage.new()
    var sentence := ""
    for row: Node in top_bar.find_children("*", "HBoxContainer", true, false):
        if String(row.get_meta(SaSettingsRows.TITLE_META, "")) == "Window button position":
            for label: Node in row.get_child(0).find_children("*", "Label", true, false):
                if (label as Label).text.begins_with("Where"):
                    sentence = (label as Label).text
    assert_true(sentence.begins_with("Where minimize, maximize and close sit"), "the window buttons' sentence: %s" % sentence)
    top_bar.free()

    var keep: Array = []
    _boot(keep)
    var registries: SaRegistries = keep[0]
    var sections: Array[String] = []
    for section: SaFilterRegistry.Section in registries.filters.list_sections():
        sections.append(section.label)
    assert_true(sections.has("Stylize"), "the Filter menu's section is Stylize: %s" % ", ".join(sections))
    var noise := registries.tools.get_descriptor(&"noise_brush")
    var rolls: Array[String] = []
    for spec: SaOptionSpec in noise.options if noise != null else []:
        if String(spec.key).ends_with("_random"):
            rolls.append(spec.tooltip)
    assert_false(rolls.is_empty(), "the noise brush declares its randomise rows")
    # A tooltip is an imperative sentence, so each row says Randomize and not
    # Randomizes.
    for tooltip: String in rolls:
        assert_true(tooltip.begins_with("Randomize "), "and each says Randomize: %s" % tooltip)
