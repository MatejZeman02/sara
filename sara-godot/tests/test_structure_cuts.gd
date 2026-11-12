## The second rule of structure, in CONTRIBUTING.md: "A cut makes a class that
## owns state of its own and takes no reference back to the class it was cut
## from. A file that reaches into one other object ten times or more is a piece
## of that object's class, and it goes back or takes its state with it."
##
## Two shapes of the same mistake, over the six layer folders (`utils`,
## `core`, `render`, `tools`, `ui`, `harness`).
##
## **`BACK_REFERENCES`**, from `"file:Class"` to the reason it stands, is
## every site of `Class.new(self` outside comments and strings: a piece
## handed the object that built it. `HOSTS` is the same shape with a sentence
## in place of a reason, for the sites that are a widget handed the window or
## the container it serves rather than a cut in need of draining. The list
## `BACK_REFERENCES` is empty, so a new `Class.new(self` fails the run.
##
## **`PIECES`**, from `"file -> receiver"` to the reason, is a member of the
## file's own class, typed as a different project class, whose members are
## read ten times or more anywhere in the file: `receiver.member`, counted
## regardless of which member. A member typed as the file's own class is
## excluded, because a class comparing itself to a peer of its own kind is not
## a cut reaching backward. A receiver is a member variable typed as another
## project class, since counting every identifier before a dot finds the
## pattern in a `Rect2` or a `Color` local as readily as in a held-back
## reference.
##
## A class asking the parts it is made of, labelled with its id in `PIECES`, is
## the composition the rule leaves standing and not a cut reaching back.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const LAYER_DIRS: Array[String] = ["utils", "core", "render", "tools", "ui", "harness"]

## Never descend into these. `.godot` is the engine's import cache, `.conda` the
## vendored gdtoolkit env, and `build/` is output rather than source. A `tests`
## folder beside a package holds its suites, and a suite reaching into what it
## tests is no cut of the package.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "tests"]

## Where the planted pair is written and removed again.
static var scratch_dir: String = SaDataRoot.path("test_structure_cuts_scratch")

## `"file:Class"` to the reason it stands, one entry per `Class.new(self`
## site under the six layer folders, minus the entries of `HOSTS`.
const BACK_REFERENCES: Dictionary = {}

## The same shape as `BACK_REFERENCES`, with a sentence in place of a reason: a
## widget handed the window or the container it serves, not a cut in need of
## draining.
const HOSTS: Dictionary = {
    "ui/dialogs/sa_dialog_window.gd:DockerResizerScript": "The dialog's own resize handle, built for the window it decorates.",
    "ui/dockers/docker_window.gd:DockerResizerScript": "The docker's own resize handle, built for the window it decorates.",
    "ui/dockers/presets/brush_presets_docker.gd:SaRandomPresetButton": "The panel's own Random button.",
    "ui/dockers/toolbox/toolbox_docker.gd:SaToolBoxSize":
    "The toolbox's own button size and the menu on its drag bar, a child freed with it.",
    "ui/dockers/layers/list/layer_list.gd:SaLayerListEdgeScroll": "The list's own edge scroll, freed with it.",
    "ui/dockers/layers/list/layer_list.gd:SaLayerRowSleep": "The list's own sleep of the rows out of view, freed with it.",
    "ui/settings/sa_settings_window.gd:SaSettingsTypeAhead":
    "The window's own type-ahead into its search, a child freed with it.",
    "ui/files/sa_document_files.gd:SaQuitPrompt":
    (
        "The quit's question is handed the node `SaMessage.confirm` builds its window"
        + " under, the way every dialog here is handed one, and names it for nothing"
        + " else."
    ),
    "ui/main/main.gd:SaDocumentTabs":
    (
        "The tabs are handed the node the documents' views stand in, main, which"
        + " they add each further view to and read the tools' registries from, and"
        + " name it for nothing else."
    ),
    "ui/page/sa_page.gd:SaPageWatch":
    (
        "The page's own change listener, a Node built for the page it serves so freeing"
        + " the page's container frees the listener with it, which is what keeps the"
        + " page from leaking."
    ),
    "ui/tool_options/tool_options_bar.gd:ToolOptionControls":
    (
        "Not a cut handed its class: the controls are handed the container they are"
        + " built into, the docker its row box and the brush editor its page box, and the"
        + " bar is its own container. It is used for tr, add_child and get_tree."
    ),
    "ui/tool_options/views/sa_tool_option_views.gd:ToolOptionControls": "The view is the box its control is built in.",
}

## `"file -> receiver"` to the reason it stands.
const PIECES: Dictionary = {
    # The toolbox's size node holds the docker's edges, the bar's narrow form,
    # the grip over the corner and the cut to whole rows, which are the
    # window's geometry at the button size the node holds.
    "ui/dockers/toolbox/toolbox_size.gd -> _window": "package",
    # The reference selection and its box live in a folder of their own, and
    # the view that turns a press into a selection asks it at every gesture.
    "ui/dockers/reference/reference_picture_view.gd -> selection": "package",
    # SaRegistries wires every registry into the context it builds, and the
    # codecs make that ten writes.
    "core/registry/sa_registries.gd -> context": "package",
    # The paint context reads its document ten times.
    "core/api/paint/sa_paint_context.gd -> document": "package",
    "core/api/color/sa_color_space.gd -> transfer": "package",
    "core/composite/filter-chain/sa_filter_halo.gd -> layer": "package",
    "core/sad-file/sa_autosave.gd -> document": "package",
    "core/image/sa_color_conversion.gd -> _document": "package",
    "core/image/precision/sa_precision.gd -> _document": "package",
    "core/image/sa_crop.gd -> _document": "package",
    "core/image/sa_resample.gd -> _document": "package",
    # A flip of one layer swaps its chunks, its masks and the caches the way
    # the resample's own apply does, so it reads the document as that does.
    "core/image/sa_orient.gd -> _document": "package",
    # A conversion between projection kinds puts a new size, its chunks, masks
    # and projection on the document the way the resample's own apply does
    "core/api/projection/sa_projection_conversion.gd -> _document": "package",
    "core/layers/sa_layer_ops.gd -> _document": "package",
    # The conversion between an attached filter and an adjustment layer is an
    # operation on the document the way a layer's own are, so it reads the
    # document for the stack, the history and the caches as they do.
    "core/layers/sa_filter_conversion.gd -> _document": "package",
    # The shape of the tree is an operation on the document the way a layer's
    # own are, and it shares the keeper, the take out, the put back and the
    # refresh every structural step goes through, from an ops it builds over
    # the same document rather than one handed back.
    "core/layers/groups/sa_layer_groups.gd -> _document": "package",
    "core/layers/groups/sa_layer_groups.gd -> _ops": "package",
    "core/layers/masks/sa_mask_ops.gd -> _document": "package",
    # Rasterize Impasto swaps a layer's chunks or puts a paint layer in a
    # ground's place, an operation on the document the way a layer's own are,
    # so it reads the document for the canvas, the space, the history and the
    # caches as they do.
    "core/layers/impasto/sa_rasterize_impasto.gd -> _document": "package",
    "core/settings/sa_settings.gd -> _file": "package",
    "core/settings/sa_settings.gd -> _layout": "package",
    "harness/captures/workspace_page_capture.gd -> _page": "package",
    "render/main_canvas.gd -> canvas": "package",
    "render/main_canvas.gd -> tool_machine": "package",
    "render/sa_canvas.gd -> easel": "package",
    "render/sa_canvas_view.gd -> canvas": "package",
    "tools/tool_machine.gd -> surface": "package",
    "tools/tool_machine.gd -> _held": "package",
    # The machine drives the tool it holds: the press, the frame, the reset and
    # what the pointer shows over the canvas, which is the composition the rule
    # leaves standing. The tooltip is the tenth read.
    "tools/tool_machine.gd -> active_tool": "package",
    "ui/brush_editor/brush_editor_window.gd -> page_list": "package",
    "ui/brush_editor/brush_editor_window.gd -> pages": "package",
    "ui/brush_editor/brush_editor_window.gd -> preset_bar": "package",
    "ui/brush_editor/editor_pages.gd -> page_controls": "package",
    "ui/brush_editor/editor_preset_bar.gd -> session": "package",
    "ui/brush_editor/preview/editor_scratchpad.gd -> canvas": "package",
    "ui/brush_editor/preview/editor_scratchpad.gd -> snap": "package",
    "ui/dockers/color/sa_color_picker.gd -> shape": "package",
    # The docker frames the browser it holds, the composition the rule leaves
    # standing. Its Open, which invokes and goes back, is the tenth read.
    "ui/dockers/filters/filters_docker.gd -> browser": "package",
    "ui/dockers/graph/graph_docker.gd -> plot": "package",
    "ui/dockers/graph/graph_docker.gd -> reference_plot": "package",
    "ui/dockers/layers/layer_actions.gd -> menu": "package",
    # The driving of the layer list lives outside the docker. The docker asks the keeper it
    # builds, which is the composition the rule leaves standing, and the keeper
    # asks the list it is handed, which is the one thing it is for.
    "ui/dockers/layers/layers_docker.gd -> list_keeper": "package",
    "ui/dockers/layers/list_keeper/layer_list_keeper.gd -> _list": "package",
    "ui/dockers/palette/palette_slot_ring.gd -> wheel": "package",
    "ui/dockers/minimap/minimap_docker.gd -> _proof_option": "package",
    "ui/dockers/recorder/recorder_docker.gd -> recorder": "package",
    "ui/dockers/reference/reference_docker.gd -> board_view": "package",
    "ui/dockers/reference/reference_picture_view.gd -> board": "package",
    "ui/filters/sa_filter_dialog_window.gd -> dialog": "package",
    "ui/main/main.gd -> dockers": "package",
    "ui/main/main.gd -> _shortcut_router": "package",
    "ui/main/main.gd -> registries": "package",
    "ui/main/main_dockers.gd -> layout_store": "package",
    "ui/main/sa_boot_fit.gd -> _canvas": "package",
    "ui/menus/sa_menu.gd -> popup": "package",
    "ui/menus/view_menu.gd -> view_transforms": "package",
    "ui/notes/sa_note_mode.gd -> menu": "package",
    "ui/presets/brush_preset_tags.gd -> menu": "package",
    # The preset group loads presets out of the store it fronts, the
    # composition the rule leaves standing. The question
    # whether a loaded preset erases, which the blend memory needs, is the tenth read.
    "ui/presets/tool_options_presets.gd -> preset_store": "package",
    "ui/presets/brush_preset_tags.gd -> _store": "package",
    "ui/presets/brush_presets_chooser.gd -> tags": "package",
    # Every tag of the list is a three-way toggle: the chooser
    # writes the list's rows and marks and hands each press to its tag filter,
    # the piece it composes for that rule, ten reads each.
    "ui/presets/brush_presets_chooser.gd -> tag_filter": "package",
    "ui/presets/brush_presets_chooser.gd -> tag_option": "package",
    # The chooser lays its grid out through the cells it composes. Scrolling
    # the preset in hand into view on a load is the tenth read.
    "ui/presets/brush_presets_chooser.gd -> cells": "package",
    # File > New composes the colour space picker, the piece that owns the
    # colour rows and the saved spaces, and hands it its rows, its browser and
    # every question the dialog answers about the space.
    "ui/dialogs/document/new_document/new_document_dialog.gd -> picker": "package",
    "ui/settings/input/tablet_calibration.gd -> _curve": "package",
    "ui/settings/input/tablet_sweep_dialog.gd -> _editor": "package",
    "ui/settings/look/display_page.gd -> _view_option": "package",
    "ui/settings/sa_settings_frame.gd -> _window": "package",
    "ui/tool_options/tool_options_bar.gd -> target_tool_machine": "package",
    "ui/tool_options/tool_options_bar.gd -> preset_box": "package",
    "ui/tool_options/tool_options_bar.gd -> options": "package",
    "ui/tool_options/tool_options_bar.gd -> switches": "package",
    "ui/dockers/tool_options/tool_options_docker.gd -> options": "package",
    "ui/filters/sa_filter_edit_window.gd -> dialog": "package",
    "ui/top_bar/top_bar_rotation.gd -> slider": "package",
    "ui/widgets/blend_mode_button.gd -> registry": "package",
    "ui/widgets/choice/sa_choice_popup.gd -> search": "package",
    # The curve editor's own children and the option it edits, read as they
    # were while the control was the stamp brush's and outside this sweep.
    "ui/widgets/curve_option/sa_curve_option_control.gd -> _graph": "package",
    "ui/widgets/curve_option/sa_curve_option_control.gd -> _sensors": "package",
    "ui/widgets/curve_option/sa_curve_option_control.gd -> _strength": "package",
    "ui/widgets/curve_option/sa_curve_option_control.gd -> option": "package",
    "ui/widgets/sa_scratchpad.gd -> canvas": "package",
}


func test_every_new_self_site_is_listed() -> void:
    var found := _all_new_self_sites()

    var unlisted: Array[String] = []
    for key: String in found:
        if not BACK_REFERENCES.has(key) and not HOSTS.has(key):
            unlisted.append(key)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            (
                "A constructor hands self back to its builder, unlisted: %s. List it in "
                + "BACK_REFERENCES to be drained, or in HOSTS if it is a widget handed the "
                + "window it serves rather than a cut."
            )
            % ", ".join(unlisted)
        )
    )

    var stale: Array[String] = []
    for key: String in BACK_REFERENCES:
        if not found.has(key):
            stale.append(key)
    for key: String in HOSTS:
        if not found.has(key):
            stale.append(key)
    stale.sort()
    assert_true(stale.is_empty(), "No longer a hand-off, remove from BACK_REFERENCES or HOSTS: %s" % ", ".join(stale))


func test_every_piece_is_listed() -> void:
    var class_names := _all_class_names()
    var found := _all_pieces(class_names)

    var unlisted: Array[String] = []
    for key: String in found:
        if not PIECES.has(key):
            unlisted.append(key)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            (
                "A file reaches into one other object ten times or more, unlisted: %s. It is a "
                + "piece of that object's class, so it goes back or takes the state with it, or is "
                + "listed in PIECES for now."
            )
            % ", ".join(unlisted)
        )
    )

    var stale: Array[String] = []
    for key: String in PIECES:
        if not found.has(key):
            stale.append(key)
    stale.sort()
    assert_true(stale.is_empty(), "No longer ten reads into one receiver, remove from PIECES: %s" % ", ".join(stale))


## The check sees a hand-off and a reach planted beside it, and a class
## reading its own kind is not read as one.
func test_the_planted_pair_is_found_and_a_self_read_is_not() -> void:
    var reach := ""
    for letter in "abcdefghij":
        reach += "    _owner.%s\n" % letter
    var reach_twin := ""
    for letter in "abcdefghij":
        reach_twin += "    _twin.%s\n" % letter

    var planted := {
        "sa_scratch_owner.gd": "class_name ScratchOwner\nextends RefCounted\n\nvar sibling := ScratchHost.new(self)\n",
        "sa_scratch_host.gd":
        (
            "class_name ScratchHost\nextends RefCounted\n\n"
            + "var _owner: ScratchOwner\nvar _twin: ScratchHost\n\n\n"
            + "func _init(owner: ScratchOwner) -> void:\n    _owner = owner\n\n\n"
            + "func reach() -> void:\n%s\n\nfunc reach_twin() -> void:\n%s" % [reach, reach_twin]
        ),
    }
    _write_scratch(planted)

    var self_sites := _new_self_sites_under(scratch_dir, "")
    var class_names := _class_names_under(scratch_dir)
    var pieces := _pieces_under(scratch_dir, "", class_names)
    ScratchFolder.clear(scratch_dir)

    assert_eq(
        self_sites.size(), 1, "The planted hand-off should be the one site found, and the scan saw %s" % [self_sites.keys()]
    )
    assert_true(
        self_sites.has("sa_scratch_owner.gd:ScratchHost"), "The planted hand-off was not seen, so the check measures nothing"
    )

    assert_eq(pieces.size(), 1, "The planted reach should be the one piece found, and the scan saw %s" % [pieces.keys()])
    assert_true(pieces.has("sa_scratch_host.gd -> _owner"), "The planted reach was not seen, so the check measures nothing")
    assert_false(
        pieces.has("sa_scratch_host.gd -> _twin"),
        "A class reading its own kind is not a piece of another class, and the check found one anyway"
    )


## Every `Class.new(self` site under the six layer folders.
func _all_new_self_sites() -> Dictionary:
    var found: Dictionary = {}
    for layer in LAYER_DIRS:
        var here := _new_self_sites_under("res://%s" % layer, "%s/" % layer)
        for key: String in here:
            found[key] = true
    return found


func _new_self_sites_under(root_path: String, prefix: String) -> Dictionary:
    var files: Dictionary = {}
    _gd_files_under(root_path, prefix, files)
    var found: Dictionary = {}
    var re := RegEx.create_from_string("\\b([A-Z]\\w*)\\.new\\(\\s*self\\b")
    for rel: String in files:
        for m: RegExMatch in re.search_all(_cleaned_of(files[rel])):
            found["%s:%s" % [rel, m.get_string(1)]] = true
    return found


## Every project `class_name` under the six layer folders.
func _all_class_names() -> Dictionary:
    var names: Dictionary = {}
    for layer in LAYER_DIRS:
        for name: String in _class_names_under("res://%s" % layer):
            names[name] = true
    return names


func _class_names_under(root_path: String) -> Dictionary:
    var files: Dictionary = {}
    _gd_files_under(root_path, "", files)
    var names: Dictionary = {}
    var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
    for rel: String in files:
        var m := re.search(_text_of(files[rel]))
        if m:
            names[m.get_string(1)] = true
    return names


## Every `"file -> receiver"` where a member typed as a different project
## class is read ten times or more, under the six layer folders.
func _all_pieces(class_names: Dictionary) -> Dictionary:
    var found: Dictionary = {}
    for layer in LAYER_DIRS:
        var here := _pieces_under("res://%s" % layer, "%s/" % layer, class_names)
        for key: String in here:
            found[key] = true
    return found


func _pieces_under(root_path: String, prefix: String, class_names: Dictionary) -> Dictionary:
    var files: Dictionary = {}
    _gd_files_under(root_path, prefix, files)
    var own_class_re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
    var typed_member_re := RegEx.create_from_string("(?m)^var\\s+(\\w+)\\s*:\\s*(\\w+)")
    var ctor_member_re := RegEx.create_from_string("(?m)^var\\s+(\\w+)\\s*:?=\\s*(\\w+)\\.new\\(")
    var found: Dictionary = {}
    for rel: String in files:
        var cleaned := _cleaned_of(files[rel])
        var own_match := own_class_re.search(_text_of(files[rel]))
        var own_class := own_match.get_string(1) if own_match else ""

        var receivers: Dictionary = {}
        for m: RegExMatch in typed_member_re.search_all(cleaned):
            var typ := m.get_string(2)
            if class_names.has(typ) and typ != own_class:
                receivers[m.get_string(1)] = true
        for m: RegExMatch in ctor_member_re.search_all(cleaned):
            var typ := m.get_string(2)
            if class_names.has(typ) and typ != own_class:
                receivers[m.get_string(1)] = true

        for receiver: String in receivers:
            var reach_re := RegEx.create_from_string("(?<![.\\w])%s\\.[a-zA-Z_]\\w*" % receiver)
            if reach_re.search_all(cleaned).size() >= 10:
                found["%s -> %s" % [rel, receiver]] = true
    return found


## One read and one strip a file, however many scans ask for it. The three
## checks here walk the same six folders, and stripping is the expensive half,
## so the suite read and stripped every file about four times over. Nothing
## under `res://` changes during a run, and the planted pair is written before
## the scans that look for it and removed after them, so a path's text is the
## same answer every time it is asked for.
var _text_by_path: Dictionary = {}
var _cleaned_by_path: Dictionary = {}


## The file's text, or the empty string when it cannot be opened, which reads
## as a file with nothing in it and so matches nothing.
func _text_of(path: String) -> String:
    if _text_by_path.has(path):
        return _text_by_path[path]
    var file := FileAccess.open(path, FileAccess.READ)
    var text := file.get_as_text() if file != null else ""
    _text_by_path[path] = text
    return text


func _cleaned_of(path: String) -> String:
    if _cleaned_by_path.has(path):
        return _cleaned_by_path[path]
    var cleaned := _strip_comments_and_strings(_text_of(path))
    _cleaned_by_path[path] = cleaned
    return cleaned


## Strips comments and string contents to spaces, same length, so a match
## inside either never fires and a reported line number still lines up.
static func _strip_comments_and_strings(text: String) -> String:
    var out := ""
    var i := 0
    var n := text.length()
    var in_string := ""
    while i < n:
        var c := text[i]
        if not in_string.is_empty():
            out += " "
            if c == "\\" and i + 1 < n:
                i += 2
                out += " "
                continue
            if c == in_string:
                in_string = ""
            i += 1
            continue
        if c == '"' or c == "'":
            in_string = c
            out += " "
            i += 1
            continue
        if c == "#":
            while i < n and text[i] != "\n":
                out += " "
                i += 1
            continue
        out += c
        i += 1
    return out


## Every `.gd` file under *root_path*, as `{display path: absolute path}`.
func _gd_files_under(root_path: String, prefix: String, out: Dictionary) -> void:
    var dir := DirAccess.open(root_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _gd_files_under(root_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out[prefix + entry] = root_path.path_join(entry)
        entry = dir.get_next()
    dir.list_dir_end()


## Writes *planted*, `{file name: source}`, into the scratch directory.
##
## Under `user://` rather than `res://`, so the editor never imports it and a run
## that dies between the write and the removal cannot leave a script in the tree.
func _write_scratch(planted: Dictionary) -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    for name: String in planted:
        var file := FileAccess.open(scratch_dir.path_join(name), FileAccess.WRITE)
        assert_not_null(file, "The scratch pair could not be written to %s" % scratch_dir)
        if file != null:
            file.store_string(String(planted[name]))
            file.close()
