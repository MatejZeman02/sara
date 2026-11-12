## The application's own commands: the ones whose home is a dialog, a filter or
## a docker rather than the document.
##
## Commands rather than menu entries alone, so the shortcuts dialog and a chord
## reach Preferences, the two adjustments and the dockers as they reach the
## rest.
##
## They register through the same door a module's command uses, and they live
## here rather than in main.gd because a chord is not a window's business. The
## chords are Krita's map where it has one: `krita_filter_hsvadjustment` is Ctrl+U there. Krita
## leaves `options_configure` unbound, so Preferences takes the Ctrl+comma every
## other program uses, and Brightness/Contrast takes Photoshop's Ctrl+Shift+B
## because Krita has none.
class_name SaAppCommands
extends RefCounted

## The dockers that shipped without a chord. Each row is the command id, the
## registered docker id, the title and the key, and every existing docker chord
## is Shift with a letter, so these follow: Shift+T is the layers and Shift+V the
## minimap.
##
## **Shift with a tool's key steps that tool's family**, see [SaToolFamilies],
## so a docker toggle on Shift and a tool's letter gave the chord up. The
## toolbox on B, the colour picker on C, Recent Presets on E and the Pop-up
## Palette on W hold no toggle chord in Sara's own map. Every letter under the
## left hand is taken, so none of the four moved to another, and each is still
## reached from the Window menu and by its summon on Alt+Shift with the same
## letter. `TOGGLE_UNBOUND` names the two this table registers, and
## `project.godot` holds no chord on the other two.
##
## **Every letter is under the left hand**, because the left little finger
## holds Shift and a right-hand letter put the pen down. Five rows moved off M,
## O, H, P and U to letters Shift held nothing on in any table, and Shift+Q is
## Quick Favourites. The summon and its locked twin follow the row, and the
## row carries their titles whole, so a language that declines the docker's
## name translates each title as one message.
##
## A row may carry a seventh element, a second bare key the same command answers
## to. Only the presets docker has one, and the paragraph on its row says what
## it cost.
const DOCKER_COMMANDS: Array = [
    # X, because Shift+R is Repeat Last, the Blender chord, and X was the one
    # letter under the left hand Shift held nothing on in any of the three
    # shipped profiles when it was chosen.
    [
        &"docker_recorder",
        SaDockerIds.RECORDER,
        "Recorder docker",
        KEY_X,
        "Summon Recorder docker",
        "Summon Recorder docker and lock it"
    ],
    # V for view, because the minimap is the view of the whole picture, and a letter that says what the docker is gets
    # remembered. C is the crop's key, so the colour picker has no toggle chord.
    # A, the one letter of its own name under the left hand, went to the graph,
    # which has no other.
    [
        &"docker_minimap",
        SaDockerIds.MINIMAP,
        "Minimap docker",
        KEY_V,
        "Summon Minimap docker",
        "Summon Minimap docker and lock it"
    ],
    # D, on the home row, for the one of the five the default layout opens. Its
    # own letters, T and S, are the layers and the presets, and Krita's shipped
    # profile keeps the backslash for it.
    [
        &"docker_tool_options",
        SaDockerIds.TOOL_OPTIONS,
        "Tool Options docker",
        KEY_D,
        "Summon Tool Options docker",
        "Summon Tool Options docker and lock it"
    ],
    # A, the one letter of graph under the left hand that nothing held: Shift+G
    # steps the fill family and Shift+R is Repeat Last.
    [&"docker_graph", SaDockerIds.GRAPH, "Graph docker", KEY_A, "Summon Graph docker", "Summon Graph docker and lock it"],
    # E, the letter both words of the name hold under the left hand that was
    # free. Shift+R is Repeat Last, Shift+T the layers and Shift+S the presets.
    # The name follows the docker's own rather than History. The toggle holds no
    # chord, because Shift+E steps the eraser's family, and the summon keeps E.
    [
        &"docker_history",
        SaDockerIds.HISTORY,
        "Recent Presets docker",
        KEY_E,
        "Summon Recent Presets docker",
        "Summon Recent Presets docker and lock it"
    ],
    # Z, the key undo is on as Ctrl+Z. The router matches the modifiers exactly,
    # so Shift+Z alone is not redo's Ctrl+Shift+Z.
    [
        &"docker_undo",
        SaDockerIds.UNDO,
        "Undo History docker",
        KEY_Z,
        "Summon Undo History docker",
        "Summon Undo History docker and lock it"
    ],
    # F for reference, since Shift+R is Repeat Last and every other letter
    # the word offers is taken: E is the eraser, N is nothing anyone would
    # guess, and C is the crop.
    [
        &"docker_reference",
        SaDockerIds.REFERENCE,
        "Reference docker",
        KEY_F,
        "Summon Reference docker",
        "Summon Reference docker and lock it"
    ],
    # S for presets, because every other letter of the two words under the left
    # hand is taken: B and E are tool keys whose Shift chord steps a family,
    # Shift+R is Repeat Last and Shift+T the layers. Bare B is the brush tool,
    # which is the whole reason a docker's chord holds Shift.
    #
    # **And bare Z beside it**, as in Krita, which is why `tool_zoom` in
    # `project.godot` holds no Z. The command table is answered before the tool
    # table in `ShortcutRouter.handle`, so Z here takes the key from the zoom
    # tool whether or not that binding stays, and a binding that can never fire
    # is worse than none: the Keyboard Shortcuts page would show two rows
    # claiming Z and only one of them true. The zoom tool keeps Ctrl+Space, the
    # toolbox and the scroll wheel, and Photoshop's shipped profile puts Z back
    # on it for a painter who picks that map.
    [
        &"docker_brush_presets",
        SaDockerIds.BRUSH_PRESETS,
        "Brush Presets docker",
        KEY_S,
        "Summon Brush Presets docker",
        "Summon Brush Presets docker and lock it",
        KEY_Z
    ],
    # W for wheel, free with Alt and Shift in Sara's own map. Shift+W steps the
    # Magic Wand's family there and is Krita's wrap in the Krita profile, so
    # the toggle holds no chord and the summon keeps W.
    [
        &"docker_palette",
        SaDockerIds.PALETTE,
        "Pop-up Palette",
        KEY_W,
        "Summon Pop-up Palette",
        "Summon Pop-up Palette and lock it"
    ],
]

## The four dockers whose toggle is an action in `project.godot` rather than a
## row above, in the same shape, so each gets a summon beside its toggle. The
## toggles stay where they are: only the summon is registered from here.
const OLDER_DOCKERS: Array = [
    [
        &"docker_toolbox",
        SaDockerIds.TOOLBOX,
        "Toolbox docker",
        KEY_B,
        "Summon Toolbox docker",
        "Summon Toolbox docker and lock it"
    ],
    [&"docker_layers", SaDockerIds.LAYERS, "Layers docker", KEY_T, "Summon Layers docker", "Summon Layers docker and lock it"],
    # C for colour, and V the minimap's, for view. Its toggle in `project.godot` holds the same letter, so the summon
    # follows the toggle.
    [
        &"docker_color_selector",
        SaDockerIds.COLOR,
        "Colour Picker docker",
        KEY_C,
        "Summon Colour Picker docker",
        "Summon Colour Picker docker and lock it"
    ],
    # F9 rather than F1, which nearly every desktop program answers with its
    # help and which is the manual's, and rather than F12, the key browsers give
    # their developer tools, because KDE Plasma's compositor holds Alt+Shift+F12
    # to suspend itself, which would take the summon. Neither desktop holds F9,
    # Alt+Shift+F9 or Ctrl+Alt+Shift+F9: GNOME's Ctrl+Alt+F9 and Plasma's
    # Ctrl+F9 are chords of their own.
    [&"info_docker", SaDockerIds.INFO, "Info docker", KEY_F9, "Summon Info docker", "Summon Info docker and lock it"],
]

## The toggles of the rows above that hold no chord of their own, because the
## same Shift chord steps a tool's family. Their summons keep the row's key.
const TOGGLE_UNBOUND: Array[StringName] = [&"docker_history", &"docker_palette"]


## Registers the lot against the skeleton, which is what owns them.
##
## `toggle_docker` takes a registered docker id and flips that docker, because
## showing one is more than setting `visible`: the geometry is restored, the
## Dockers menu's tick follows and the layout is saved. Main owns all three, so
## it hands the door over rather than having it copied here.
##
## `tool_machine_provider` answers the main canvas's tool machine, the same
## provider the router is handed, so the mirrors find the view the router's
## zoom chords move. A host with no canvas, which is what a test builds, leaves
## it empty and the mirrors decline.
##
## `summon_docker` takes a registered docker id and shows that docker under the
## pointer on a borrow, which is `MainDockers`' for the reason `toggle_docker`
## is. A host that hands none still registers the summons, so their chords are
## in the InputMap for the shortcuts page and the profiles.
static func register_all(
    registries: SaRegistries,
    toggle_docker: Callable,
    tool_machine_provider: Callable = Callable(),
    summon_docker: Callable = Callable()
) -> void:
    if registries == null or registries.context == null:
        push_error("SaAppCommands: the context must be built before the commands are registered.")
        return
    var ctx := registries.context.for_module(&"sara-skeleton")
    _register_preferences(ctx)
    _register_fullscreen(ctx)
    _register_image_size(ctx)
    _register_mirrors(ctx, tool_machine_provider)
    _register_dockers(ctx, toggle_docker)
    # The painter's composed dockers, a toggle each, from the library that keeps them.
    SaComposedDockers.register_commands(ctx.ui, ctx.commands, toggle_docker)
    _register_summons(ctx, summon_docker)
    SaToolFamilies.register_all(ctx, tool_machine_provider)
    _register_brush_editor(ctx)
    _register_picker_shape(ctx)
    _register_reload_shaders(ctx)
    ReferenceDocker.register_solo(ctx)
    LayersDocker.register_rename(ctx)
    SaEffectsLut.register(ctx)
    SaStatusLine.register_command(ctx)
    SaEnvironmentView.register_command(ctx)
    SaIsolateActiveLayer.register_command(ctx)
    SaTopBarPageEdges.register_command(ctx)
    SaTopBarDoubleResolution.register_command(ctx)
    ToolOptionsPresets.register_previous(ctx)
    SaRecentPresetWalk.register(ctx)
    SaQuickCommands.register(ctx)
    # The ten brush slots, from their own file: ten commands off one table is a
    # different shape from the singular ones above, and the Brush Slots page
    # asks that file the same questions a chord does.
    SaBrushSlotCommands.register_all(ctx)
    # The ten opacity digits, from their own file for the same reason.
    SaOpacityDigitCommands.register_all(ctx, tool_machine_provider)
    SaSearchWindow.register_command(ctx, toggle_docker, tool_machine_provider)


## Modules > Reload Shaders, on Ctrl+Shift+R in Sara's map and Photoshop's.
##
## A debug build already rescans every thirty frames and recompiles everything
## when anything moved, and a shipped build does not scan at all, so this is the
## door that works in both and only does the work that changed. A row of the
## Modules menu's Develop section, beside Reload Modules, rather than an action
## `show_in_modules_menu` files under a heading. R is the word's own letter. The
## Krita profile clears the chord, which Krita gives to Paste as Reference Image,
## a painter's action.
static func _register_reload_shaders(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"modules_reload_shaders", "Reload shaders", _reload_shaders)
    command.label = "Reload Shaders"
    command.default_events = [chord(KEY_R, true, true)]
    command.category = &"modules"
    command.sentence = "Recompile every kernel whose file changed. One that fails to compile keeps the one that worked."
    ctx.register_command(command)


## Runs the reload and says in the corner what came of it, the failures by name
## with the first line of the compiler's message, because a kernel that kept its
## old pipeline paints as if nothing happened and the corner is the only place
## that says otherwise.
static func _reload_shaders() -> bool:
    SaMessage.notice(reload_notice(GlobalShaderCompiler.reload_changed()))
    return true


## The corner line for a reload's *result*, for the command and for a suite.
static func reload_notice(result: Dictionary) -> String:
    var rebuilt: Array = result.get("rebuilt", [])
    var failed: Dictionary = result.get("failed", {})
    if rebuilt.is_empty() and failed.is_empty():
        return "No shader changed."
    var line := "Reloaded %d shader%s." % [rebuilt.size(), "" if rebuilt.size() == 1 else "s"]
    for shader_name: String in failed:
        var message := String(failed[shader_name]).strip_edges().split("\n")[0]
        line += " %s kept its last build: %s" % [shader_name, message]
    return line


## F5, Krita's own chord for Edit Brush Settings, rather than Ctrl+Shift+E,
## which is Krita's Merge Visible and Sara's. The map's function keys are F1 for
## the manual, F5 for this, F9 for the Info docker and F11 for full screen.
static func _register_brush_editor(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"edit_brush", "Edit brush", _open_brush_editor)
    command.label = "Edit Brush..."
    command.sentence = "Opens the brush editor on the brush in hand."
    command.default_events = [chord(KEY_F5)]
    command.category = &"edit"
    ctx.register_command(command)


## Deferred, for the reason `_open_preferences` gives one file over: a chord
## pressed over an open menu arrives while that popup is mid-hide.
static func _open_brush_editor() -> bool:
    _open_brush_editor_deferred.call_deferred()
    return true


static func _open_brush_editor_deferred() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    # A toggle, so a null from a close is no failure, and only a missing bar is.
    if SaBrushEditorDoor.toggle(tree) == null and SaBrushEditorDoor.tool_options_bar(tree) == null:
        push_warning("SaAppCommands: no tool options bar, so there is no tool to edit")


## The colour picker's shapes, stepped by a chord.
##
## There are seven shapes, so the toggle is a step that wraps. The id begins
## with `color_` so the Keyboard Shortcuts page files it under Colour beside the
## swap and the reset, which is where a painter looking for it would look.
##
## **Ctrl+Shift+K rather than unbound**, because
## `ui/shortcuts/tests/test_command_chords.gd` settles it either way:
## every registered command answers to a chord, the three symmetry switches are
## the only stated exception bar the docker toggles that gave their Shift chord
## to a tool's family, and a second test asserts the three are the only others.
## An unbound command is not a thing this build means to have, so the question
## is which key and not whether.
##
## Ctrl+Shift with a letter is where Sara puts what is neither a docker nor a
## tool, Merge Visible on Ctrl+Shift+E among them, and the two families this
## would otherwise fall into are spoken for: Shift with a letter toggles a docker
## or steps a tool's family, and a bare letter is a tool. K is the code's own word for a
## picker shape, `KIND_KEYS` and `set_kind`, and it is free in the build's map
## and in both shipped profiles.
static func _register_picker_shape(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"color_picker_shape_next", "Next colour picker shape", _next_picker_shape)
    command.default_events = [chord(KEY_K, true, true)]
    command.category = &"color"
    command.sentence = "Step the colour docker's picker to the next shape, wrapping past the last one."
    ctx.register_command(command)


## Not deferred, unlike the two above: this opens no window and closes no menu,
## it writes one setting, and the pickers redraw on the signal.
static func _next_picker_shape() -> bool:
    SaColorPicker.step_shape_kind(1)
    return true


## Ctrl+comma, which is what a painter arriving from anywhere else presses.
static func _register_preferences(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"edit_preferences", "Preferences", _open_preferences)
    command.default_events = [chord(KEY_COMMA, true)]
    command.category = &"edit"
    command.sentence = "Sara's own settings: the interface, the theme, colour spaces, shortcuts and the tablet."
    command.label = "Preferences..."
    ctx.register_command(command)


## F11 alone, which is what every other application on the desktop uses.
##
## **F11 instead of Krita's Ctrl+Shift+F rather than beside it**, so that chord
## is free in the build's map. The shipped Krita profile still names
## it, because that table is Krita's own map and not this build's.
##
## A profile saved while the pair was the default holds no entry for the
## command, since a profile keeps only differences, and so reads F11 alone. One
## that wrote the pair out, which a painter who added F11 by hand when
## Ctrl+Shift+F was the only chord did, is read as no entry too by
## `SaShortcutStore.load_profile`. A binding of a painter's own is kept.
##
## It is a command rather than an action in `project.godot` and a branch of
## `ui/shortcuts/shortcut_router.gd`. The registry builds an InputMap action for
## every command it takes, so an action added by hand would be a second one,
## invisible to the Keyboard Shortcuts page and unrebindable.
static func _register_fullscreen(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"window_fullscreen", "Fullscreen", _toggle_fullscreen)
    command.default_events = [chord(KEY_F11)]
    command.category = &"window"
    command.sentence = "Fill the screen with Sara's window."
    command.checked = is_fullscreen
    ctx.register_command(command)


## Image > Canvas Size and Image > Image Size, on Krita's own Ctrl+Alt+C and
## Ctrl+Alt+I.
##
## They are the two entries of Krita's 201 defaults that name a Sara feature
## which exists and has a door anything can knock on, `canvassize` and
## `imagesize`, so they are chords and not menu rows alone.
##
## Commands rather than `[input]` actions, for the reason the fullscreen chord
## above gives: the registry builds an InputMap action for every command it
## takes, so an action added by hand would be a second one the Keyboard
## Shortcuts page cannot see and nobody can rebind.
##
## **Select > Feather is the third and is not here.** Krita puts it on Shift+F6
## and Sara has the dialog, but `ui/menus/select_menu.gd` builds it inside its
## own handler and emits nothing, so there is no door for a command to reach it
## through. Giving it one is a change to that file, and it is the whole of what
## stands between that chord and existing.
static func _register_image_size(ctx: SaContext) -> void:
    var canvas_size := SaCommandDescriptor.create(&"image_canvas_size", "Canvas size", _open_canvas_size)
    canvas_size.default_events = [chord(KEY_C, true, false, true)]
    canvas_size.category = &"image"
    canvas_size.label = "Canvas Size..."
    canvas_size.sentence = ("Keep the pixels and change the canvas around them, anchored where you choose. Nothing is resampled.")
    ctx.register_command(canvas_size)

    var image_size := SaCommandDescriptor.create(&"image_size", "Image size", _open_image_size)
    image_size.default_events = [chord(KEY_I, true, false, true)]
    image_size.category = &"image"
    image_size.label = "Image Size..."
    image_size.sentence = "Keep the picture and change the pixels: resample every layer to a new size."
    ctx.register_command(image_size)


## Plain H for the horizontal flip and Ctrl+Shift+H for the vertical.
##
## H because nothing else holds it: not this build's own map, where every docker
## chord is Shift with a letter and `docker_graph` has the Shift+H, not the
## `[input]` section of `project.godot`, and not either shipped profile in
## `core/registry/shortcuts/sa_shortcut_store.gd`, since Krita leaves the canvas
## mirror on M and Photoshop has none. The vertical takes the same key under
## Ctrl and Shift so the pair reads as one chord and its opposite, rather than
## borrowing a letter from a word nobody would guess.
##
## Commands rather than actions in `project.godot`, for the reason the
## fullscreen chord above gives: the registry builds an InputMap action for
## every command it takes, so an action added by hand would be a second one that
## the Keyboard Shortcuts page cannot see and nobody can rebind.
##
## Named Flip, as the Minimap's buttons are, and never Mirror, the word a
## painter reads as the bar's symmetry, because one name for both has a painter
## who means to check a face by flipping it turn on symmetry and paint two
## noses. The ids keep the old word,
## because a stored shortcut map names them.
static func _register_mirrors(ctx: SaContext, tool_machine_provider: Callable) -> void:
    var horizontal := SaCommandDescriptor.create(
        &"view_mirror_horizontal", "Flip view horizontally", _mirror.bind(tool_machine_provider, true)
    )
    horizontal.label = "Flip View Horizontally"
    horizontal.default_events = [chord(KEY_H)]
    horizontal.category = &"view"
    horizontal.sentence = "Flip the view left to right. The picture is not changed."
    horizontal.checked = _mirrored.bind(tool_machine_provider, true)
    ctx.register_command(horizontal)

    var vertical := SaCommandDescriptor.create(
        &"view_mirror_vertical", "Flip view vertically", _mirror.bind(tool_machine_provider, false)
    )
    vertical.label = "Flip View Vertically"
    vertical.default_events = [chord(KEY_H, true, true)]
    vertical.category = &"view"
    vertical.sentence = "Flip the view top to bottom. The picture is not changed."
    vertical.checked = _mirrored.bind(tool_machine_provider, false)
    ctx.register_command(vertical)


static func _register_dockers(ctx: SaContext, toggle_docker: Callable) -> void:
    for entry: Array in DOCKER_COMMANDS:
        var command := SaCommandDescriptor.create(entry[0], entry[2], _toggle_docker.bind(toggle_docker, entry[1]))
        command.default_events = [] if TOGGLE_UNBOUND.has(entry[0]) else [chord(entry[3], false, true)]
        # The optional second key, bare. One row has one and the rest are three
        # elements long, so the size is asked rather than a KEY_NONE written
        # into every other row.
        if entry.size() > 6:
            command.default_events.append(chord(entry[6]))
        command.category = &"docker"
        ctx.register_command(command)


## One summon per docker, from both tables, so a docker given a toggle row
## tomorrow gets its summon with it.
##
## The id is `SaShortcutStore.SUMMON_PREFIX` and the docker's word from its
## toggle, `docker_summon_layers` beside `docker_layers` and `docker_summon_info`
## beside `info_docker`, which is how the two shipped maps from other programs
## know to leave it unbound.
## The chord is the toggle's with Alt added, Alt+Shift with the docker's own
## letter, so the pair reads as one on the shortcuts page. A toggle that gave
## its Shift chord to a tool's family keeps the letter all the same, and its
## summon is then the docker's only key. Alt rather than Ctrl
## because Ctrl+Shift is already Brightness/Contrast on B, the note on C, Reload
## Shaders on R, Flip View Vertically on H and Redo on Z, and no
## Alt+Shift chord was taken. The Info docker's toggle is a bare F9 and its
## summon is Alt+Shift+F9 all the same, because a bare Alt with a function key
## is a desktop's to take, as GNOME has held Alt+F1 for its own menu, and one
## rule is easier to remember than one rule and a case.
##
## **Each summon has a locked twin**, the same chord with Ctrl held, which shows
## the docker with the lock already on. A chord of its own rather than a modifier
## the handler reads, because the router matches the modifiers exactly: a press
## of Ctrl+Alt+Shift+T never reaches Alt+Shift+T's action at all. Ctrl on top of
## the Alt and the Shift the pair already holds was free on every docker's
## letter, and the Keyboard Shortcuts page files the twin beside its summon.
static func _register_summons(ctx: SaContext, summon_docker: Callable) -> void:
    for entry: Array in DOCKER_COMMANDS + OLDER_DOCKERS:
        var id := summon_id(entry[0])
        var command := SaCommandDescriptor.create(id, entry[4], _summon_docker.bind(summon_docker, entry[1]))
        command.default_events = [chord(entry[3], false, true, true)]
        command.category = &"docker"
        command.sentence = "Show the %s under the pointer until it moves away. Press again to close." % entry[2]
        # A summon is a chord's gesture at the pointer, and the search lists the
        # docker itself, so neither summon is a row of it.
        command.show_in_search = false
        ctx.register_command(command)

        var locked := SaCommandDescriptor.create(
            locked_summon_id(entry[0]), entry[5], _summon_docker_locked.bind(summon_docker, entry[1])
        )
        locked.default_events = [chord(entry[3], true, true, true)]
        locked.category = &"docker"
        locked.sentence = (
            "Show the %s under the pointer with the lock on, so it stays until it is closed or unlocked." % entry[2]
        )
        locked.show_in_search = false
        ctx.register_command(locked)


## A key event for the InputMap, by keycode rather than by physical keycode, so
## the chord is the one printed on the key the painter is looking at.
##
## `alt` is last, for Krita's Ctrl+Alt+C and Ctrl+Alt+I, so a call naming only
## Ctrl and Shift reads the same with or without it.
static func chord(keycode: Key, ctrl: bool = false, shift: bool = false, alt: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    event.alt_pressed = alt
    return event


## Deferred for the reason the Edit menu gives: a chord pressed over an open
## menu arrives while that popup is still mid-hide, and a window that takes
## focus from inside that re-entrancy desynchronises the engine's popup
## bookkeeping.
static func _open_preferences() -> bool:
    EventBus.preferences_requested.emit.call_deferred()
    return true


## The mode the main window goes to, given the mode it is in and the mode to
## come back to. Pure, so the arithmetic is testable without a display: a
## headless run has a dummy DisplayServer that answers every window call and
## changes nothing.
##
## A window that was maximised comes back maximised rather than to a plain
## windowed rectangle, which is the difference between a fullscreen a painter
## can leave and one that costs them their layout on the way out.
static func fullscreen_target(
    current: DisplayServer.WindowMode, restore: DisplayServer.WindowMode, is_android: bool = false
) -> DisplayServer.WindowMode:
    if is_fullscreen_mode(current):
        if (
            (is_android or OS.has_feature("android") or OS.get_name() == "Android")
            and restore == DisplayServer.WINDOW_MODE_WINDOWED
        ):
            return DisplayServer.WINDOW_MODE_MAXIMIZED
        return restore
    return DisplayServer.WINDOW_MODE_FULLSCREEN


static func is_fullscreen_mode(mode: DisplayServer.WindowMode) -> bool:
    return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## True while the main window is in either fullscreen mode, which is what the
## Window menu ticks and what the toggle asks before it decides.
static func is_fullscreen() -> bool:
    return is_fullscreen_mode(DisplayServer.window_get_mode(DisplayServer.MAIN_WINDOW_ID))


## The toggle the chord and the menu row share, static because they are two
## call sites of one function rather than an object anybody holds. Made on the
## first press, so a suite that never presses one never touches the display.
static var _fullscreen: Fullscreen = null


## Fullscreen on the main window and nothing else. The dockers are embedded
## subwindows of it, so they keep the positions they had and grow with the
## viewport: this is the fullscreen that gives the canvas the screen, not the
## one that hides the interface.
static func toggle_fullscreen() -> void:
    if _fullscreen == null:
        var tree := Engine.get_main_loop() as SceneTree
        _fullscreen = Fullscreen.new(_main_window_mode, _set_main_window_mode, tree.process_frame if tree != null else Signal())
    _fullscreen.toggle()


static func _main_window_mode() -> DisplayServer.WindowMode:
    return DisplayServer.window_get_mode(DisplayServer.MAIN_WINDOW_ID)


static func _set_main_window_mode(mode: DisplayServer.WindowMode) -> void:
    DisplayServer.window_set_mode(mode, DisplayServer.MAIN_WINDOW_ID)


static func _toggle_fullscreen() -> bool:
    toggle_fullscreen()
    return true


## The same two signals the Image menu emits, deferred for the same reason it
## defers them: a chord pressed over an open menu arrives while that popup is
## still mid-hide, and a window taking focus from inside that re-entrancy
## desynchronises the engine's popup bookkeeping.
static func _open_canvas_size() -> bool:
    EventBus.canvas_size_requested.emit.call_deferred()
    return true


static func _open_image_size() -> bool:
    EventBus.image_size_requested.emit.call_deferred()
    return true


## Flips the main canvas's view about the middle of the viewport, and says so.
##
## The same `SaView.flip_view` the Minimap's two buttons and the View menu's two
## rows press, so a flip from the chord shows on all three: the buttons read
## the view back every frame and the menu reads it back when it opens. The
## document is untouched, which is why this costs no dispatch and no undo step.
## It asks for no composite, because a view flip needs none.
## The notice says so because a bare H turns the picture over with no other
## sign, and "back" is that axis reading unflipped again.
static func _mirror(tool_machine_provider: Callable, horizontal: bool) -> bool:
    var view := _main_view(tool_machine_provider)
    if view == null:
        return false
    view.flip_view(horizontal)
    var flipped := _mirrored(tool_machine_provider, horizontal)
    SaMessage.notice(TranslationServer.translate("View flipped") if flipped else TranslationServer.translate("View flipped back"))
    return true


## A flip row's tick: whether the main view is flipped that way now.
static func _mirrored(tool_machine_provider: Callable, horizontal: bool) -> bool:
    var view := _main_view(tool_machine_provider)
    var flip := view.get_flip() if view != null else Vector2.ONE
    return (flip.x if horizontal else flip.y) < 0.0


## The main canvas's view, or null on a host with no canvas.
static func _main_view(tool_machine_provider: Callable) -> SaView:
    var tool_machine := tool_machine_provider.call() as ToolMachine if tool_machine_provider.is_valid() else null
    var surface: SaSurface = tool_machine.surface if tool_machine != null else null
    return surface.view if surface != null else null


static func _toggle_docker(toggle_docker: Callable, docker_id: StringName) -> bool:
    if not toggle_docker.is_valid():
        return false
    toggle_docker.call(docker_id)
    return true


## The summon's action id beside the toggle *toggle_id*.
static func summon_id(toggle_id: StringName) -> StringName:
    return StringName(SaShortcutStore.SUMMON_PREFIX + String(toggle_id).trim_prefix("docker_").trim_suffix("_docker"))


## The locked summon's action id, built the same way with `locked` before the
## docker's word, so `docker_summon_locked_layers` sits beside
## `docker_summon_layers` and the rule that leaves every summon unbound in the
## two shipped maps covers it too.
static func locked_summon_id(toggle_id: StringName) -> StringName:
    return StringName(SaShortcutStore.SUMMON_PREFIX + "locked_" + String(toggle_id).trim_prefix("docker_").trim_suffix("_docker"))


static func _summon_docker(summon_docker: Callable, docker_id: StringName) -> bool:
    if not summon_docker.is_valid():
        return false
    summon_docker.call(docker_id)
    return true


## The locked twin's handler. The door takes the lock as its second argument,
## which is `MainDockers.summon_docker_by_id`'s, so a host that hands over a
## Callable answering the plain summon alone never has this one pressed.
static func _summon_docker_locked(summon_docker: Callable, docker_id: StringName) -> bool:
    if not summon_docker.is_valid():
        return false
    summon_docker.call(docker_id, true)
    return true


## The main window's way into fullscreen and back out to the mode it left.
##
## The display is two callables and the frame is a signal, so a suite can drive
## the whole toggle against a stand-in that honours a request, drops one or
## answers late. A headless run has a dummy DisplayServer that changes nothing,
## and the arithmetic of `fullscreen_target` on its own never saw the part
## that goes wrong, which is what was remembered on the way in and what the
## window said once it was out.
##
## **A maximised window can come back from fullscreen reporting windowed**, at
## its old place and size. The toggle remembers the mode it left, so the cause
## is one of two things, and the log tells them apart.
## Either the window read windowed on the way in, which the line `windowed to
## fullscreen` shows, or it was asked for maximised and did not stay there,
## which is a guess at how Windows treats the style change that takes a window
## out of fullscreen and has not been seen yet. The second is met by asking
## again a frame later, at most twice, and by saying so in the log each time.
class Fullscreen:
    extends RefCounted

    ## How many times a return is asked for again before it is given up on. Two
    ## rather than more because a window that refuses three times is refusing.
    const RETRIES: int = 2

    ## The mode of the main window, and the call that sets it.
    var _get_mode: Callable
    var _set_mode: Callable

    ## The frame the return is checked on, or a null signal when the caller
    ## checks by hand with `settle()`.
    var _frames: Signal

    ## Whether this toggle runs under Android, where full screen leaves for a
    ## maximised window under the bars and keeps the choice in preferences.
    var is_android: bool = OS.has_feature("android") or OS.get_name() == "Android"

    ## The mode to come back to. Windowed until a press has seen something else.
    var _restore: DisplayServer.WindowMode = (
        DisplayServer.WINDOW_MODE_MAXIMIZED
        if (OS.has_feature("android") or OS.get_name() == "Android")
        else DisplayServer.WINDOW_MODE_WINDOWED
    )

    ## The mode the last press left fullscreen for and has not yet seen the window
    ## take, or -1 when nothing is owed.
    var _owed: int = -1

    ## How many times the owed mode has been asked for again.
    var _retried: int = 0

    func _init(get_mode: Callable, set_mode: Callable, frames: Signal = Signal()) -> void:
        _get_mode = get_mode
        _set_mode = set_mode
        _frames = frames

    ## One press. Out of a fullscreen goes to the mode that was left, and out of
    ## anything else goes in, remembering what it left every time rather than
    ## once, so a window a painter un-maximised in between is not sent back to
    ## maximised.
    func toggle() -> void:
        var current: DisplayServer.WindowMode = _get_mode.call()
        var going_out := SaAppCommands.is_fullscreen_mode(current)
        if not going_out:
            _restore = current
        var target := SaAppCommands.fullscreen_target(current, _restore, is_android)
        print("SaFullscreen: %s to %s" % [_name(current), _name(target)])
        _set_mode.call(target)
        if is_android:
            SaSettings.screen_mode = "fullscreen" if SaAppCommands.is_fullscreen_mode(target) else "maximised"
        _owed = target if going_out else -1
        _retried = 0
        if _owed >= 0 and not _frames.is_null() and not _frames.is_connected(settle):
            _frames.connect(settle)

    ## Looks at what the window did with the return the last press asked for, and
    ## asks again while it has not taken it. Runs on the frames after a press,
    ## and a suite calls it to be that frame.
    func settle() -> void:
        if _owed < 0:
            _stop_listening()
            return
        var now: DisplayServer.WindowMode = _get_mode.call()
        if now == _owed or SaAppCommands.is_fullscreen_mode(now):
            # Either it took the mode, or another door put it back into
            # fullscreen, and a return nobody wants any more is not owed.
            _owed = -1
            _stop_listening()
            return
        if _retried >= RETRIES:
            print("SaFullscreen: the window stays %s, %s was asked for %d times" % [_name(now), _name(_owed), _retried + 1])
            _owed = -1
            _stop_listening()
            return
        _retried += 1
        print("SaFullscreen: asked for %s, the window says %s, asking again" % [_name(_owed), _name(now)])
        _set_mode.call(_owed)

    func _stop_listening() -> void:
        if not _frames.is_null() and _frames.is_connected(settle):
            _frames.disconnect(settle)

    static func _name(mode: int) -> String:
        match mode:
            DisplayServer.WINDOW_MODE_WINDOWED:
                return "windowed"
            DisplayServer.WINDOW_MODE_MINIMIZED:
                return "minimised"
            DisplayServer.WINDOW_MODE_MAXIMIZED:
                return "maximised"
            DisplayServer.WINDOW_MODE_FULLSCREEN:
                return "fullscreen"
            DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
                return "exclusive fullscreen"
        return "mode %d" % mode
