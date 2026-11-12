## Dependencies run one way.
##
## Two scans. The first walks `utils`, `core`, `render`, `tools`, `ui` and
## `harness`, and for every class or autoload a file names, asks whether the
## file it lives in comes after the referrer in the order: utils, then core,
## then render and tools together, because the canvas hosts the tool machine
## and each names the other, then ui, then harness. `core` naming `render` or
## `tools` is not checked, because the rule does not ask it, so
## `NOT_CHECKED_TO` skips those two pairs rather than judging them.
##
## The second walks every module and asks whether the skeleton class it names
## sits behind the door: `core/api`, `core/custom-shader`, `utils`, and under
## `ui` the toolkit, `ui/widgets` and the packages under it, and `ui/page`.
## `DOOR_BY_NAME` holds files the door names by path rather than by folder, and
## is empty.
##
## `UPWARD`, `BY_DESIGN` and `OUTSIDE_THE_DOOR` are today's pairs, each kept
## with the sentence that says why, or `package` where the reach is the
## package's own. A pair the scan finds that none of the three lists carries
## fails the run, and so does a listed pair the tree no longer has, which is how
## a re-cut that drains one is caught leaving it behind.
extends "res://tests/test_framework.gd"

const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch"]
const SKELETON_ROOTS: Array[String] = ["utils", "core", "render", "tools", "ui", "harness"]
const LAYER_RANK: Dictionary = {"utils": 0, "core": 1, "render": 2, "tools": 2, "ui": 3, "harness": 4}

## The one pairing the rule does not ask the scan to judge.
const NOT_CHECKED_FROM := "core"
const NOT_CHECKED_TO: Array[String] = ["render", "tools"]

## Files a module names that are the door by name rather than by folder.
const DOOR_BY_NAME: Array[String] = []

const DOOR_PREFIXES: Array[String] = [
    "core/api/",
    "core/custom-shader/",
    "utils/",
    "ui/themes/",
    "ui/widgets/",
    "ui/page/",
]

## Every upward pair the scan finds today, "referrer -> file", to why. None
## stands. A new one is a failure rather than an entry here.
const UPWARD: Dictionary = {}

## Allowed on purpose and never drained. The sentence is why.
const BY_DESIGN: Dictionary = {
    "ui/main/main.gd -> harness/sa_capture.gd":
    "The boot starts the harness's own capture door, inert until --capture is on the command line.",
    "core/api/filter/sa_filter.gd -> ui/page/sa_dialog.gd":
    "What a filter is handed: build() takes the dialog the filter API hands every module.",
    "core/api/filter/sa_pixel_filter.gd -> ui/page/sa_dialog.gd":
    "The same build() signature, on the pixel function wrapper every scripted filter extends.",
    "core/api/filter/sa_pixel_filter.gd -> ui/page/sa_page_row.gd":
    "A generated slider is a page row, and the filter API builds one per parameter through the same door.",
    "core/api/filter/sa_pixel_filter.gd -> ui/page/time_row/sa_time_row.gd":
    "A pixel function that reads `t` declares in build() the time row a written filter declares in its own.",
}

## Every module pair outside the door today, kept the same way.
const OUTSIDE_THE_DOOR: Dictionary = {
    # The Blender Live docker is a docker window, as every module docker is.
    "modules/sara-base-modules/blender-live/blender_live_docker.gd -> ui/dockers/docker_utils.gd": "package",
    "modules/sara-base-modules/blender-live/blender_live_docker.gd -> ui/dockers/docker_window.gd": "package",
    # The Colourise docker is a docker window, as every module docker is.
    "modules/sara-base-modules/base/colorize/sa_colorize_docker.gd -> ui/dockers/docker_utils.gd": "package",
    "modules/sara-base-modules/base/colorize/sa_colorize_docker.gd -> ui/dockers/docker_window.gd": "package",
    # A view layer that arrives takes its place among the others, and one that
    # goes takes its layer with it, as the OpenRaster reader places its layers.
    "modules/sara-base-modules/blender-live/module.gd -> core/layers/sa_layer_ops.gd": "package",
    # MIDI's page is a
    # Preferences page, which every page extends, and a note naming a preset or
    # a filter that is gone says so in the corner as the rest of the app does.
    "modules/sara-base-modules/midi/midi_bindings.gd -> ui/dialogs/sa_message.gd": "package",
    "modules/sara-base-modules/midi/midi_learning.gd -> ui/dialogs/sa_message.gd": "package",
    "modules/sara-base-modules/midi/midi_page.gd -> ui/settings/settings_page.gd": "package",
    # The tutorials' list of lessons, the recording's box and the lesson's box
    # are dialog windows, with the chrome every window of Sara has, as the
    # Exposure docker is a docker window.
    "modules/sara-tutorials/player/player_box.gd -> ui/dialogs/sa_dialog_window.gd": "package",
    "modules/sara-tutorials/recording/instruction_box.gd -> ui/dialogs/sa_dialog_window.gd": "package",
    "modules/sara-tutorials/tutorials_window.gd -> ui/dialogs/sa_dialog_window.gd": "package",
    # Select Subject's dialog, the source, the size and the
    # licence of the weights it downloads, is a dialog window as well.
    "modules/sara-background-removal/weights_dialog.gd -> ui/dialogs/sa_dialog_window.gd": "package",
    # A text block is a drawn layer made where a click lands: in the group of
    # the layer in front, given its recipe by the drawn layer's own attach, and
    # recorded as one added layer or one recipe step, the calls a drawn layer
    # made by hand has and the door does not offer yet.
    "modules/sara-base-modules/text/edit/sa_text_session.gd -> core/composite/sa_layer_stack.gd": "package",
    "modules/sara-base-modules/text/edit/sa_text_session.gd -> core/layers/drawn/sa_drawn_layer.gd": "package",
    "modules/sara-base-modules/text/edit/sa_text_session.gd -> core/layers/sa_layer_ops.gd": "package",
    # The stamp brush's tip preview names the dab renderer it shares with the
    # editor's stroke strip, which belongs to `core/presets`, whose other module
    # pairs are the same question.
    "modules/sara-base-modules/stamp-brush/ui/sa_tip_preview.gd -> core/presets/sa_preset_thumbs.gd": "package",
    "modules/sara-base-modules/base/module.gd -> core/settings/sa_settings.gd": "package",
    # The Levels histogram polls the easel a canvas holds. The Graph
    # docker's pass it runs over the active layer, and the Curves graph draws
    # behind the curve, is the door's `SaGraphPlot`.
    "modules/sara-base-modules/base/filters/sa_adjust_graph.gd -> core/composite/sa_easel.gd": "package",
    # Module files ask which canvas the painter is working on through one
    # lookup, `SaCanvasView.front_canvas()`. That answer follows the surface
    # `SaDocuments` keeps in front, so it is still one canvas once a second
    # document is open. It lives in `render` because it is the file that knows
    # a view is a Control over an `SaCanvas`, and each of these five already
    # names `SaCanvas` itself, so the pair is one reach widened rather than a
    # new one. The door's `SaInHand.Canvas.front()` answers the same surface,
    # and the pattern capture's below is the one left.
    # The LUT's dialog opens the file picker on `.cube` files, the
    # one picker every dialog opens through. The page has no file row to open it
    # for a filter, and `ui/page` has no room for a new row kind.
    "modules/sara-base-modules/base/usual/lut_filter.gd -> core/app/sa_file_picker.gd": "package",
    # The transform tool's handles drive the layer's live
    # transform, which is kept beside the layer rather than behind the door,
    # so the tool asks it for the map, its refusal and the step it puts.
    "modules/sara-base-modules/base/transform/state_transform.gd -> core/layers/transform/sa_live_transform.gd": "package",
    "modules/sara-base-modules/base/transform/live/sa_transform_live.gd -> core/layers/transform/sa_live_transform.gd": "package",
    # Ctrl+T on a group previews and puts each member's live
    # transform as the tool does one layer's, through the same facade the two
    # entries above reach. The question of which layers sit inside the group is
    # the layer stack's, the one the OpenRaster writer and the Stats docker ask
    # below, and asking it again in the module would be a second answer that
    # goes stale.
    "modules/sara-base-modules/base/transform/group/sa_transform_group.gd -> core/layers/transform/sa_live_transform.gd":
    "package",
    "modules/sara-base-modules/base/transform/group/sa_transform_group.gd -> core/composite/sa_layer_stack.gd": "package",
    # Ctrl+I is the base module's Invert, because its pixels
    # go through the module's own Invert filter, which the skeleton may not
    # name. A mask target is inverted by the mask operations the Layer menu's
    # Invert Mask runs, the picked layers by the one-shot Filter > Invert's
    # Apply writes, a group once through the stack's roots, and the filter's
    # key and command through the registry's own spelling of them. A second
    # answer to any of the four in the module would go stale.
    "modules/sara-base-modules/base/invert_command.gd -> core/layers/masks/sa_mask_ops.gd": "package",
    "modules/sara-base-modules/base/invert_command.gd -> core/layers/sa_filter_ops.gd": "package",
    "modules/sara-base-modules/base/invert_command.gd -> core/composite/sa_layer_stack.gd": "package",
    "modules/sara-base-modules/base/invert_command.gd -> core/registry/sa_filter_registry.gd": "package",
    # The fill's reference group is drawn as the canvas draws it, filters and
    # mask included, and the door's node input leaves both out, so the module
    # asks the tree render the merge and the flatten draw through.
    "modules/sara-base-modules/base/wand/group_picture.gd -> core/layers/sa_tree_render.gd": "package",
    "modules/sara-base-modules/base/tools/state_eyedropper.gd -> core/composite/sa_easel.gd": "package",
    "modules/sara-base-modules/base/ui/sa_color_ramp_control.gd -> core/presets/sa_preset_store.gd": "package",
    "modules/sara-base-modules/stamp-brush/module.gd -> core/colors/sa_color_store.gd": "package",
    "modules/sara-base-modules/stamp-brush/module.gd -> tools/tool_machine.gd": "package",
    "modules/sara-base-modules/stamp-brush/tools/brush_capture_report.gd -> core/presets/sa_preset_store.gd": "package",
    "modules/sara-base-modules/stamp-brush/krita/sa_kpp_import.gd -> core/presets/sa_preset_store.gd": "package",
    "modules/sara-base-modules/stamp-brush/krita/sa_kpp_import_capture.gd -> core/presets/sa_preset_store.gd": "package",
    "modules/sara-base-modules/stamp-brush/pattern/sa_pattern_capture.gd -> render/sa_canvas_view.gd": "package",
    "modules/sara-base-modules/stamp-brush/pattern/sa_pattern_capture.gd -> tools/tool_machine.gd": "package",
    "modules/sara-base-modules/stamp-brush/presets/sa_shipped_bundles.gd -> core/loader/module_loader.gd": "package",
    "modules/sara-base-modules/stamp-brush/presets/sa_shipped_bundles.gd -> core/presets/sa_preset_store.gd": "package",
    # The Exposure docker is a module's docker. A docker's window and drag bar are not behind the door,
    # and its way toggle is a second hand on the filter dialog's ways. Its
    # registry pairs are the types it is handed. Its reads of the
    # settings, the colour pair and the canvas go through the door's `SaInHand`.
    "modules/sara-base-modules/exposure/exposure_docker.gd -> core/registry/sa_filter_registry.gd": "package",
    "modules/sara-base-modules/exposure/exposure_docker.gd -> core/registry/sa_layer_type_registry.gd": "package",
    "modules/sara-base-modules/exposure/exposure_docker.gd -> ui/dockers/docker_utils.gd": "package",
    "modules/sara-base-modules/exposure/exposure_docker.gd -> ui/dockers/docker_window.gd": "package",
    "modules/sara-base-modules/exposure/exposure_layer_row.gd -> core/layers/sa_filter_conversion.gd": "package",
    "modules/sara-base-modules/exposure/exposure_layer_row.gd -> core/layers/sa_filter_ops.gd": "package",
    "modules/sara-base-modules/exposure/exposure_layer_row.gd -> core/registry/sa_filter_registry.gd": "package",
    "modules/sara-base-modules/exposure/exposure_layer_row.gd -> core/registry/sa_layer_type_registry.gd": "package",
    "modules/sara-base-modules/exposure/exposure_way_toggle.gd -> ui/filters/sa_filter_dialog_window.gd": "package",
    # The Sphere docker is the same. The ball reads the
    # canvas the main window shows through the Environment view's composer and
    # lookup, which no door carries, and the window and its drag bar are a
    # docker's as above. The canvas and the layout signal it reads through
    # `SaInHand`.
    "modules/sara-base-modules/sphere/sphere_docker.gd -> render/environment/sa_environment_view.gd": "package",
    "modules/sara-base-modules/sphere/sphere_docker.gd -> ui/dockers/docker_utils.gd": "package",
    "modules/sara-base-modules/sphere/sphere_docker.gd -> ui/dockers/docker_window.gd": "package",
    # The TIFF, Radiance and OpenRaster readers and writers live in the image
    # formats module. A writer is handed the easel the Export
    # dialog reads, and an OpenRaster file is a stack of layers, so its writer
    # walks the stack and asks the compositor for each layer's pixels, and its
    # reader builds the stack through the layer operations a painter's own
    # Add Layer runs. None of the four is behind the door today.
    "modules/sara-base-modules/image-formats/module.gd -> core/composite/sa_easel.gd": "package",
    "modules/sara-base-modules/image-formats/tiff/sa_export_tiff.gd -> core/composite/sa_easel.gd": "package",
    "modules/sara-base-modules/image-formats/open_raster/sa_export_ora.gd -> core/composite/sa_compositor.gd": "package",
    "modules/sara-base-modules/image-formats/open_raster/sa_export_ora.gd -> core/composite/sa_easel.gd": "package",
    "modules/sara-base-modules/image-formats/open_raster/sa_export_ora.gd -> core/composite/sa_layer_stack.gd": "package",
    "modules/sara-base-modules/image-formats/open_raster/sa_ora_reader.gd -> core/composite/sa_layer_stack.gd": "package",
    "modules/sara-base-modules/image-formats/open_raster/sa_ora_reader.gd -> core/layers/sa_layer_ops.gd": "package",
    # The Stats docker's parts are each handed the
    # front surface, which `SaInHand.Canvas` answers, the coverage
    # walks the layer stack past the generated layers, and the session numbers
    # read the stroke recorder's log, neither small enough to pull behind the
    # door for one docker.
    # The idle clock is the autoload whose stops the docker logs, the quantizer
    # switches the view transform the registries hold and moves a setting, and
    # the window, its drag bar and the profile's layout signal are a docker's,
    # as Exposure's and Sphere's are above. Its numbers' service, `SaReductions`,
    # is behind the door in `core/api/reduction`.
    "modules/sara-base-modules/stats/coverage_and_edges.gd -> core/composite/sa_layer_stack.gd": "package",
    "modules/sara-base-modules/stats/coverage_and_edges.gd -> core/layers/generated/sa_generated_layer.gd": "package",
    "modules/sara-base-modules/stats/quantizer.gd -> core/registry/sa_registries.gd": "package",
    "modules/sara-base-modules/stats/quantizer.gd -> core/registry/sa_view_transform_registry.gd": "package",
    "modules/sara-base-modules/stats/session_numbers.gd -> core/pen/sa_stroke_recorder.gd": "package",
    "modules/sara-base-modules/stats/stats_docker.gd -> core/composite/sa_easel.gd": "package",
    "modules/sara-base-modules/stats/stats_docker.gd -> core/idle/sa_idle_clock.gd": "package",
    "modules/sara-base-modules/stats/stats_docker.gd -> core/pen/sa_stroke_recorder.gd": "package",
    "modules/sara-base-modules/stats/stats_docker.gd -> ui/dockers/docker_utils.gd": "package",
    "modules/sara-base-modules/stats/stats_docker.gd -> ui/dockers/docker_window.gd": "package",
    # A vector layer's edit and its undo step are the drawn layer's, which the
    # door's `SaDrawnRecipe` names and leaves in `core/layers/drawn`. The Shape
    # tool, the Object tool's drag and the objects list's buttons each make one,
    # and a second history step of the module's own would keep a recipe the
    # layer's redraw does not.
    "modules/sara-base-modules/vector/sa_vector_place.gd -> core/layers/drawn/sa_drawn_layer.gd": "package",
    "modules/sara-base-modules/vector/tools/state_vector_object.gd -> core/layers/drawn/sa_drawn_layer.gd": "package",
    "modules/sara-base-modules/vector/ui/sa_vector_objects_list.gd -> core/layers/drawn/sa_drawn_layer.gd": "package",
    # The Transform tool's move of a text layer is a recipe step of the drawn
    # layer's, as the Text tool's own edits are, so its undo puts the recipe
    # back and the redraw follows it.
    "modules/sara-base-modules/base/transform/drawn/sa_transform_drawn.gd -> core/layers/drawn/sa_drawn_layer.gd": "package",
}

## The third scan. Every suite under `core`
## or `render` whose code loads a path under `res://ui/` or names a class
## declared under `ui` outside the door, to why it stays. A suite lives beside
## what it tests, so one whose subject is a docker, a page or a dialog moves
## under `ui` with `scripts/move_suites.py`, and the ones here test a `core` or
## `render` class and build a window, a menu or the router only as the fixture
## that shows it. The two scans above skip every `tests` folder, so
## this one reads them. The door's own classes, `SaDialog` and
## the widgets, are no question, since a module names them too.
const SUITES_NAMING_UI: Dictionary = {
    "core/app/tests/test_the_data_folder_the_app_fills_by_itself_stays_bounded.gd":
    "The data tidy, which reads the pasted references' folder off the Reference docker so the two cannot drift.",
    "core/presets/tests/test_a_preset_s_description_is_kept_through_every_write_and_never_copied_as_a_setting.gd":
    "A preset's description through every write, whose rename and Save As are the brush editor's session.",
    "core/composite/debt/tests/test_an_export_taken_right_after_a_layer_is_shown_or_hidden_carries_the_change.gd":
    "The fold debt paid before a read of the picture, the File menu's Export dialog one door into the read of four tests.",
    "core/sad-file/tests/test_a_sad_header_with_a_width_or_height_that_no_dialog_could_have_made_is_refused_by_name.gd":
    "The .sad reader's size check, the three size dialogs' constants read once so the limits cannot drift apart.",
    "core/api/color/tests/test_color_axes_in_use.gd":
    "The four axes' maths, the colour spaces page's solid and compare one reader of four tests in fourteen.",
    "core/api/color/tests/test_document_gamut.gd":
    "The document's declared gamut and its soft proof, the New Document dialog's Custom row one test of ten.",
    "core/api/color/tests/test_new_document_defaults.gd":
    "What a fresh install opens on and the preset that names it, the dialog one test of five.",
    "core/api/color/tests/test_the_exr_gradient.gd":
    "The tonemapper's curve over an opened EXR, the document files the door the picture is opened through.",
    "core/api/color/tests/test_the_list_is_colour_spaces.gd":
    "The colour space presets' names, the page's heading and captions three readers of them.",
    "core/api/color/tests/test_tonemap_view.gd":
    "The tonemapper's plumbing, the settings window holding the exposure that feeds it.",
    "core/api/descriptors/tests/test_layer_types.gd":
    "A module's layer type through the public API, the Layers docker the witness that the docker shows it.",
    "core/api/descriptors/tests/test_module_api_contract.gd":
    "Hard rule 6 as a suite, the ToolBox docker the place a registered tool has to reach.",
    "core/api/document/tests/test_a_double_resolution_layer_composites_at_the_documents_resolution.gd":
    "The composite of a layer at twice the resolution, its thumbnail one test of fourteen.",
    "core/api/document/tests/test_a_layer_at_twice_the_resolution.gd":
    "A layer at twice the resolution made and saved, the Layers docker's 2x mark one test of five.",
    "core/api/document/tests/test_a_load_hands_the_docker_no_freed_layer.gd":
    "The load's order of release, the Layers docker the one reader that saw the freed layer.",
    "core/api/filter/tests/test_filter_sentence.gd":
    "A filter's sentence on its descriptor, the Filter menu and the browser the two readers of one string.",
    "core/api/filter/tests/test_presets_are_a_dialog_row.gd":
    "The presets row a filter's build asks of the door, the dialog window the host that realises it.",
    "core/api/filter/tests/test_the_filter_door_takes_a_double_resolution_layer.gd":
    "The filter door over a layer at twice the resolution, the browser's preview two tests of eight.",
    "core/api/reduction/tests/test_one_reduction_service_runs_the_graph_and_the_numbers_on_one_schedule.gd":
    "The one service under both dockers, the Graph docker one of the two it reads registering on it.",
    "core/api/selection/tests/test_color_range.gd":
    "A colour range into the selection or a mask, the Layers docker the button a painter presses.",
    "core/api/selection/tests/test_selection_drive.gd":
    "The selection regressions, the Tool Options docker's transform rows one test of nine.",
    "core/api/tests/test_a_reloaded_modules_layers_and_menus.gd":
    "A reloaded module's layers resolve again, the Tools menu one test of four.",
    "core/api/tests/test_a_tool_switch_reads_no_disk_and_walks_no_tree.gd":
    "EventBus.tool_changed and what its handlers cost, the presets docker and the options bar two of the handlers timed.",
    "core/api/tests/test_history_depth.gd":
    "The undo budget, the document files the door a picture is opened through in one test of nine.",
    "core/api/tests/test_module_name_from_id.gd": "A module's name from its id, the Filter menu the place the name was drawn.",
    "core/api/tests/test_option_specs.gd": "The option specs a tool declares, the options bar the one builder of them.",
    "core/app/tests/test_a_freeze_leaves_a_line_in_the_log.gd":
    "The watchdog's line in the log, booted through the main scene that starts it.",
    "core/app/tests/test_a_stall_names_the_place_sara_is_in.gd":
    "The trail's place at a stall, a dialog's show and hide one of the two things that write it.",
    "core/export/tests/test_an_export_shows_the_relief.gd": "The export's bake of the relief, the dialog's row one test of nine.",
    "core/export/tests/test_convert_keeps_the_canvas_and_clips_the_png.gd":
    "What Convert does to the canvas and the PNG, the Image menu's question one test of four.",
    "core/export/tests/test_export_carries_the_gamut.gd": "The gamut an export carries, the export dialog one test of seven.",
    "core/export/tests/test_sa_export.gd": "The file formats, the settings window's creation one test of the suite's many.",
    "core/image/precision/tests/test_an_open_document_converts_to_half_precision_and_back_to_full_as_one_history_step.gd":
    "Image > Depth on the card, the Image menu's question one reader of what its count found.",
    "core/image/tests/test_import_fit.gd":
    "The three fits an import is placed by, the dialog that asks one of them the fixture half the tests open.",
    "core/layers/generated/tests/test_a_woven_canvas_ground.gd":
    "The woven ground's height, the Layers docker's ground rows one test of nine.",
    "core/layers/tests/test_a_filter_reaches_a_group_s_layers_or_the_whole_picture_with_affect_all.gd":
    "A bake of a group and of the whole picture in core, the filter dialog the check and the way a painter picks.",
    "core/layers/tests/test_filter_mask.gd": "A filter's mask in core, the Layers docker the button a painter presses.",
    "core/layers/tests/test_filter_on_a_group.gd":
    "A filter on a group and the isolation it asks, the row view one test of four.",
    "core/layers/tests/test_a_new_filter_layer_comes_with_a_mask_that_hides_nothing.gd":
    "Every door to a new filter layer, the kind browser and the Filter dialog two of its four.",
    "core/pen/tests/test_tablet_sweep.gd":
    "The pressure sweep's fit, arithmetic in core/pen, the dialog and its strips the half that paints the reading.",
    "core/perf/tests/test_attaching_or_applying_a_filter_does_not_stall.gd":
    "The frame timers of an attach and an apply, the Layers docker's More list the wait they time.",
    "core/perf/tests/test_boot_marks.gd": "SaBootMarks, timing the main scene's boot it marks.",
    "core/presets/tests/test_an_engine_converts_a_preset.gd":
    "The converter registry and the store's question of it, the preset menu's Convert to rows two tests of seven.",
    "core/presets/tests/test_brush_presets.gd":
    "The recipes the brush ships and what a template carries, the options bar two tests of twenty-three.",
    "core/presets/tests/test_preset_engine.gd": "A preset's engine and its refusal, the chooser's dimmed mark one test of five.",
    "core/presets/tests/test_preset_thumbs.gd":
    "The thumbnail renderer in core/presets, the editor's stroke strip one reader of it.",
    "core/registry/tests/test_a_strangers_tool_asks_the_descriptor.gd":
    "The registry's descriptor door, the Info and Brush Presets dockers the readers that ask it.",
    "core/registry/tests/test_filter_declarations.gd":
    "The command and chord a filter declares in the registry, the router and the dialog the fixtures that answer them.",
    "core/registry/tests/test_import_from_krita_reads_every_key_name_krita_writes.gd":
    "The shortcut store's Krita import, the app's commands the fixture and the page's notice one test of seven.",
    "core/registry/tests/test_krita_profile.gd":
    "The shortcut store's Krita table, the app's commands and the router the fixture that gives every action its name.",
    "core/registry/tests/test_profile_chords.gd":
    "A shortcut profile's chords, the dockers' rows the claimants the table hands them to.",
    "core/registry/tests/test_rebind_survives.gd":
    "The shortcut store keeping a rebind through a restart, the page the place a painter rebinds.",
    "core/registry/tests/test_shape_check.gd": "The shape check as a view mode, the router and the View menu two tests of seven.",
    "core/registry/tests/test_shortcut_profiles.gd":
    "The shortcut store's shipped profiles and the Krita import, the page's save one test of six.",
    "core/registry/tests/test_the_numpad_chords_in_two_steps.gd":
    "The shortcut store's two-step profile load, the app's commands and the router the fixture that builds the map.",
    "core/registry/tests/test_the_shortcut_table_names_no_module.gd":
    "The shortcut table names no module, the Keyboard Shortcuts page one reader of its titles.",
    "core/registry/tests/test_the_two_fill_chords_fill.gd":
    "The two fill chords in the store and the fill they run, the router the path a key takes and the page one test of seven.",
    "core/sad-file/tests/test_a_scratch_run_writes_under_its_own_root.gd":
    "The data root a scratch run writes under, the docker layout store one of the writers it checks.",
    "core/sad-file/tests/test_document_dpi.gd": "The document's DPI key in the file, the New Document dialog one test of five.",
    "core/sad-file/tests/test_sa_autosave.gd":
    "The autosave's clock and files, the welcome window's recovery row the reader that offers them.",
    "core/settings/values/tests/test_a_tool_says_where_its_options_sit.gd":
    "SaSettingsLayout's tables and a tool's own order, the options bar the builder that reads them.",
    "core/settings/values/tests/test_pen_buttons.gd": "The pen buttons' bound actions, the tablet page's row one test of six.",
    "core/usage/tests/test_the_tally_counts_what_a_hand_used.gd":
    "The usage tally's six kinds read back, the router, a menu and the dockers the routes a hand takes into it.",
    "render/cursor/tests/test_the_place_comes_from_the_policy.gd":
    "The cursor policy's place, the summon and the drag handle two of its readers.",
    "core/api/tests/test_the_zoom_reads_as_the_picture_s_size_on_screen.gd":
    "The view's two figures and Ctrl+0's reset, the router's two chords and the status line's words two readers of them.",
    "render/tests/test_fit_below_the_top_bar.gd":
    "The canvas's fit, which reads the main scene's top bar to know where the picture starts.",
    "core/custom-shader/tests/test_a_simulation_s_step_can_be_a_pixel_function_and_step_and_t_are_names_it_reads.gd":
    "One suite asks for the rule and for the time a filter plays, the filter panel's scrubber the hand that plays it.",
    (
        "core/layers/adjustment/tests/"
        + "test_affect_all_is_the_adjustment_layer_s_own_so_it_reaches_the_whole_picture_from_inside_a_group.gd"
    ):
    (
        "One suite asks for Affect all on the layer,"
        + " the settings window's check and the Filter dialog's Layer way two of its doors."
    ),
}


func test_the_scans_own_numbers() -> void:
    assert_eq(DOOR_BY_NAME.size(), 0, "No file is the door by name")
    assert_eq(BY_DESIGN.size(), 5, "the boot, the filter API's three and the time row of a pixel function")
    assert_eq(SUITES_NAMING_UI.size(), 68, "The suites that name a ui class outside the door, each kept for the reason beside it")
    assert_eq(UPWARD.size(), 0, "No upward pair stands")
    assert_eq(OUTSIDE_THE_DOOR.size(), 72, "The module pairs that reach outside the door, each kept for the reason beside it")


func test_every_upward_pair_is_listed_and_every_listed_one_still_stands() -> void:
    var files := _files_under(SKELETON_ROOTS)
    var names := _class_and_autoload_map(files)
    var found := _pairs(files, _read_all(files), names, true)
    var unlisted: Array[String] = []
    for key: String in found:
        if not UPWARD.has(key) and not BY_DESIGN.has(key):
            unlisted.append(key)
    assert_true(unlisted.is_empty(), "An upward pair neither UPWARD nor BY_DESIGN carries: %s" % ", ".join(unlisted))
    var stale: Array[String] = []
    for key: String in UPWARD:
        if not found.has(key):
            stale.append(key)
    for key: String in BY_DESIGN:
        if not found.has(key):
            stale.append(key)
    assert_true(stale.is_empty(), "A listed upward pair the tree no longer carries: %s" % ", ".join(stale))
    assert_eq(found.size(), UPWARD.size() + BY_DESIGN.size(), "the scan's own total against the two lists")


func test_every_module_pair_outside_the_door_is_listed_and_every_listed_one_still_stands() -> void:
    var skeleton_files := _files_under(SKELETON_ROOTS)
    var names := _class_and_autoload_map(skeleton_files)
    var module_files := _files_under(["modules"])
    var found := _pairs(module_files, _read_all(module_files), names, false)
    var unlisted: Array[String] = []
    for key: String in found:
        if not OUTSIDE_THE_DOOR.has(key):
            unlisted.append(key)
    assert_true(unlisted.is_empty(), "A module pair outside the door OUTSIDE_THE_DOOR does not carry: %s" % ", ".join(unlisted))
    # A source copy leaves some modules out, and a pair listed for a file in one
    # of them has nothing to be found in there, so it is held only where its
    # referrer is on disk.
    var listed: Array[String] = []
    for key: String in OUTSIDE_THE_DOOR:
        if FileAccess.file_exists("res://" + key.split(" -> ")[0]):
            listed.append(key)
    if listed.size() < OUTSIDE_THE_DOOR.size():
        skip("%d listed module pairs name files this copy of the source leaves out" % (OUTSIDE_THE_DOOR.size() - listed.size()))
    var stale: Array[String] = []
    for key: String in listed:
        if not found.has(key):
            stale.append(key)
    assert_true(stale.is_empty(), "A listed module pair no longer reaches outside the door: %s" % ", ".join(stale))
    assert_eq(found.size(), listed.size(), "the scan's own total against the one list")


func test_core_naming_render_or_tools_is_the_one_pairing_not_checked() -> void:
    assert_false(_is_upward("core", "render"), "core naming render is the exemption")
    assert_false(_is_upward("core", "tools"), "core naming tools is the same exemption")
    assert_true(_is_upward("core", "ui"), "core naming ui is still judged")
    assert_true(_is_upward("core", "harness"), "core naming harness is still judged")
    assert_false(_is_upward("ui", "core"), "ui naming something before it in the order is never upward")


func test_a_file_under_the_door_prefixes_or_by_name_is_inside_it() -> void:
    assert_true(_in_door("core/api/document/sa_document.gd"), "core/api is the door")
    assert_true(_in_door("ui/widgets/choice/sa_choice_button.gd"), "the package under ui/widgets is the door")
    assert_true(_in_door("core/api/color/sa_color_ramp.gd"), "the ramp is the door by its folder")
    assert_false(_in_door("core/settings/sa_settings.gd"), "a core file outside the listed prefixes is outside the door")
    assert_false(_in_door("ui/dockers/docker_utils.gd"), "a docker outside the toolkit is outside the door")


func test_a_planted_core_file_naming_a_scratch_ui_class_is_found() -> void:
    var files: Array[String] = ["core/scratch_s4_referrer.gd"]
    var contents := {"core/scratch_s4_referrer.gd": "var seen := ScratchS4Widget.new()"}
    var names := {"ScratchS4Widget": "ui/scratch_s4_target.gd"}
    var found := _pairs(files, contents, names, true)
    assert_true(found.has("core/scratch_s4_referrer.gd -> ui/scratch_s4_target.gd"), "the planted upward pair is found")


func test_a_planted_module_class_outside_the_door_is_found() -> void:
    var files: Array[String] = ["modules/scratch/scratch_s4.gd"]
    var contents := {"modules/scratch/scratch_s4.gd": "var seen := ScratchS4CoreThing.new()"}
    var names := {"ScratchS4CoreThing": "core/scratch_s4_target.gd"}
    var found := _pairs(files, contents, names, false)
    assert_true(found.has("modules/scratch/scratch_s4.gd -> core/scratch_s4_target.gd"), "the planted door pair is found")


func test_every_suite_under_core_or_render_naming_ui_is_listed_and_every_listed_one_still_does() -> void:
    var suites := _suites_under(["core", "render"])
    var found := _suites_naming_ui(suites, _read_all(suites), _ui_classes_outside_the_door())
    var unlisted: Array[String] = []
    for suite: String in found:
        if not SUITES_NAMING_UI.has(suite):
            unlisted.append(suite)
    assert_true(
        unlisted.is_empty(),
        (
            "A suite under core or render names ui and SUITES_NAMING_UI does not say why,"
            + " move it beside what it tests: %s" % ", ".join(unlisted)
        )
    )
    var stale: Array[String] = []
    for suite: String in SUITES_NAMING_UI:
        if not found.has(suite):
            stale.append(suite)
    assert_true(stale.is_empty(), "A listed suite no longer names ui: %s" % ", ".join(stale))


func test_a_planted_core_suite_preloading_ui_is_found() -> void:
    var suites: Array[String] = ["core/scratch/tests/test_scratch_d4.gd", "core/scratch/tests/test_scratch_d4_quiet.gd"]
    var contents := {
        "core/scratch/tests/test_scratch_d4.gd": 'const DOCKER := preload("res://ui/dockers/scratch_d4.gd")',
        "core/scratch/tests/test_scratch_d4_quiet.gd": '# once preloaded "res://ui/dockers/scratch_d4.gd"\nvar x := 1',
    }
    var found := _suites_naming_ui(suites, contents, {})
    assert_true(found.has("core/scratch/tests/test_scratch_d4.gd"), "the planted preload of ui is found")
    assert_false(found.has("core/scratch/tests/test_scratch_d4_quiet.gd"), "a path in a comment is prose, not a load")


func test_a_planted_core_suite_naming_a_ui_class_outside_the_door_is_found() -> void:
    var suites: Array[String] = [
        "core/scratch/tests/test_scratch_d7.gd",
        "core/scratch/tests/test_scratch_d7_door.gd",
        "core/scratch/tests/test_scratch_d7_prose.gd",
    ]
    var contents := {
        "core/scratch/tests/test_scratch_d7.gd": "var page := ScratchD7Page.new()",
        "core/scratch/tests/test_scratch_d7_door.gd": "var dialog := SaDialog.new()",
        "core/scratch/tests/test_scratch_d7_prose.gd": '## ScratchD7Page reads it\nvar said := "ScratchD7Page"',
    }
    var found := _suites_naming_ui(suites, contents, {"ScratchD7Page": "ui/settings/scratch_d7_page.gd"})
    assert_true(found.has("core/scratch/tests/test_scratch_d7.gd"), "the planted ui class is found")
    assert_false(found.has("core/scratch/tests/test_scratch_d7_door.gd"), "a class of the door is no question")
    assert_false(found.has("core/scratch/tests/test_scratch_d7_prose.gd"), "a name in a comment or a string is prose")
    assert_false(_ui_classes_outside_the_door().has("SaDialog"), "the dialog the filter API hands a module is the door's")
    assert_true(_ui_classes_outside_the_door().has("SaShortcutsPage"), "a settings page is outside it")


## The suites of *suites* whose code, comments taken out and strings kept,
## names a path under `res://ui/`, or whose code with strings taken out too
## names a class of *ui_classes*.
func _suites_naming_ui(suites: Array[String], contents: Dictionary, ui_classes: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var doc := RegEx.create_from_string("##.*$")
    for suite in suites:
        var text := String(contents.get(suite, ""))
        for line: String in text.split("\n"):
            if line.strip_edges().begins_with("#"):
                continue
            if doc.sub(line, "").contains("res://ui/"):
                out[suite] = true
                break
        if out.has(suite):
            continue
        var code := _code(text)
        for name: String in ui_classes:
            if _names(code, name):
                out[suite] = true
                break
    return out


## Every class and autoload declared under `ui` outside the door, to its file.
func _ui_classes_outside_the_door() -> Dictionary:
    var out: Dictionary = {}
    var every := _class_and_autoload_map(_files_under(["ui"]))
    for name: String in every:
        var file: String = every[name]
        if file.begins_with("ui/") and not _in_door(file):
            out[name] = file
    return out


## Every suite in a `tests` folder under *roots*.
func _suites_under(roots: Array[String]) -> Array[String]:
    var out: Array[String] = []
    var every: Array[String] = []
    for root in roots:
        _walk("res://" + root, root + "/", every, true)
    every.sort()
    for path in every:
        if path.get_base_dir().get_file() == "tests":
            out.append(path)
    return out


## The shared engine both scans and both planted tests run through.
## `upward_only` true is the layer scan, false is the door scan.
func _pairs(files: Array[String], contents: Dictionary, name_to_file: Dictionary, upward_only: bool) -> Dictionary:
    var out: Dictionary = {}
    for referrer in files:
        var code := _code(contents.get(referrer, ""))
        var from_layer: String = referrer.get_slice("/", 0)
        for name: String in name_to_file:
            var target: String = name_to_file[name]
            if target == referrer:
                continue
            if upward_only:
                var to_layer: String = target.get_slice("/", 0)
                if not _is_upward(from_layer, to_layer):
                    continue
            elif _in_door(target):
                continue
            if _names(code, name):
                out["%s -> %s" % [referrer, target]] = true
    return out


func _is_upward(from_layer: String, to_layer: String) -> bool:
    if from_layer == NOT_CHECKED_FROM and NOT_CHECKED_TO.has(to_layer):
        return false
    return LAYER_RANK[from_layer] < LAYER_RANK[to_layer]


func _in_door(target: String) -> bool:
    if DOOR_BY_NAME.has(target):
        return true
    for prefix in DOOR_PREFIXES:
        if target.begins_with(prefix):
            return true
    return false


func _names(code: String, name: String) -> bool:
    var whole := RegEx.create_from_string("\\b%s\\b" % name)
    return whole.search(code) != null


func _class_and_autoload_map(files: Array[String]) -> Dictionary:
    var out: Dictionary = {}
    var declared := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
    for path in files:
        var found := declared.search(_read(path))
        if found != null:
            out[found.get_string(1)] = path
    var autoload := RegEx.create_from_string('(?m)^(\\w+)="\\*res://(.+)"$')
    for found in autoload.search_all(_read("project.godot")):
        var autoload_name := found.get_string(1)
        if not out.has(autoload_name):
            out[autoload_name] = found.get_string(2)
    return out


func _read_all(files: Array[String]) -> Dictionary:
    var out: Dictionary = {}
    for path in files:
        out[path] = _read(path)
    return out


## The file with comments and string contents removed, so a class name in a
## doc comment or a log message is prose about it and never a reference.
func _code(text: String) -> String:
    var kept: Array[String] = []
    var doc := RegEx.create_from_string("##.*$")
    var trailing := RegEx.create_from_string("\\s#.*$")
    for line in text.split("\n"):
        if line.strip_edges().begins_with("#"):
            continue
        kept.append(trailing.sub(doc.sub(line, ""), ""))
    var code := "\n".join(kept)
    code = RegEx.create_from_string('(?s)""".*?"""').sub(code, '""""""', true)
    code = RegEx.create_from_string('"(?:\\\\.|[^"\\\\\n])*"').sub(code, '""', true)
    code = RegEx.create_from_string("'(?:\\\\.|[^'\\\\\n])*'").sub(code, "''", true)
    return code


func _files_under(roots: Array[String]) -> Array[String]:
    var out: Array[String] = []
    for root in roots:
        _walk("res://" + root, root + "/", out)
    out.sort()
    return out


## Every script under *dir_path*, into a `tests` folder only when *with_suites*.
func _walk(dir_path: String, prefix: String, out: Array[String], with_suites: bool = false) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry) and (with_suites or entry != "tests"):
                _walk(dir_path.path_join(entry), prefix + entry + "/", out, with_suites)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


func _read(relative: String) -> String:
    var file := FileAccess.open("res://" + relative, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
