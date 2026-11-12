## Which actions the Keyboard Shortcuts page lists, in which section, under what
## name, and what their keys read as.
##
## Everything here is a table or a lookup over one. The page builds the controls
## and holds what is being edited, and none of that is a question anything else
## asks. The Help suite reads these, which is why they are their own file rather
## than private. `core/registry/shortcuts/sa_shortcut_store.gd` keeps its own
## `ui_` names, because `core` may not name a class under `ui`, and
## `ui/settings/input/tests/test_shortcut_sections.gd` holds the two lists to
## each other.
class_name SaShortcutRows
extends RefCounted

## The order the rows are shown in inside their section, so a section reads as
## importance rather than as whatever order the InputMap happened to hand the
## actions out in. Identifiers only: the words a row reads as are the command's
## title, which the menus read too, so the page and the menus cannot drift.
##
## The filters named here are the adjustments with a command of their own, in
## the Filter menu's family order, tone and then colour. A module's filters are
## absent on purpose, because a table in the skeleton cannot name them.
const ORDER: Array[StringName] = [
    &"file_new",
    &"file_open",
    &"file_save",
    &"file_save_as",
    &"ui_quit",
    &"edit_preferences",
    &"edit_undo",
    &"edit_redo",
    &"edit_cut",
    &"edit_copy",
    &"edit_paste",
    &"brush_size_increase",
    &"brush_size_decrease",
    &"brush_toggle_eraser",
    &"select_all",
    &"select_none",
    &"select_invert",
    &"select_quick_mask",
    &"layer_new_paint",
    &"layer_duplicate",
    &"layer_via_copy",
    &"layer_via_cut",
    &"layer_via_seamless_cut",
    &"layer_group",
    &"layer_merge_down",
    &"layer_merge_visible",
    &"layer_clip_to_below",
    &"layer_move_up",
    &"layer_move_down",
    &"layer_delete",
    &"layer_mask_add",
    &"layer_mask_add_from_selection",
    &"layer_mask_delete",
    &"layer_mask_apply",
    &"layer_mask_invert",
    &"layer_mask_disable",
    &"layer_mask_to_selection",
    &"filter_brightness_contrast",
    &"filter_levels",
    &"filter_curves",
    &"filter_hue_saturation_lightness",
    &"filter_color_balance",
    &"filter_palette",
    &"color_swap",
    &"color_picker_shape_next",
    &"color_reset",
    &"docker_toolbox",
    &"docker_layers",
    &"docker_color_selector",
    &"info_docker",
    &"docker_recorder",
    &"docker_reference",
    &"docker_minimap",
    &"docker_tool_options",
    &"docker_graph",
    &"docker_history",
    &"docker_brush_presets",
    &"toggle_dockers",
    &"view_zoom_in",
    &"view_zoom_out",
    &"view_zoom_100",
    &"view_actual_pixels",
    &"view_soft_proof",
    &"view_fit",
    &"view_fit_window",
    &"view_center",
    &"view_isolate_active_layer",
    &"view_rotate_left",
    &"view_rotate_right",
    &"view_rotate_reset",
    &"ui_scale_up",
    &"ui_scale_down",
    &"ui_scale_reset",
    &"ui_take_note",
]

## The words of the actions no command holds: keys the router answers itself,
## declared in `project.godot` rather than registered, so there is no title to
## read. Everything else on the page is a command and says what its title says.
const WORDS := {
    "brush_size_increase": "Larger brush",
    "brush_size_decrease": "Smaller brush",
    "brush_toggle_eraser": "Toggle the eraser",
    "color_swap": "Swap the two colours",
    "color_reset": "Reset the two colours",
    "docker_toolbox": "Toolbox docker",
    "docker_layers": "Layers docker",
    "docker_color_selector": "Colour picker docker",
    "info_docker": "Info docker",
    "toggle_dockers": "Hide or show every docker",
    # The held tools of the base module, each a whole phrase so a catalogue
    # holds it as one, which a tool's name glued to " while held" never is.
    "tool_eyedropper_quick": "Eyedropper while held",
    "tool_pan_quick": "Pan while held",
    "tool_zoom_quick": "Zoom while held",
}

## Group titles by action prefix, in the order they are shown.
##
## **Every prefix an action carries has a section**, because a prefix nothing
## lists is not an empty section, it is an action nobody can find or rebind, and
## `actions_for` never asks whether every prefix has a home. Image, Fill and
## Window hold `image_crop_to_selection`, `fill_foreground`, `fill_background`
## and `window_fullscreen` among them.
const GROUPS := [
    ["file_", "File"],
    ["edit_", "Edit"],
    ["image_", "Image"],
    ["select_", "Select"],
    ["layer_", "Layer"],
    ["fill_", "Fill"],
    ["filter_", "Filter"],
    ["tool_", "Tools"],
    ["brush_", "Brush"],
    ["color_", "Colour"],
    ["view_", "View"],
    ["window_", "Window"],
    # Reload Shaders, the first skeleton action on the Modules menu, which is
    # the section's title for the same reason Image is Image's.
    ["modules_", "Modules"],
    # The rows of the Help menu's settings among them, and two Modules carries.
    ["help_", "Help"],
    ["docker_", "Dockers"],
    ["ui_", "Interface"],
]

## The one chord left that no action carries: Tab, which the router reads as a
## bare keycode because a modified Tab has to stay focus traversal. It is shown
## and not editable, which the row says.
const KEYCODE_CHORDS := [
    ["Interface", "Hide or show every docker", "Tab"],
]

## What has no action to read from: the pointer gestures. Kept beside the keys
## because a painter looking for "how do I pan" looks here.
const GESTURES := [
    ["Wheel", "Zoom about the pointer"],
    ["Middle drag", "Pan"],
    ["Shift + left drag on the canvas", "Size the brush, a screen pixel of radius for each pixel of drag"],
    ["Shift + middle drag", "Turn the view about where the drag starts"],
    ["Ctrl + middle drag", "Zoom about where the drag starts, up or right zooming in"],
    ["Shift + Space + drag", "Turn the view with the pen or the left button"],
    ["Alt + left drag on a docker", "Move the docker"],
    ["Alt + right drag on a docker", "Resize the docker"],
]

## The actions `ShortcutRouter._answer` reads itself before it asks the
## registered commands, in the order it reads them: quit, the File chords, the
## dockers, the history, the brush size and the two colours. What
## [method first_to_answer] walks. The docker toggles come after
## `toggle_dockers`, by name, because the router reads them off the docker
## table and this is static.
const READ_BEFORE_COMMANDS: Array[String] = [
    "ui_quit",
    "file_new",
    "file_open",
    "file_save",
    "file_save_as",
    "toggle_dockers",
    "edit_undo",
    "edit_redo",
    "brush_size_increase",
    "brush_size_decrease",
    "color_swap",
    "color_reset",
]


## Which of *actions*, every one holding one chord, a press of that chord goes
## to: the order `ShortcutRouter._answer` asks in, then the registered commands
## in the order *commands* dispatches them, then the tools in the order *tools*
## lists them. Empty when the router answers none of them.
##
## What the line under a clashing row says. Binding the Brush to E colours the
## row, and E goes on toggling the eraser, because the command answers before
## any tool's key is read, so the row says which of them a press goes to. The
## order is the router's and is read here rather than asked of it, because the
## router answers a press and has nothing that answers without acting.
## `ui/settings/input/tests/test_a_clash_says_which_command_a_press_goes_to.gd`
## presses the chord through a real router and holds the two to each other.
##
## A handler can still decline, undo with nothing to undo, and the press then
## goes on down the chain. This is the order and not the outcome of one press.
static func first_to_answer(actions: Array, commands: SaCommandRegistry = null, tools: SaToolRegistry = null) -> StringName:
    var wanted: Array[StringName] = []
    for action: Variant in actions:
        wanted.append(StringName(action))
    var order: Array[StringName] = []
    for action: String in READ_BEFORE_COMMANDS:
        order.append(StringName(action))
        if action == "toggle_dockers":
            for held: StringName in wanted:
                if _toggles_a_docker(held):
                    order.append(held)
    if commands != null:
        for descriptor: SaCommandDescriptor in commands._dispatch_order:
            order.append(descriptor.action)
    if tools != null:
        for descriptor: SaToolDescriptor in tools.list_descriptors():
            order.append(descriptor.activate_action)
    for action: StringName in order:
        if wanted.has(action):
            return action
    return &""


## Whether *action* is a docker's own toggle, which the router answers from the
## docker table before any command. By the name the Dockers section files it
## under, less the summons and the maximise, which are commands.
static func _toggles_a_docker(action: StringName) -> bool:
    var action_name := String(action)
    if not (action_name.begins_with("docker_") or action_name.ends_with("_docker")):
        return false
    return not action_name.begins_with(SaShortcutStore.SUMMON_PREFIX) and action_name != "docker_maximise"


## "Undo", "Eraser and Toggle the eraser", or "A, B and C": the words of *actions*
## as one phrase, for the question a taken chord asks and the line under a row.
static func listed(
    actions: Array, tools: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null
) -> String:
    var names: Array[String] = []
    for action: Variant in actions:
        names.append(label_for(String(action), tools, filters, commands))
    if names.size() < 2:
        return "" if names.is_empty() else names[0]
    return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]


## The actions in one prefix, in InputMap order, chorded or not.
##
## **The chordless ones are kept**, because a row is how a key is given, and
## dropping the unbound ones would make them the only actions in Sara that can
## never be bound: `tool_zoom` ships with no chord, and so does many a filter a
## module registers. The Help list drops them, in [method rows_for], because it
## prints keys rather than offering to set them.
static func actions_for(prefix: String) -> Array[StringName]:
    var out: Array[StringName] = []
    for action: StringName in InputMap.get_actions():
        var action_name := String(action)
        # "info_docker" is a docker toggle named the other way round.
        var in_group := action_name.begins_with(prefix) or (prefix == "docker_" and action_name.ends_with("_docker"))
        if not in_group:
            continue
        if SaShortcutStore.is_engine_action(action):
            # Godot's own ui_ actions, arrows and focus, are not Sara's to
            # list, and neither is an alias: it is shown under the name it
            # mirrors and moves with it.
            continue
        out.append(action)
    out.sort_custom(_by_importance)
    return out


## Rows within a section follow [constant ORDER], and what is not in it follows
## by action name, counted the way a painter counts.
##
## Not `InputMap.get_actions()`, which is registration order: the Interface
## section would open on Quit because `ui_quit` is declared first in
## project.godot, and a module's tool would land wherever its load happened to
## fall. An unlabelled action sorts by its identifier rather than by its display
## name, because this is static and a display name needs the tool registry.
##
## **The name is compared naturally**, and a locked summon as the summon it
## locks. A plain comparison of the text puts `brush_slot_10` between slot 1 and
## slot 2, and files every `docker_summon_locked_` id in one block between
## `docker_summon_layers` and `docker_summon_minimap`, so the Brush section
## reads 1, 10, 2 and the Dockers section splits its summons round the locked
## ones. A locked twin and its summon share a key, and the summon, the shorter
## id, comes first.
##
## The underscores are compared as spaces, because Godot's natural comparison
## sorts an underscore after every letter, which puts `docker_summon_toolbox`
## before `docker_summon_tool_options` where the rows read Toolbox after Tool
## Options. A word boundary sorts first, as it does between the titles.
static func _by_importance(a: StringName, b: StringName) -> bool:
    var rank_a := ORDER.find(a)
    var rank_b := ORDER.find(b)
    if rank_a < 0:
        rank_a = ORDER.size()
    if rank_b < 0:
        rank_b = ORDER.size()
    if rank_a != rank_b:
        return rank_a < rank_b
    var by_name := _sort_name(a).naturalnocasecmp_to(_sort_name(b))
    if by_name != 0:
        return by_name < 0
    return String(a).length() < String(b).length()


## The name *action* sorts by, its words apart: its own, or for a locked
## summon the summon it locks, which `SaAppCommands.locked_summon_id` builds by
## putting `locked_` after the summon prefix.
static func _sort_name(action: StringName) -> String:
    var locked := SaShortcutStore.SUMMON_PREFIX + "locked_"
    var action_name := String(action)
    if action_name.begins_with(locked):
        action_name = SaShortcutStore.SUMMON_PREFIX + action_name.trim_prefix(locked)
    return action_name.replace("_", " ")


## The rows for one prefix as `[label, keys]`, which is what the Help suite and
## anything else reading the list rather than editing it wants.
##
## An action with no chord is left out here and kept by [method actions_for],
## and the difference is what the two surfaces are for: Help prints what the
## keys do, and a line naming no key claims nothing, while the page offers to
## give one.
static func rows_for(
    prefix: String, tools: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null
) -> Array:
    var rows: Array = []
    for action: StringName in actions_for(prefix):
        var keys := keys_for(action)
        if keys.is_empty():
            continue
        rows.append([label_for(String(action), tools, filters, commands), keys])
    return rows


## The words a row reads as: the command's title, then the words of an action
## no command holds, then the title the tool or the filter declared, then the
## identifier capitalized.
##
## The command's title first, because it is the one copy of a command's name:
## the menus draw it too, as the command's label when it has a shorter one. A
## filter is asked for its own title because a table in the skeleton cannot name
## a stranger's filters, and a student's box blur in a folder `box-blur`, whose
## command is `filter_box_blur_box_blur`, would read "Filter Box Blur Box" from
## its id.
static func label_for(
    action: String, tools: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null
) -> String:
    var descriptor := commands.get_descriptor(StringName(action)) if commands != null else null
    if descriptor != null and not descriptor.title.is_empty():
        return descriptor.shown_title()
    if WORDS.has(action):
        return WORDS[action]
    if action.begins_with(SaFilterRegistry.COMMAND_PREFIX) and filters != null:
        for key: StringName in filters.list_keys():
            var filter := filters.get_filter(key)
            if String(SaFilterRegistry.command_for(key, filter)) == action:
                return filter.title()
    if action.begins_with("tool_") and tools != null:
        for tool: SaToolDescriptor in tools.list_descriptors():
            if String(tool.activate_action) == action:
                return tool.display_name
            if String(tool.quick_action) == action:
                return tool.display_name + " while held"
    var bare := action
    for prefix: String in ["tool_", "docker_"]:
        bare = bare.trim_prefix(prefix)
    return bare.capitalize()


## Whether *needle*, a search already lowercase and trimmed, names one of
## *chords*: every part of it is a part of the one chord. "ctrl+j" finds Ctrl+J
## and Ctrl+Shift+J, "shift" every chord held with Shift and the Shift drag, and
## "drag" every drag, whose keys are words.
##
## **A lone character is a whole key**, so "m" finds M and not Numpad or Middle
## drag, and "a" finds A and not the "a" of "on a docker".
static func chord_answers(chords: Array, needle: String) -> bool:
    var wanted := chord_parts(needle)
    for chord: Variant in chords:
        var text := String(chord).to_lower()
        if needle.length() == 1:
            if text.substr(SaCommandRegistry.key_name_at(text)).strip_edges() == needle:
                return true
            continue
        var parts := chord_parts(text)
        if not wanted.is_empty() and wanted.all(func(part: String) -> bool: return parts.has(part)):
            return true
    return false


## The parts a chord reads as: each modifier, and each word of the key's name.
## "ctrl+shift+z" is ctrl, shift and z, "ctrl+numpad +" ctrl, numpad and +, and
## a gesture's "alt + left drag on a docker" alt, left, drag, on, a and docker.
## `key_name_at` makes the cut, so the plus key is a key and not a separator.
static func chord_parts(chord: String) -> Array[String]:
    var cut := SaCommandRegistry.key_name_at(chord)
    var out: Array[String] = []
    for part: String in chord.substr(0, cut).split("+", false):
        if not part.strip_edges().is_empty():
            out.append(part.strip_edges())
    for word: String in chord.substr(cut).split(" ", false):
        out.append(word)
    return out


## "Ctrl+Z" or "Ctrl+Z, Ctrl+Shift+Z", from every key event the action has.
##
## The formatting lives on the command registry, because the toolbox tooltip
## needs the same sentence and a second copy of it drifts.
static func keys_for(action: StringName) -> String:
    return SaCommandRegistry.format_events(InputMap.action_get_events(action), 1)
