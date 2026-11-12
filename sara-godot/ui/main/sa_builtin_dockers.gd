## The dockers Sara ships, the list they register from: each one's id, title,
## window, chord and the sentence its Window menu row says on hover.
##
## Its own class because it owns something `MainDockers` does not: that node
## runs whatever dockers are registered, a module's as well, and this is which
## ones the skeleton brings, each with the sentence its row says. `SaDockerIds`
## names the ids, and `test_every_built_in_docker_has_a_constant.gd` holds
## the two lists to each other.
class_name SaBuiltinDockers
extends RefCounted

## What each docker holds, which its row in the Window menu says on hover. A
## table by id rather than a fifth column of the list in [method register],
## whose rows would each have run past a line.
const SENTENCES := {
    SaDockerIds.TOOLBOX: "Every tool, one press each, grouped by what it does.",
    SaDockerIds.LAYERS: "The painting's layers, with their order, visibility, blend and opacity.",
    SaDockerIds.COLOR: "The wheel and the sliders that set the brush's colour, and the two swatches.",
    SaDockerIds.INFO: "The build, the document, its colour space and layer, and what the pen and the GPU are doing.",
    SaDockerIds.RECORDER: "Records the painting as a timelapse and hands the frames to ffmpeg.",
    SaDockerIds.MINIMAP: "The whole painting small, with the part in view drawn over it. A click takes the view there.",
    SaDockerIds.TOOL_OPTIONS: "The settings of the tool in the hand that the bar has no room for.",
    SaDockerIds.GRAPH: "A live scope over the picture: a waveform, a histogram, a parade or a vectorscope.",
    SaDockerIds.HISTORY: "The brush presets loaded last, most recent first, to load one again.",
    SaDockerIds.UNDO: "Every step the document can go back to, with the one it stands on marked.",
    SaDockerIds.REFERENCE: "A board of pictures to paint from beside the canvas, and a click that samples one.",
    SaDockerIds.BRUSH_PRESETS: "Every brush preset, by tag. A press puts that brush in the hand.",
    SaDockerIds.PALETTE: "The ten brush slots on a ring round the colour wheel, summoned under the pointer by its shortcut.",
    SaDockerIds.FILTERS: "Every filter a module registered, with a search, what each does to the layer, and Open.",
}


## The skeleton's own dockers go through the same door a module uses, so a
## registered docker cannot be second-class: one list feeds the Window menu,
## the layout store and the shortcut router alike. The ids are the
## docker_layout.cfg keys, so a title can be translated or renamed without
## touching anyone's saved geometry.
##
## Each registration builds its window on the registry's `changed`, too long
## for all of them in one frame. Given *slice_usec*, the call stops once that long
## has gone by and answers false, so the boot can build the rest a frame later.
## One is registered whatever the slice, so a call always
## moves on. True once every built-in is registered.
static func register(ui: SaUIRegistry, slice_usec: int = 0) -> bool:
    var began := Time.get_ticks_usec()
    var registered := 0
    var toolbox_factory := func() -> Window: return preload("res://ui/dockers/toolbox/toolbox_docker.gd").new()
    var layers_factory := func() -> Window: return preload("res://ui/dockers/layers/layers_docker.gd").new()
    var color_factory := func() -> Window: return preload("res://ui/dockers/color/color_docker.gd").new()
    var info_factory := func() -> Window: return preload("res://ui/dockers/panels/info_docker.gd").new()
    var recorder_factory := func() -> Window: return preload("res://ui/dockers/recorder/recorder_docker.gd").new()
    var minimap_factory := func() -> Window: return preload("res://ui/dockers/minimap/minimap_docker.gd").new()
    var tool_options_factory := func() -> Window: return preload("res://ui/dockers/tool_options/tool_options_docker.gd").new()
    var graph_factory := func() -> Window: return preload("res://ui/dockers/graph/graph_docker.gd").new()
    var history_factory := func() -> Window: return preload("res://ui/dockers/presets/history_docker.gd").new()
    var undo_factory := func() -> Window: return preload("res://ui/dockers/panels/undo_docker.gd").new()
    var reference_factory := func() -> Window: return preload("res://ui/dockers/reference/reference_docker.gd").new()
    var presets_factory := func() -> Window: return preload("res://ui/dockers/presets/brush_presets_docker.gd").new()
    var palette_factory := func() -> Window: return preload("res://ui/dockers/palette/palette_docker.gd").new()
    var filters_factory := func() -> Window: return preload("res://ui/dockers/filters/filters_docker.gd").new()
    var builtins: Array = [
        [SaDockerIds.TOOLBOX, "Toolbox", toolbox_factory, &"docker_toolbox"],
        [SaDockerIds.LAYERS, "Layers", layers_factory, &"docker_layers"],
        [SaDockerIds.COLOR, "Colour Picker", color_factory, &"docker_color_selector"],
        [SaDockerIds.INFO, "Info", info_factory, &"info_docker"],
        [SaDockerIds.RECORDER, "Recorder", recorder_factory, &"docker_recorder"],
        [SaDockerIds.MINIMAP, "Minimap", minimap_factory, &"docker_minimap"],
        [SaDockerIds.TOOL_OPTIONS, "Tool Options", tool_options_factory, &"docker_tool_options"],
        [SaDockerIds.GRAPH, "Graph", graph_factory, &"docker_graph"],
        # "Recent Presets" rather than "History", which is the undo stack
        # everywhere else in Sara and is not this. The id stays, being a key
        # `docker_layout.cfg` already files a painter's window under.
        [SaDockerIds.HISTORY, "Recent Presets", history_factory, &"docker_history"],
        # The undo stack's own window, which is what a painter opening the menu
        # looks for. It sits beside the preset trail, and the two are the only
        # lists of what has happened.
        [SaDockerIds.UNDO, "Undo History", undo_factory, &"docker_undo"],
        [SaDockerIds.REFERENCE, "Reference", reference_factory, &"docker_reference"],
        [SaDockerIds.BRUSH_PRESETS, "Brush Presets", presets_factory, &"docker_brush_presets"],
        # The pop-up palette, a docker like the rest and off until Preferences
        # turns it on. Its summon is the way it is meant to appear, and the
        # Window menu still lists it, since a registration that hid itself would
        # be a second rule for one docker.
        [SaDockerIds.PALETTE, "Pop-up Palette", palette_factory, &"docker_palette"],
        # The filter browser. No chord of its own: Filter > Browse Filters...
        # is its summon, and the Window menu's row summons it locked and wide.
        [SaDockerIds.FILTERS, "Filters", filters_factory, &""],
    ]
    for entry: Array in builtins:
        if ui.has_docker(entry[0]):
            continue
        if slice_usec > 0 and registered > 0 and Time.get_ticks_usec() - began >= slice_usec:
            return false
        # Translated here only so the template reads every sentence, the
        # Window menu translates the registered one again as it shows it.
        var sentence := TranslationServer.translate(SENTENCES.get(entry[0], ""))
        ui.register_docker(entry[0], entry[1], entry[2], entry[3], &"", sentence)
        registered += 1
    # The painter's composed dockers, after the built-ins so they list after them.
    return SaComposedDockers.register(ui)
