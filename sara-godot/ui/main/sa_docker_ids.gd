## The ids the skeleton's own dockers register under, one constant each.
##
## An id is the key the registry, the Window menu and `docker_layout.cfg` file a
## docker under, and the name its Window takes in the tree. Written as a string
## across `ui` and the harness, a renamed or mistyped one found nothing and said nothing,
## which a scenario reported as a docker that would not show. As a constant it
## is a parse error instead. `MainDockers.register_builtin_dockers` registers
## through these, and `ALL` is the list a suite holds the registration to.
##
## A docker a module registers keeps its own id in its own module: the harness
## finds it through the registry the same way, and nothing here names it.
class_name SaDockerIds
extends RefCounted

const TOOLBOX := &"ToolBoxDocker"
const LAYERS := &"LayersDocker"
const COLOR := &"ColorDocker"
const INFO := &"InfoDocker"
const RECORDER := &"RecorderDocker"
const MINIMAP := &"MinimapDocker"
const TOOL_OPTIONS := &"ToolOptionsDocker"
const GRAPH := &"GraphDocker"
## The recent presets, under the id the window had when it was called History.
const HISTORY := &"HistoryDocker"
const UNDO := &"UndoDocker"
const REFERENCE := &"ReferenceDocker"
const BRUSH_PRESETS := &"BrushPresetsDocker"
const PALETTE := &"PaletteDocker"
## The filter browser, a docker and the one place the filters are listed.
const FILTERS := &"FiltersDocker"

## Every built-in, in the order they register in.
const ALL: Array[StringName] = [
    TOOLBOX,
    LAYERS,
    COLOR,
    INFO,
    RECORDER,
    MINIMAP,
    TOOL_OPTIONS,
    GRAPH,
    HISTORY,
    UNDO,
    REFERENCE,
    BRUSH_PRESETS,
    PALETTE,
    FILTERS,
]


## The words a docker goes by in the locale in use, the one answer the Window
## menu's row asks, and the one a title bar's label agrees with. A label is
## handed the source string and translates it every time it is drawn, rather
## than translated words when it is built, which a locale applied afterwards
## finds no source string in to translate back: "Color Picker" on the bar and
## "Colour Picker" in the menu, which is built on every open. A caller that
## builds a row of words asks here.
static func display_name(title: String) -> String:
    return TranslationServer.translate(title)
