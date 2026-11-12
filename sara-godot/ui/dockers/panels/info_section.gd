## One section of the Info docker, a bold title over its rows, and the code that
## fills those rows from a canvas and the tool machine it paints with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row fillers live here rather than in `info_docker.gd`, because a placed
## section reads what the docker would read, and keeps reading it when Info
## itself is closed. The docker's own eight
## sections and a section placed in another docker are both of this class and
## filled by the same functions, so the two cannot say different things. The
## docker ticks its eight together while it is shown, and a placed one is a
## [SaInfoSection.View], which ticks its own while the view is shown, whether
## Info is open or not.
##
## Every row exists from the first frame and only its text changes, because
## this ticks ten times a second and building `Label`s at that rate is node
## churn for numbers nobody is reading between two of them. A row with nothing
## to say hides instead.
class_name SaInfoSection
extends VBoxContainer

## The row of the recent composite mean, named for how many composites it spans,
## which is `SaEasel.RECENT_COMPOSITES` and a suite holds the two together.
const RECENT_MEAN: String = "Mean of 60"

## Logical width one section asks for, and the reason every value is kept
## short: a row wider than this makes its whole section wider, and two sections
## that no longer fit side by side fall back to one column. Two of these plus
## the flow separation and the margins is what the docker's default size holds.
const SECTION_WIDTH: int = 216

## Row text as a fraction of the theme's size, through the meta the theme pass
## reads. This is a panel of numbers read at a glance rather than prose, and at
## the full size six sections in two columns wanted a docker three quarters of
## a 1080 screen tall.
const ROW_FONT_SCALE := 0.65

## How often a section is filled again while it is shown, in seconds: ten times
## a second, for the docker's sections and a placed one alike.
const TICK := 0.1

## The section's name, "Active layer", which is its layout element as well.

## The words a row is shown under where its key is a measure's name rather than
## a painter's word. The key stays, because it is what `section_report` hands a
## dump and what `sara_replay.py` and the suites read, so a new label costs no
## reader.
const ROW_TITLES := {
    "VRAM": "GPU memory, budget used",
    "VRAM all": "All documents, budget used",
    "Declared": "Tagged",
    "Transfer": "Tone curve",
    "FG value": "FG RGB",
    "FG stops": "FG stops over white",
    "BG value": "BG RGB",
    "BG stops": "BG stops over white",
}

var title: String = ""

## Row key -> [name `Label`, value `Label`], in the order they are drawn.
var rows: Dictionary = {}

## The frame rate's graph, under the FPS row, in the GPU section alone.
var fps_graph: SaInfoFpsGraph

## Times the FPS row's text was replaced, so a suite reads that a write of the
## text the row already shows touched nothing and so asked for no frame.
var fps_row_writes: int = 0

## The Preferences category whose switch for this section also hides it: the
## Info docker's for its own sections, and empty for a placed one, which the
## docker holding it shows and hides.
var _switches: String = ""

## The GPU counters as of the previous fill, so what is shown is the difference.
var _gpu_before: Dictionary = {}

## The Document section's Name row, written when its signals say and not here.
var _name_row: SaDocumentLabel = null


## A section titled *section* with a row for each of *keys*, hidden by
## *switches*' switch for it when that is not empty. A Build section writes its
## rows here, because nothing about a running build changes.
func _init(section: String, keys: Array, switches: String = "") -> void:
    title = section
    _switches = switches
    name = section.to_pascal_case()
    set_meta(SaMake.KIND_META, SaMake.Kind.COLUMN)
    custom_minimum_size = Vector2(float(SaUI.px(SECTION_WIDTH)), 0.0)

    SaSettingsRows.embolden(SaMake.label(self, "Title", tr(section)))

    var grid := SaMake.grid(self, "Rows", 2)
    # Set on the grid rather than on each label: the theme pass carries the
    # fraction down to every child, so the title above stays full size.
    grid.set_meta(SaUI.FONT_SCALE_META, ROW_FONT_SCALE)

    for key: String in keys:
        var name_label := SaMake.label(grid, "%sName" % key.to_pascal_case(), tr(ROW_TITLES.get(key, key)))
        SaTheme.bind_font(name_label, "text_muted")

        var value_label := SaMake.label(grid, "%sValue" % key.to_pascal_case())
        value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

        rows[key] = [name_label, value_label]
    # The graph of the FPS row, which is the section's last row so the graph
    # sits under it.
    if section == "GPU":
        fps_graph = SaInfoFpsGraph.new()
        add_child(fps_graph)
    if section == "Build":
        _build_rows(SaBuildInfo.read())


## A view of *section* another docker holds, with a row for each of *keys*,
## filled from the canvas and the tool machine *sources* answers as a pair.
static func view(section: String, keys: Array, sources: Callable) -> View:
    return View.new(section, keys, sources)


## Fills the rows from *canvas*'s document and *machine*, the rows of this
## section and no other. Nothing is written until both are there, as at home.
func fill(canvas: SaCanvas, machine: ToolMachine) -> void:
    if canvas == null or machine == null:
        return
    var doc := canvas.document
    if doc == null:
        return
    match title:
        "Document":
            _document_rows(doc)
        "Colour space":
            _colour_rows(doc.color_space)
        "Active layer":
            # The registry the compositor resolves the layer's mode through,
            # which is the one every blend dropdown is bound to at boot.
            var compositor := canvas.compositor
            _active_layer_rows(doc.active_layer, compositor.registry if compositor != null else null, doc.color_space)
        "Selected colours":
            _selected_colour_rows()
        "Input":
            _input_rows(machine)
        "History":
            _history_rows(doc)
        "GPU":
            _gpu_rows(canvas.easel)


## Sets one row's value, or hides the row when *text* is empty.
func _set_row(key: String, text: String) -> void:
    var row: Array = rows.get(key, [])
    if row.is_empty():
        return
    var shown := not text.is_empty()
    (row[0] as Label).visible = shown
    (row[1] as Label).visible = shown
    (row[1] as Label).text = text


## Shows the section when it has something to say, unless the painter hid it.
##
## The layout switch has to be read here as well as in the docker's
## `apply_layout_settings`, because this runs from the tick ten times a second
## and whatever it writes last is what stands. Without the second half, History,
## Colour space and Active layer each came back a tenth of a second after being
## switched off, and the three sections with no content condition, GPU and
## Selected colours among them, obeyed the same switch: the toggle looked broken
## on three rows out of seven and correct on the rest.
func _show(shown: bool) -> void:
    visible = shown and (_switches.is_empty() or SaSettings.get_element_visible(_switches, title))


## One frame of the FPS row and graph, with the clock, the drawn-frame count and
## the rest passed in so a suite can drive it.
##
## At rest the row reads the word, so it is written once, in the tick the rest
## began, and never asks for a frame of its own after. A text equal to the one
## shown is not set at all, which leaves the label with nothing to redraw.
func follow_frame(now_usec: int, frames_drawn: int, resting: bool) -> void:
    if fps_graph == null:
        return
    if not fps_graph.tick(now_usec, frames_drawn, resting):
        return
    var text := fps_graph.fps_text()
    var row: Array = rows.get("FPS", [])
    if not row.is_empty() and (row[1] as Label).text == text:
        return
    fps_row_writes += 1
    _set_row("FPS", text)


## The three facts of the banner's Build line, as rows, from the same reader
## the banner and the About dialog use so the three cannot name three builds.
##
## The commit carries the provenance the banner spells out in words, because a
## commit named by an exported binary and one read off a working tree with
## edits in it are different claims: an editor run says so after the hash, and
## an export made on a dirty tree says so too. The Built row is the export's
## date and hides for a run that was never exported, because "not exported" is
## already what the Commit row says and a row saying it twice is a row of
## nothing. The date goes through the reader's own formatter rather than a
## second copy of it here, so the banner and the docker print one date.
func _build_rows(info: Dictionary) -> void:
    _set_row("Version", str(info.get("version", "")))
    var commit := str(info.get("commit", SaBuildInfo.UNKNOWN_COMMIT))
    var built := ""
    match str(info.get("source", SaBuildInfo.SOURCE_UNKNOWN)):
        SaBuildInfo.SOURCE_EXPORT:
            if bool(info.get("dirty", false)):
                commit += ", " + tr("development build")
            built = SaBuildInfo.built_for_humans(str(info.get("built", "")))
        SaBuildInfo.SOURCE_WORKING_TREE:
            commit += ", " + tr("development build")
    _set_row("Commit", commit)
    _set_row("Built", built)


## The pressure of whatever tool is active when its descriptor says it reads
## one, empty otherwise, rather than the brush's alone asked by id, which
## would show a module's pen an empty row and "no brush". The device
## is the pointer policy's and needs no tool.
func _input_rows(machine: ToolMachine) -> void:
    var active := machine.active_tool
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    var reads: bool = active != null and descriptor != null and descriptor.reads_pressure
    _set_row("Pressure", "%.2f" % active.last_pressure if reads else "")
    _set_row("Device", tr("Tablet") if SaCursorPolicy.pointer_is_tablet else tr("Mouse"))
    _set_row("Tool", machine.active_tool_name.capitalize())


## What a texel of this document is, as both rows that report it read it.
##
## One function rather than the expression written twice, because the whole
## point of the Document row is that it agrees with the Colour space row, and
## two copies of a ternary is how they stop agreeing.
static func depth_text(space: SaColorSpace) -> String:
    if space == null:
        return ""
    return "F16" if space.depth == SaColorSpace.Depth.F16 else "F32"


## What a layer's chunks hold in VRAM. Each chunk is asked its own edge, because
## a half-resolution chunk is a quarter of a full one, and only the fields it
## has are counted, because a lazy field costs nothing until it is painted.
## Counting every chunk at 256 and every field of the schema would overstate
## both.
static func layer_vram_bytes(layer: SaLayer) -> float:
    var total := 0.0
    for chunk: SaChunk in layer.chunks.values():
        if chunk == null:
            continue
        var texels := float(chunk.pixel_size() * chunk.pixel_size())
        for spec: SaFieldSpec in layer.schema:
            if chunk.has_field(spec.id):
                total += texels * float(spec.bytes_per_texel())
    return total


func _document_rows(doc: SaDocument) -> void:
    # Summed per layer over its own schema rather than assuming 16 bytes a
    # texel. A literal reports the wrong number the moment a document is
    # anything but RGBA32F, and BYTES_PER_TEXEL is the only place allowed to
    # know a size.
    var allocated_chunks := 0
    var vram_bytes := 0.0
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        allocated_chunks += layer.chunks.size()
        vram_bytes += layer_vram_bytes(layer)

    _follow_name(doc)
    _set_row("Size", tr_n("%d x %d", "%d x %d", doc.canvas_size.y) % [doc.canvas_size.x, doc.canvas_size.y])
    # The depth belongs beside the VRAM row it halves, not only three sections
    # further down under Colour space, which is the block a painter opens to
    # read a gamut rather than to work out why the canvas costs 20 MB.
    _set_row("Depth", depth_text(doc.color_space))
    # The storage size sits next to the pixel size it is read against, with the
    # depth between them as the factor that turns one into the other, ahead
    # of Layers and Chunks, which are counts a painter reads to explain the
    # number rather than on the way to it.
    var mb := tr("%.1f MB")
    _set_row("VRAM", _with_budget_share("VRAM", mb % (vram_bytes / 1048576.0), SaMemoryBudget.document_bytes(doc)))
    # What the layers hold is not what Sara holds. Undo history is chunk
    # textures that no layer schema lists, and it is the larger of the two.
    var all_shown := mb % (float(SaTexture.allocated_bytes) / 1048576.0)
    _set_row("VRAM all", _with_budget_share("VRAM all", all_shown, _open_documents_bytes(doc)))
    _set_row("Layers", str(doc.get_child_count()))
    _set_row("Tiles", str(allocated_chunks))
    # The mode is announced in the corner as it is entered, and here for anyone
    # who missed the message and has the docker open.
    _set_row("Focus mode", SaFocusMode.status_text())


## *shown*, the figure of the GPU memory row *key*, and the share of the GPU
## memory budget *bytes* takes: the document's layers and history on the first row,
## every open document's on the second. Bare when the card's memory is not
## known and there is no budget.
func _with_budget_share(key: String, shown: String, bytes: int) -> String:
    var budget := SaMemoryBudget.budget()
    var value := rows.get(key, []) as Array
    if not value.is_empty():
        (value[1] as Label).tooltip_text = budget_tip(bytes, budget)
    if budget <= 0:
        return shown
    # Only the per cent, because the section stands beside Colour space at the
    # docker's shipped width and "of budget" after it pushed the section onto
    # a line of its own. The tooltip and the Preferences row name the budget.
    return TranslationServer.translate("%s, %s") % [shown, _percent(bytes, budget)]


## How much of the GPU memory budget *documents*' open documents use, or *doc* alone
## in a scene without main's list.
func _open_documents_bytes(doc: SaDocument) -> int:
    var scene := get_tree().current_scene if is_inside_tree() else null
    var documents := scene.get(&"documents") as SaDocuments if scene != null else null
    return SaMemoryBudget.used(documents) if documents != null else SaMemoryBudget.document_bytes(doc)


## The sentence a GPU memory row's value explains its per cent with: *bytes*
## of the *budget*, and where the budget is set.
static func budget_tip(bytes: int, budget: int) -> String:
    if budget <= 0:
        return ""
    var said := TranslationServer.translate(
        "%s of the %s budget Sara keeps to on the graphics card, set in Preferences > Performance."
    )
    return said % [SaCardMemory.size_words(bytes), SaCardMemory.size_words(budget)]


## *part* of *whole* in per cent, to a tenth under ten and whole above it.
static func _percent(part: int, whole: int) -> String:
    var share := 100.0 * float(part) / float(whole)
    return (TranslationServer.translate("%.1f%%") if share < 10.0 else TranslationServer.translate("%.0f%%")) % share


## Listens to *doc* and main's autosave for the Name row, once per pair: a
## fill only notices a new document, or the autosave main starts after it.
func _follow_name(doc: SaDocument) -> void:
    var scene := get_tree().current_scene if is_inside_tree() else null
    var autosave := scene.get_node_or_null(^"SaAutosave") if scene != null else null
    var copies := Signal(autosave, &"saved") if autosave != null else Signal()
    if _name_row != null and _name_row.document == doc and _name_row.copies == copies:
        return
    _name_row = SaDocumentLabel.new(doc, copies)
    _name_row.changed.connect(_on_name)
    _on_name(_name_row.text)


func _on_name(text: String) -> void:
    _set_row("Name", text)


## Steps and what they cost, because the step count on its own was the number
## that hid a couple of hundred megabytes.
func _history_rows(doc: SaDocument) -> void:
    var known: bool = doc.undo_redo != null and doc.history != null
    _show(known)
    if not known:
        return
    _set_row("Steps", str(doc.undo_redo.get_history_count()))
    _set_row("Paint", tr("%.1f / %.0f MB") % [doc.history.total_bytes() / 1048576.0, doc.history.effective_budget() / 1048576.0])
    _set_row(
        "Layer pool",
        tr("%.1f / %.0f MB") % [doc.history.total_layer_bytes() / 1048576.0, doc.history.layer_budget_bytes / 1048576.0]
    )
    # What a whole-canvas step costs on this document and how many the depth in
    # Preferences buys, because "480 MB" on its own does not say whether the
    # next gradient is the one that takes the way back to a flat canvas.
    var largest: int = doc.history.largest_step_bytes
    # Integer division on purpose: the answer is how many whole steps fit, and
    # half a gradient is not a step the painter can undo back through.
    @warning_ignore("integer_division")
    var room: int = doc.history.effective_budget() / largest if largest > 0 else 0
    _set_row(
        "Widest step",
        tr_n("%.1f MB, room for %d", "%.1f MB, room for %d", room) % [largest / 1048576.0, room] if largest > 0 else ""
    )
    # Steps eviction has taken. Zero until the budget bites, and the number the
    # painter has no other way to see.
    _set_row("Dropped", str(doc.history.dropped_steps))


## What the GPU was actually asked to do since the last tick, which is the
## measurement the specialisation-constant and caching work is graded against. Uniform sets sitting level
## with dispatches is the caching doing nothing, and lists level with
## dispatches is one full barrier per dispatch.
func _gpu_rows(easel: SaEasel) -> void:
    var gpu := SaCompute.counters()
    _set_row("Dispatches", str(gpu["dispatches"] - int(_gpu_before.get("dispatches", 0))))
    _set_row("Lists", str(gpu["lists"] - int(_gpu_before.get("lists", 0))))
    _set_row("Uniform sets", str(gpu["uniform_sets"] - int(_gpu_before.get("uniform_sets", 0))))
    _set_row("Workgroups", str(gpu["workgroups"] - int(_gpu_before.get("workgroups", 0))))
    _set_row("Session", str(gpu["dispatches"]))
    _gpu_before = gpu

    # CPU time to issue one composite, which is the half of stroke latency that
    # can be measured without stalling on the GPU. The mean spans the easel's
    # recent composites rather than the session, and both figures are
    # microseconds written as such, because a bare number of microseconds is
    # easily read as milliseconds.
    var measured: bool = easel != null and not easel.composite_usec_recent.is_empty()
    _set_row("Composite", microseconds(easel.composite_usec_last) if measured else "")
    var mean := 0
    if measured:
        mean = roundi(float(easel.composite_usec_recent_total) / easel.composite_usec_recent.size())
    _set_row(RECENT_MEAN, microseconds(mean) if measured else "")


## A CPU cost as the Info docker shows it: whole microseconds with the unit
## written out, never a fraction of a millisecond a reader can take for a
## whole one.
static func microseconds(usec: int) -> String:
    return "%d microseconds" % usec


## What the document's numbers mean, which is otherwise invisible anywhere in
## the UI: the same pixel values are a different colour in each of these
## spaces.
##
## "unspecified" is shown as such rather than as sRGB. A file written before
## the descriptor existed carries no colour space, and "the file did not say"
## differs from "the file said sRGB" the moment anything offers to convert it.
func _colour_rows(space: SaColorSpace) -> void:
    _show(space != null)
    if space == null:
        return
    _set_row("Space", SaColorSpace.display_name(space.id))
    # The three primary rows are what the gamut *is* and say nothing about what
    # it is called, and the space id is not the answer either. "Oklab over
    # Display P3" is one space id over two different gamuts as the preset is
    # written, and a document that arrived tagged Adobe RGB has no id at all.
    _set_row("Gamut", SaColorNames.gamut_name(space.primaries))
    # "the file did not say" differs from "the file said sRGB" the moment
    # anything offers to convert it, so the row appears only when it is news.
    _set_row("Declared", "" if space.is_specified else tr("no"))
    _set_row("Transfer", space.transfer.display_name)
    _set_row("Depth", depth_text(space))
    # The name in front and the numbers behind it, because the pair is what a
    # painter checks a file against and the name alone cannot be checked. The
    # Colour Spaces page prints the same call, so the two cannot disagree.
    _set_row("White", SaColorNames.white_point_text(space.white))
    var has_primaries := space.primaries.size() >= 3
    _set_row("Red", "%.3f, %.3f" % [space.primaries[0].x, space.primaries[0].y] if has_primaries else "")
    _set_row("Green", "%.3f, %.3f" % [space.primaries[1].x, space.primaries[1].y] if has_primaries else "")
    _set_row("Blue", "%.3f, %.3f" % [space.primaries[2].x, space.primaries[2].y] if has_primaries else "")


## The pair a painter is working with, which is otherwise only readable as two
## squares in the title bar and the picker.
##
## Both forms of each colour, because neither is enough on its own. The hex is
## what a painter names a colour by and what goes into the picker's own box, and
## `to_html` clamps, so an out-of-range value reads as `ffffff` there and is
## itself in the value row beside it. Hard rule 5 is the reason a colour can be
## out of range at all, and this panel is where that is visible.
##
## Alpha is a row only when it is not full, because a pair at alpha 1 is every
## pair until somebody changes one, and two rows saying 100% every tick are two
## rows of nothing. The stops row follows the same rule for the same reason: a
## colour that is not above 1.0 has no stops above 1.0 to report.
func _selected_colour_rows() -> void:
    var fore := SaColors.foreground
    var back := SaColors.background
    _set_row("Foreground", "#%s" % fore.to_html(false))
    _set_row("FG value", "%.3f, %.3f, %.3f" % [fore.r, fore.g, fore.b])
    _set_row("FG stops", stops_text(fore))
    _set_row("FG alpha", "" if is_equal_approx(fore.a, 1.0) else "%d%%" % roundi(fore.a * 100.0))
    _set_row("Background", "#%s" % back.to_html(false))
    _set_row("BG value", "%.3f, %.3f, %.3f" % [back.r, back.g, back.b])
    _set_row("BG stops", stops_text(back))
    _set_row("BG alpha", "" if is_equal_approx(back.a, 1.0) else "%d%%" % roundi(back.a * 100.0))


## How far *color* reaches above the display's white, in stops, or 0.0 when it
## does not reach above it at all.
##
## The row is for "exposure or HDR values", which is two things: the view's
## own exposure slider, which scales the picture and never a pixel, and the
## magnitude a stored colour actually has. This row is the second. The value row
## beside it already prints the three channels, and three floats are not a thing
## a headroom is read off, so the one number here answers "how far over is
## this": doubling is one stop, so 8.0 is three.
##
## The brightest channel, because that is the one that clips, and because a
## per-channel figure would be three more rows saying what the value row says.
static func stops_above_white(color: Color) -> float:
    var peak := maxf(color.r, maxf(color.g, color.b))
    return log(peak) / log(2.0) if peak > 1.0 else 0.0


## The stops row's text, empty when there are none, so `_set_row` hides the row.
static func stops_text(color: Color) -> String:
    var stops := stops_above_white(color)
    return "" if stops <= 0.0 else "+%.2f" % stops


## What the Blend row says for *mode_id*: the label the blend dropdown shows for
## the same mode in a document of *space*, so the two cannot disagree.
##
## The label rather than the registry id capitalised, which would read a
## module's own prefix into the name where the dropdown reads the name the
## module gave, and a built-in whose id is not its name as the id, "Normal
## Srgb" for sRGB Normal, with no bracket naming the space it mixes in.
##
## The name goes through the catalogue as `BlendModeButton.shown_label` puts
## it, and what `label_for` writes after it stays as written, so the row and
## the dropdown read the same words in every language. An id no registry
## holds, a layer from a module that is not installed, keeps the capitalised
## id, because no dropdown has a label for it to agree with.
static func blend_text(mode_id: StringName, registry: SaBlendModeRegistry, space: SaColorSpace) -> String:
    if registry == null or not registry.has(mode_id):
        return String(mode_id).capitalize()
    var descriptor := registry.get_descriptor(mode_id)
    var english := descriptor.label_for(space)
    var translated := String(TranslationServer.translate(descriptor.display_name))
    return translated + english.trim_prefix(descriptor.display_name)


func _active_layer_rows(active: SaLayer, registry: SaBlendModeRegistry, space: SaColorSpace) -> void:
    _show(active != null)
    if active == null:
        return
    _set_row("Name", str(active.name))
    _set_row("Blend", blend_text(active.get_blend_mode_name(), registry, space))
    _set_row("Opacity", "%d%%" % roundi(active.opacity * 100.0))
    _set_row("Locked", tr("paint") if active.is_locked else (tr("alpha") if active.alpha_locked else tr("no")))


## A section placed in another docker: one [SaInfoSection] that fills itself
## ten times a second while the view is in sight, from the canvas and the tool
## machine its source answers, whether the Info docker is open or not.
##
## The view holds the section rather than being it, because a section with
## nothing to say hides itself, the Active layer with no layer active, and a
## view hidden that way would be out of sight and never tick again to come
## back. A GPU view feeds its graph every frame while it is in sight, as the
## docker does its own.
class View:
    extends VBoxContainer

    ## The section this view shows, built and filled as the docker's own is.
    var section: SaInfoSection

    ## The ticker, running while the view is in sight and stopped otherwise.
    var ticker: Timer

    ## Answers [canvas, tool machine] to fill from, or an empty array when
    ## there is nothing to read.
    var _sources: Callable

    func _init(title: String, keys: Array, sources: Callable) -> void:
        name = "%sView" % title.to_pascal_case()
        _sources = sources
        section = SaInfoSection.new(title, keys)
        add_child(section)
        ticker = Timer.new()
        ticker.name = "UpdateTimer"
        ticker.wait_time = TICK
        ticker.timeout.connect(refresh)
        add_child(ticker)
        set_process(false)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_READY or what == NOTIFICATION_VISIBILITY_CHANGED:
            follow_sight()

    func _process(_delta: float) -> void:
        section.follow_frame(Time.get_ticks_usec(), Engine.get_frames_drawn(), OS.low_processor_usage_mode)

    ## Fills the section once from what the source answers.
    func refresh() -> void:
        var pair: Array = _sources.call() if _sources.is_valid() else []
        if pair.size() < 2 or not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
            return
        section.fill(pair[0] as SaCanvas, pair[1] as ToolMachine)

    ## Starts the ticker and fills the rows at once when the view comes into
    ## sight, so a placed section is never an empty box for a tenth of a
    ## second, and stops it when the view leaves sight.
    func follow_sight() -> void:
        var shown := is_visible_in_tree()
        set_process(shown and section.fps_graph != null)
        if not ticker.is_inside_tree():
            return
        if not shown:
            ticker.stop()
            return
        if ticker.is_stopped():
            ticker.start()
            refresh()
