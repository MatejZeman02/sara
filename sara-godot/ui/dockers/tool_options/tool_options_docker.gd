## The Tool Options docker: every option the active tool declares, in a column,
## built from the same `SaOptionSpec` list the top bar builds from.
##
## The bar is one row, so a tool with many options overflowed it and a tool had
## no way to say an option was secondary. The answer: the docker shows every
## option, the bar shows the few a spec flags with `bar`. Neither surface knows
## anything about a particular tool, so a module tool that declares a spec
## appears in both without an edit here.
##
## Both surfaces own their own `ToolOptionControls`, and each follows the
## other's writes through `option_written`, because two controls for one option
## that disagree read as broken. The controls follow the machine's registry and
## the blend modes themselves, and the docker listens.
@tool
extends DockerWindow

class_name ToolOptionsDocker

const ToolOptionsFloor := preload("res://ui/dockers/tool_options/tool_options_floor.gd")
const ToolOptionsHeld := preload("res://ui/dockers/tool_options/tool_options_held.gd")
const ToolOptionsAfter := preload("res://ui/dockers/tool_options/tool_options_after.gd")

## What the docker opens at, matching its row in `docker_layout_default.cfg`.
## Tall enough for the brush's eleven options without a scroll at the default
## width, which is the fullest tool there is.
const DEFAULT_SIZE := Vector2i(300, 396)

## The label column's floor in logical pixels. Wide enough for "Opacity by
## Pressure" at the docker's font. A label takes its whole width whenever the
## row has it, and wraps onto a second line down to this when it does not, so
## "Saturation dynamics" reads whole at the default width and the row still
## fits the docker's floor.
const LABEL_WIDTH: int = 104

## The floor of a button whose text this docker writes, in logical pixels.
## Below its text's width the button cuts the text with an ellipsis and its
## tooltip carries the whole of it, so a row asks for its label column and
## this, not for "100%, no sensor" in full.
const VALUE_FLOOR: int = 24

## The narrowest a wrapped line of this docker is laid out, the narrowest row's
## width, so it widens nothing. A label wraps at the width it was last laid out
## at, and a docker hidden at boot lays out nothing: the engine held the foot
## line at its own minimum, one pixel, where it read one letter a row and asked
## the column for 1113 units. That was the column's floor when the default
## layout was fitted, and the fit put Tool Options over the bar to hold it.
const WRAP_FLOOR: int = LABEL_WIDTH + VALUE_FLOOR

## Row text as a fraction of the theme's size, through the meta the theme pass
## reads. The same treatment the Info docker's rows get, and for the same
## reason: a column of labelled controls at the full size wants a docker half
## a 1080 screen tall.
const ROW_FONT_SCALE := 0.8

## Which tool the size the window has now belongs to. Empty until the first
## `tool_changed`, so the size a restore put there is nobody's and is filed under
## nobody when the painter first switches away.
var _sized_for_tool: StringName = &""

## The layout store, once `_layout_store` has found it.
var _store: DockerLayoutStore = null

## Whether the opening height has been taken already. The grow is "a docker's
## first size, computed when it is first shown", and this docker asks for it
## from `sync_from_tool` because at `_ready` it has no rows to measure.
## `sync_from_tool` then runs again on every tool change, document open and
## registry change, so without this the grow was not a first size at all.
var _took_its_opening_height: bool = false

## The machine whose permanent tool the docker follows, set by Main the way the
## Info docker's is.
var target_tool_machine: ToolMachine:
    set(value):
        target_tool_machine = value
        _listen_to_the_tool()
        options.binding.follow(value)
        sync_from_tool()
    get:
        return target_tool_machine

## The bar, so the two surfaces follow each other's writes. Set by Main.
var peer_bar: ToolOptionsBar = null:
    set(value):
        if peer_bar != null and peer_bar.options.option_written.is_connected(_on_peer_written):
            peer_bar.options.option_written.disconnect(_on_peer_written)
        peer_bar = value
        if peer_bar != null:
            peer_bar.options.option_written.connect(_on_peer_written)
            options.option_written.connect(peer_bar.options.show_value)
            # And the bar's own controls that are not `options`', which is the
            # stabilizer quick toggle beside the symmetry three.
            options.option_written.connect(peer_bar.show_written_option)
    get:
        return peer_bar

var options: ToolOptionControls

## The strip above the rows holding the Advanced check.
var header: ToolOptionsHeader

var _rows_box: VBoxContainer

## The least height of the scroll the rows sit in, which is the docker's floor.
var _floor: ToolOptionsFloor

## What a held key shows on the rows, the selection tools' Shift and Alt.
var held: ToolOptionsHeld

## The rows a tool switch or a preset load leaves for the second frame after it.
var after := ToolOptionsAfter.new(2)

## An attached filter's panel, shown in place of the rows, or null.
var _filter_panel: Control = null
var _empty_label: Label

## The muted line at the docker's foot naming the rows the bar holds, which
## `sync_from_tool` leaves out. Under the scroll, so it never scrolls away.
var _foot_line: Label

## key -> the row the control sits in, so a tool that did not declare the key
## hides the label with it.
var _rows: Dictionary = {}

## key -> the button of a row whose text this docker writes rather than
## `ToolOptionControls`: a curve option, which nothing else fills in at all, and
## a toggle, whose button carried the same word the label column beside it did.
## Both are the docker's own instance of the control, so the bar, which has no
## label column, is untouched.
var _value_buttons: Dictionary = {}


func _init() -> void:
    _init_docker(SaDockerIds.TOOL_OPTIONS, "Tool Options", DEFAULT_SIZE, Vector2i(160, 120))
    # Under the toolbox on a fresh profile, where the tool being configured is.
    position = Vector2i(2, 392)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Tool Options")
    vbox.add_child(drag_handle)

    # The Advanced check, above the rows it shows and hides.
    header = ToolOptionsHeader.new()
    vbox.add_child(header)

    var scroll := SaMake.scroll(vbox, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var margin := SaMake.margin(scroll, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _rows_box = SaMake.column(margin, "Rows")
    _rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _floor = ToolOptionsFloor.new(scroll, _rows_box)

    _empty_label = SaMake.label(_rows_box, "EmptyLabel", tr("This tool has no options."))
    _empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _empty_label.custom_minimum_size.x = DockerUtils.px(WRAP_FLOOR)
    _empty_label.set_meta(SaUI.FONT_SCALE_META, ROW_FONT_SCALE)

    var foot := SaMake.margin(vbox, "Foot", SaUI.BASE_MARGIN)
    foot.add_theme_constant_override("margin_top", 0)
    _foot_line = SaMake.label(foot, "FootLine")
    _foot_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _foot_line.custom_minimum_size.x = DockerUtils.px(WRAP_FLOOR)
    _foot_line.set_meta(SaUI.FONT_SCALE_META, ROW_FONT_SCALE)
    SaTheme.bind_font(_foot_line, "text_muted")
    foot.visible = false

    options = ToolOptionControls.new(_rows_box)
    options.for_docker = true
    options.place = _place_control
    options.binding.tools_changed.connect(_on_tools_changed)
    held = ToolOptionsHeld.new(options)


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    _setup_docker_ready()
    # Outside `_listen_to_the_tool`, because Main hands the machine over before the
    # modules have loaded and the machine has a registry, so the first bind
    # gives up early. The machine announces the tool it built once the registry
    # arrives, and that announcement is what gets the rows built.
    if not EventBus.tool_changed.is_connected(_on_tool_changed):
        EventBus.tool_changed.connect(_on_tool_changed)
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    # A row that shows a canvas fraction as pixels is stale the moment the
    # document changes size, and Size has read the old document's pixels after a
    # crop.
    if not EventBus.document_resized.is_connected(_on_document_resized):
        EventBus.document_resized.connect(_on_document_resized)
    if not EventBus.advanced_options_changed.is_connected(_on_advanced_options_changed):
        EventBus.advanced_options_changed.connect(_on_advanced_options_changed)
    # A resize by hand is the size this tool wants, and the drag handle and the
    # resizer are the only things that emit this.
    if not EventBus.docker_layout_changed.is_connected(_on_painter_changed_the_layout):
        EventBus.docker_layout_changed.connect(_on_painter_changed_the_layout)
    # A row on this docker decides whether another is dead, and the painter
    # moves it here, so a write of its own has to re-ask the question.
    if options != null and not options.option_written.is_connected(_on_own_written):
        options.option_written.connect(_on_own_written)
    apply_layout_settings()
    _listen_to_the_tool()
    options.binding.follow(target_tool_machine)
    sync_from_tool()


func _process(_delta: float) -> void:
    held.follow(target_tool_machine, shown_tool_id())


func _on_document_resized(_document: SaDocument, _size: Vector2i) -> void:
    sync_from_tool()


## Every row again, because a preset writes the whole tool's settings and the
## rows are a view of them, in the frame after the pick as `ToolOptionsAfter` says.
func _on_preset_loaded(_preset_name: String) -> void:
    after.ask(&"rows", self, sync_from_tool)


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.TOOL_OPTIONS)


## A control and its label, as one row this can hide when the shown tool does
## not declare the option.
##
## A slider draws its own label inside itself, so it takes the whole width and
## gets no second one. An action carries its own word on the button and gets no
## label column for the same reason. Everything else is a label column and the
## control.
func _place_control(spec: SaOptionSpec, control: Control) -> void:
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control.custom_minimum_size.x = 0
    var row: Control
    if spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT:
        row = control
        # A slider is a whole row, so it asks for what a labelled row asks
        # for rather than for its widest text.
        var slider := control as FactorSlider
        if slider != null:
            slider.fits_its_text = false
            slider.preferred_width = DockerUtils.px(LABEL_WIDTH + VALUE_FLOOR)
            slider.custom_minimum_size.x = slider.preferred_width
    else:
        var writes_own_text := _writes_own_text(spec, control)
        # A switch is as wide as its longer word, so it is never cut and its
        # tooltip is only what the option does.
        var box := ToolOptionsRow.new(control.tooltip_text, writes_own_text and spec.kind != SaOptionSpec.Kind.BOOL)
        box.name = String(spec.key).capitalize().replace(" ", "") + "Row"
        if spec.kind != SaOptionSpec.Kind.ACTION:
            var label := SaMake.label(box, "Label", _row_label(spec))
            label.custom_minimum_size.x = DockerUtils.px(LABEL_WIDTH)
            # Wrapped rather than cut, so a language longer than English reads
            # its label whole on a second line when the control leaves it less
            # than its words.
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            label.set_meta(SaUI.FONT_SCALE_META, ROW_FONT_SCALE)
        box.add_child(control)
        # A choice's row is the docker's width and cannot grow, so a choice
        # longer than its column goes onto a second line rather than ending cut.
        if control is SaChoiceButton:
            (control as SaChoiceButton).wrap_its_words()
        row = box
        if spec.kind == SaOptionSpec.Kind.CURVE:
            # A curve's graph is square at 160 and stood under its label as the
            # widest thing on the brush's page after the pattern chooser. Its
            # frame keeps that height and the graph stays square inside it,
            # smaller when the row is narrower.
            var narrowest := DockerUtils.px(LABEL_WIDTH + VALUE_FLOOR)
            control.custom_minimum_size.x = narrowest
            var graph := SaCurveRow.graph_of(control)
            if graph != null:
                graph.custom_minimum_size = Vector2(narrowest, narrowest)
        if writes_own_text:
            _value_buttons[spec.key] = control
            # The same treatment the label column gets, because the two halves
            # of one row reading at two sizes is what clipped "100%, Pressure"
            # to "100%, Pressu" at the docker's own floor.
            control.set_meta(SaUI.FONT_SCALE_META, ROW_FONT_SCALE)
            if spec.kind == SaOptionSpec.Kind.BOOL:
                # The On/Off switch, dressed by the class the brush editor's
                # pages dress theirs with, so the two cannot drift.
                SaOnOffSwitch.dress(control as Button)
            else:
                # A button asks for its text's width unless it clips, and the
                # scroll's horizontal mode is disabled, so one long value asked
                # the whole column wider than the docker and the docker grew to
                # 350 at its default 300 to hold it. Cut, it asks for the floor.
                var button := control as Button
                button.clip_text = true
                button.text_overrun_behavior = SaTheme.TEXT_CUT
                button.custom_minimum_size.x = DockerUtils.px(VALUE_FLOOR)
    _rows_box.add_child(row)
    _rows[spec.key] = row
    DockerUtils.apply_ui_theme(row)


## What the label column of *spec*'s row says. An action row has none, so this
## is never asked about one.
##
## The option's own label everywhere except a curve option, whose label is the
## parameter it modulates and is therefore the name of a slider further down the
## same page, so Size, Opacity, Flow, Ratio, Softness and Spacing would each be
## drawn twice, the first of the two with no number on it. The curve's word
## says which of the two is the dab and which is how the dab follows the pen.
func _row_label(spec: SaOptionSpec) -> String:
    # A label that already says Dynamics, the Spacing page's, is not said twice.
    if spec.kind == SaOptionSpec.Kind.CURVE_OPTION and not spec.label.ends_with("Dynamics"):
        if SaWholeSentences.OPTION_DYNAMICS.has(spec.label):
            return tr(SaWholeSentences.OPTION_DYNAMICS[spec.label])
        return tr("%s dynamics") % tr(spec.label)
    return tr(spec.label)


## What a curve option row's button says it is set to, in place of the name its
## own label column already carries.
##
## The words are the module's, through `spec.describe_value`: they name sensors,
## and what a sensor is called is the stamp brush's to say, rather than the
## skeleton's by reading the control's label table, a class that does not
## parse without the module. A spec that brings no describer gets an empty
## button rather than a guess.
func _curve_option_summary(spec: SaOptionSpec, value: Variant) -> String:
    if spec == null or not spec.describe_value.is_valid():
        return ""
    return String(spec.describe_value.call(value))


## Whether this docker writes the text on *control* rather than leaving it as
## `ToolOptionControls` built it.
##
## A curve option, whose button was never filled in by anything, and every
## toggle, which says On or Off. A toggle with a word of its own would draw the
## word the label column already draws, and an iconed one kept its icon alone,
## which read as an empty field. The icon stays beside the word.
func _writes_own_text(spec: SaOptionSpec, control: Control) -> bool:
    if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
        return true
    return spec.kind == SaOptionSpec.Kind.BOOL and control is Button


## Puts each of those rows' state on its own button.
##
## Here rather than in `ToolOptionControls._show_value` beside the other kinds,
## because the text is this docker's phrasing of a row and not a value a control
## holds: the bar builds no curve option button, its toggles are the only name
## the option has there, and the brush editor draws a curve option as a page.
func _sync_row_text(tool: ToolState, tool_id: StringName) -> void:
    if options == null or tool == null:
        return
    for key: StringName in _value_buttons:
        var spec := options.spec_for(key, tool_id)
        if spec == null:
            continue
        _write_row_text(key, spec, options.read(key, tool, tool_id))


## One row's button text, from *value*.
func _write_row_text(key: StringName, spec: SaOptionSpec, value: Variant) -> void:
    var button := _value_buttons.get(key, null) as Button
    if button == null or not is_instance_valid(button) or spec == null:
        return
    if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
        button.text = _curve_option_summary(spec, value)
    else:
        # Mirrored here as well as by the controls' sync, whichever hears the
        # write first, and its word read now rather than at the next draw so
        # a reader before then agrees.
        button.set_pressed_no_signal(bool(value))
        SaOnOffSwitch.refresh(button)
    # A clipping button's minimum does not move with its text, so nothing else
    # tells the row its value is now a different width.
    var row := button.get_parent() as ToolOptionsRow
    if row != null:
        row.queue_sort()


## The two announcements a tool's values move by. The rows themselves, and the
## registry they are built from, are the controls' to follow.
func _listen_to_the_tool() -> void:
    if target_tool_machine == null:
        return
    # Here rather than in `_ready`, because this is the moment the docker has a
    # tool worth following and it is the only one a docker outside the tree
    # reaches. A suite runs inside `run_all._ready`, where `add_child` is
    # refused, so a docker a test builds never gets a `_ready` of its own.
    if not EventBus.tool_options_moved.is_connected(_on_tool_options_moved):
        EventBus.tool_options_moved.connect(_on_tool_options_moved)
    # A preset moves every option at once and this docker heard about none of
    # them: the bar's own hook on the preset box reaches the bar's controls and
    # nothing else, so a painter who loaded a preset and then dragged any row
    # here wrote the value the row was still showing back over the preset.
    # Beside the line above for the reason above it, so a docker a test builds
    # outside the tree is connected too.
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    # The erase toggle is written by the E key as well as by either surface's
    # row, and its setter announces it here and nowhere else. The key writes the
    # tool and neither surface, so without this the bar's switch ticked and the
    # Erase row here stayed as it was. Beside the two above for
    # their reason, a docker a test builds outside the tree hears it too.
    if not EventBus.brush_eraser_toggled.is_connected(_on_eraser_toggled):
        EventBus.brush_eraser_toggled.connect(_on_eraser_toggled)


## Rows whose control went with an unloaded module go with it.
func _forget_dropped_rows() -> void:
    for key: StringName in _rows.keys().duplicate():
        if options.control(key) == null:
            var row := _rows[key] as Control
            if row != null and is_instance_valid(row):
                row.queue_free()
            _rows.erase(key)
            _value_buttons.erase(key)


## The controls moved under the docker: a tool's rows came or went, or the blend
## modes were rebuilt. Either way the rows read the tool again.
func _on_tools_changed(rebuilt: bool) -> void:
    if rebuilt:
        _forget_dropped_rows()
    sync_from_tool()


## The controls and the size follow at once, so a write lands on the tool in
## hand, and the rows wait for the frame after with a load's.
func _on_tool_changed(_tool_name: String) -> void:
    _listen_to_the_tool()
    options.binding.follow(target_tool_machine)
    follow_tool_size()
    after.ask(&"rows", self, sync_from_tool)


## Files the size the window has now under the tool it was showing, and puts it
## into the size the tool it is moving to was left at.
##
## The docker size is saved for each tool separately, because some tools have
## fewer options, and the crop tool is the case: three rows in a box sized for the
## brush's twenty.
##
## **Only the size follows the tool, and the position deliberately does not.** A
## docker that jumps across the screen on a tool change is worse than one that
## changes height, and a painter places this docker once and then paints. The
## store's per-variant keys carry a size and nothing else for the same reason.
##
## **A tool nobody has sized keeps the size that is there**, which is the single
## stored size the file has always carried, so the first tool change after an
## upgrade moves nothing and a profile written by an older build is read by this
## one unchanged.
func follow_tool_size() -> void:
    var now := shown_tool_id()
    if now == _sized_for_tool:
        return
    var store := _layout_store()
    if store == null:
        _sized_for_tool = now
        return
    if not String(_sized_for_tool).is_empty():
        store.save_variant_size(self, String(name), String(_sized_for_tool))
    _sized_for_tool = now
    var wanted := store.variant_size(self, String(name), String(now))
    if wanted != Vector2i():
        size = wanted
        # Or the settle loop puts the size back inside the sixty frames after a
        # restore, as it would a restored position.
        store.note_placement(self)


## The painter dragged a handle or a resizer, so whatever size this docker has
## now is the size the tool it is showing wants.
func _on_painter_changed_the_layout() -> void:
    var store := _layout_store()
    if store != null and not String(_sized_for_tool).is_empty():
        store.save_variant_size(self, String(name), String(_sized_for_tool))


## The store, found the way `ui/settings/arrange/workspace_page.gd` finds it: it is a
## child of Main under its own name and a docker is handed no reference to it.
##
## **Found once and held**, because every tool switch asks and the search walks
## the whole tree. Forgotten when the store or this docker leaves the tree,
## and a search that finds nothing holds nothing, since a docker can be built
## before the store is.
func _layout_store() -> DockerLayoutStore:
    if is_instance_valid(_store):
        return _store
    var tree := get_tree()
    if tree == null or tree.root == null:
        return null
    var found := tree.root.find_child("DockerLayoutStore", true, false) as DockerLayoutStore
    if found == null:
        return null
    _store = found
    found.tree_exiting.connect(_forget_layout_store, CONNECT_ONE_SHOT)
    if not tree_exiting.is_connected(_forget_layout_store):
        tree_exiting.connect(_forget_layout_store)
    return _store


## The store held by `_layout_store` left the tree, or this docker did.
func _forget_layout_store() -> void:
    if is_instance_valid(_store) and _store.tree_exiting.is_connected(_forget_layout_store):
        _store.tree_exiting.disconnect(_forget_layout_store)
    _store = null


## Which of this window's sizes the store should read and write. The tool it is
## showing, because that is the only thing about this docker that changes what
## it needs room for.
func layout_variant() -> String:
    return String(shown_tool_id())


## The Advanced options check moved, so the rows behind it appear or go.
func _on_advanced_options_changed(_enabled: bool) -> void:
    sync_from_tool()


## The tool moved its own values, so the rows read them again. Values only:
## which rows are shown is the tool's declaration and a drag cannot change it,
## and this arrives once per mouse motion of a transform gesture.
func _on_tool_options_moved() -> void:
    sync_values_from_tool()


## The eraser switch moved, and whoever moved it, every row reads the tool
## again, the way the bar does on the same announcement.
func _on_eraser_toggled(_active: bool) -> void:
    sync_values_from_tool()


## The other surface wrote an option, so follow it without writing it back. A
## row on this docker moved, so a row whose life depends on it may have just
## died or come back. Deferred, because the write that announced it has not
## reached the tool yet on every path.
func _on_own_written(_key: StringName, _value: Variant) -> void:
    # And the word on the button follows the press, the colour and the text
    # both, and the text only ever followed the *other* surface's
    # write, `_on_peer_written`, or a whole sync. Pressing this docker's own
    # toggle left it reading Off with the button down.
    if _value_buttons.has(_key):
        _write_row_text(_key, options.spec_for(_key, shown_tool_id()), _value)
    var tool_id := shown_tool_id()
    var machine := target_tool_machine
    if String(tool_id).is_empty() or machine == null:
        return
    sync_row_enabled.call_deferred(machine.get_tool(tool_id), tool_id)
    if _decides_rows(_key):
        sync_from_tool.call_deferred()


func _on_peer_written(key: StringName, value: Variant) -> void:
    options.show_value(key, value)
    # The rows whose text this docker writes are not reached by `show_value`,
    # which fills in the control and not the wording around it.
    if _value_buttons.has(key):
        _write_row_text(key, options.spec_for(key, shown_tool_id()), value)
    if _decides_rows(key):
        sync_from_tool.call_deferred()


## Whether a row of the shown tool is drawn only while *key* holds a value, so
## a write to it changes which rows are drawn. Asked rather than syncing on
## every write, because a drag writes once a frame.
func _decides_rows(key: StringName) -> bool:
    var machine := target_tool_machine
    var descriptor := machine.get_descriptor(shown_tool_id()) if machine != null else null
    if descriptor == null:
        return false
    for spec: SaOptionSpec in descriptor.options:
        if SaTyped.name_at(spec.shown_when, "key", &"") == key:
            return true
    return false


## Points the blend menu at the registry, which the controls then follow along
## with the document's colour space. Both surfaces build a control for
## `blend_mode`, so both have one to fill.
func bind_registries(blend_registry: SaBlendModeRegistry) -> void:
    options.binding.follow_blend_modes(blend_registry)


## Shows *panel* where the tool's rows are and hides them while it is shown. An
## attached filter's widgets are `SaDialog`'s, with a custom row the option
## specs do not have, so the docker hosts the panel whole rather than learning
## to build a filter's rows. The panel is the docker's from here: a second one
## replaces the first, and `clear_filter_panel` frees it.
func show_filter_panel(panel: Control) -> void:
    clear_filter_panel()
    if panel == null:
        return
    _filter_panel = panel
    _rows_box.get_parent().add_child(panel)
    _rows_box.visible = false
    header.visible = false
    _foot_line.get_parent().visible = false
    SaUI.apply_ui_theme(panel)


## Takes the filter's panel away and gives the tool its rows back.
func clear_filter_panel() -> void:
    if _filter_panel != null and is_instance_valid(_filter_panel):
        # Freed at once out of a tree, because a `queue_free()` on a node that
        # is in none is never collected.
        var in_tree := _filter_panel.is_inside_tree()
        _filter_panel.get_parent().remove_child(_filter_panel)
        if in_tree:
            _filter_panel.queue_free()
        else:
            _filter_panel.free()
    _filter_panel = null
    _rows_box.visible = true
    header.visible = true
    _foot_line.get_parent().visible = not _foot_line.text.is_empty()


## The tool whose options the docker shows: the permanent one, never the held
## one, which is the rule the bar follows too.
func shown_tool_id() -> StringName:
    if target_tool_machine == null:
        return &""
    var id := target_tool_machine.default_tool_name
    return id if not String(id).is_empty() else target_tool_machine.active_tool_name


## Shows the rows the tool declared, in the order it declared them, hides the
## rest, and puts the tool's own values on them.
##
## The order is the descriptor's rather than the build order, because a row is
## shared by every tool that declares its key: without this the lasso's own
## shape would sit under a mode row the marquee had built first.
##
## **A row the bar is showing is left out**, and the foot line names it, so
## the docker's room goes to rows the bar lacks rather than to copies of it.
## Size and Opacity stay on the bar, whose copy is the one that works in focus
## mode. So the docker shows what the bar does not: a row the bar sent to its overflow, or one the painter hid from it,
## comes back here. Main runs this again on the bar's `refitted`.
##
## **A randomise row stays when its slider goes to the bar**, and names the slider
## it rolls, which `ToolOptionsRolls` says in full.
func sync_from_tool() -> void:
    if options == null or _rows_box == null:
        return
    var tool_id := shown_tool_id()
    var machine := target_tool_machine
    if String(tool_id).is_empty() or machine == null:
        return
    for key: StringName in _rows:
        (_rows[key] as Control).visible = false
    var descriptor := machine.get_descriptor(tool_id)
    var tool := machine.get_tool(tool_id)
    var own := func(key: StringName) -> Variant: return options.read(key, tool, tool_id)
    var read := SaOptionSpec.reading_settings(own, tool.get("settings") if tool != null else null)
    var shown := 0
    var on_bar: Array[String] = []
    if descriptor != null:
        for spec: SaOptionSpec in descriptor.options:
            var row := _rows.get(spec.key, null) as Control
            if row == null:
                continue
            # An option marked advanced is drawn only while the
            # painter has asked for those. Left invisible rather than dropped,
            # so turning the check back on costs a sync and not a rebuild.
            if not ToolOptionControls.shows_advanced(spec):
                continue
            # The row's own condition, which the Brush Editor's page honours
            # too: the noise brush drew all three fields' rows here whichever
            # was chosen, and Picture's Pattern row sat under Grain's and
            # Bristle's at the foot of the docker.
            if not spec.shown_under(read):
                continue
            if bar_shows(spec.key) and not spec.panel_also:
                on_bar.append(tr(spec.label))
                continue
            row.visible = true
            ToolOptionsRolls.name_row(row, spec, descriptor.options, bar_shows)
            _rows_box.move_child(row, shown)
            shown += 1
    # A tool whose every row is on the bar has options, and the foot line says
    # where they are.
    _empty_label.visible = shown == 0 and on_bar.is_empty()
    _rows_box.move_child(_empty_label, _rows_box.get_child_count() - 1)
    _write_foot_line(on_bar)
    sync_values_from_tool()
    # Which rows lead decides how short a layout may cut the docker.
    _floor.hold()
    # The docker opens at the height of the rows it is showing, and which rows
    # those are is decided right here rather than at `_ready`: the tools bind
    # after the modules load, so at ready this docker has one row and not the
    # twenty a brush declares. `grow_to_content` leaves the size
    # alone once the painter has arranged anything, so this cannot follow a tool
    # change around a workspace somebody has set up.
    #
    # **Once, on the first sync that has a row to measure**. This runs again on
    # every tool change, document open and registry change, and a grow that
    # lands after the layout store's settle loop has stopped re-asserting the
    # stored size is a grow nothing puts back: the docker was 430 logical pixels
    # tall when a document was opened in the first second and 540 when it was
    # opened a moment later. The stored layout is the painter's last word on the
    # height, so only the opening one may raise it.
    #
    # Deferred, because the rows were made visible a line ago and a container's
    # minimum is its own until its children have been laid out once.
    if shown > 0 and not _took_its_opening_height:
        _took_its_opening_height = true
        grow_to_content.call_deferred()
    # The rows decide how narrow the docker may go, and they change with the
    # tool and with Advanced. The floor was taken once at startup, so turning
    # Advanced on brought in the stamp's pattern chooser, wider than that floor,
    # and the docker could be dragged narrower than its rows: the check read
    # "Advance" and the close button was cut at the edge.
    if is_inside_tree():
        enforce_column_minimum.call_deferred()


## Whether the bar is showing its control for *key* on one of its rows now.
##
## Visible in the tree, so a control the painter hid from the bar, one the
## shown tool has no use for there, and every control while Preferences has the
## bar's options section off all answer no. **And not in the overflow's list**,
## which is visible in the tree only while it is open: a control in it is a tap
## away rather than at hand, and a row that came and went with the list would
## move under the painter's pen.
##
## The list is known by the floating panel it is, a widget anybody may name,
## rather than by the overflow button that owns it, which is an inner file of
## the top bar's package.
func bar_shows(key: StringName) -> bool:
    if peer_bar == null or not is_instance_valid(peer_bar):
        return false
    var control := peer_bar.options.control(key)
    if control == null or not control.is_inside_tree() or not control.is_visible_in_tree():
        return false
    var node := control.get_parent()
    while node != null:
        if node is SaFloatingPanel:
            return false
        node = node.get_parent()
    return true


## Puts "Radius and Opacity are on the top bar." at the docker's foot, naming
## *labels*, or takes the line away when they are none. Hidden with the rows
## while a filter's panel stands in for them.
func _write_foot_line(labels: Array[String]) -> void:
    if labels.is_empty():
        _foot_line.text = ""
    elif labels.size() == 1:
        _foot_line.text = tr("%s is on the top bar.") % labels[0]
    else:
        var joined := "%s %s %s" % [", ".join(labels.slice(0, -1)), tr("and"), labels[-1]]
        _foot_line.text = tr("%s are on the top bar.") % joined
    _foot_line.get_parent().visible = not labels.is_empty() and _filter_panel == null


## Puts the tool's values back on the rows without touching which rows are
## shown. The tail of `sync_from_tool`, split out because a gesture in flight
## needs this half and not the other.
##
## Muted throughout: a control that answers a programmatic set the way it
## answers a painter would write the value it was just handed straight back
## into the tool, which is one round trip per frame of a drag.
func sync_values_from_tool() -> void:
    if options == null:
        return
    var tool_id := shown_tool_id()
    var machine := target_tool_machine
    if String(tool_id).is_empty() or machine == null:
        return
    var tool := machine.get_tool(tool_id)
    options.muted = true
    options.sync(tool, tool_id, options.binding.canvas_min_dimension())
    options.muted = false
    _sync_row_text(tool, tool_id)
    sync_row_enabled(tool, tool_id)


## Dims and disables every row whose `enabled_when` option is not on one of the
## values it named.
##
## Repeat and Wobble options are dimmed when they have None as selected. Dimmed
## also means disabled, so the control is greyed *and* refuses the hand rather than being greyed and still
## moving. `Control.modulate` for the grey and the control's own disabled or
## editable flag for the rest, because a `Button` and a `Slider` do not share one
## property for it.
##
## Called after every value sync rather than only on a tool change, because the
## option that decides is a row on this same docker and the painter moves it
## here.
func sync_row_enabled(tool: ToolState, tool_id: StringName) -> void:
    if options == null or tool == null:
        return
    for key: StringName in options.keys():
        var spec := options.spec_for(key, tool_id)
        if spec == null:
            continue
        var value: Variant = options.read(spec.enabled_when, tool, tool_id)
        SaOptionSpec.apply_enabled(options.control(key), _rows.get(key, null) as Control, spec, value)


## The rows the docker is showing, top to bottom. What a test and a capture
## read.
func shown_keys() -> Array[StringName]:
    var out: Array[StringName] = []
    var ordered: Array = []
    for key: StringName in _rows:
        var row := _rows[key] as Control
        if row.visible:
            ordered.append([row.get_index(), key])
    ordered.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    for entry: Array in ordered:
        out.append(entry[1])
    return out


## Moves one Tool Options row: for a scenario, `{"option": {"key": "feather",
## "value": 0.02}}`, and answers with what the row now holds. A row whose
## control answers the capture door takes the rest of the step through it, so
## `{"option": {"key": "tip_image_path", "folder": "Sara"}}` drives the grid.
##
## A helper rather than a click because the docker is its own Window and an
## injected mouse event never reaches it, which is why every other docker step
## a scenario can take is a helper too.
##
## What it proves is the path a drag takes from `value_changed` onwards: the
## control writes the shown tool, the tool writes SaSettings, and SaSettings
## writes the file. The pixels-to-value arithmetic above that signal belongs to
## the slider and is not what this drives.
static func capture_option(tree: SceneTree, spec: Dictionary) -> String:
    var docker := tree.root.find_child(SaDockerIds.TOOL_OPTIONS, true, false) as ToolOptionsDocker
    if docker == null or docker.options == null:
        return "SaCapture: no Tool Options docker"
    var key := StringName(String(spec.get("key", "")))
    var widget := docker.options.control(key)
    if widget != null and widget.has_method("capture_option_edit"):
        var rest := spec.duplicate()
        rest.erase("key")
        return String(widget.call("capture_option_edit", rest))
    var slider := widget as FactorSlider
    if slider == null:
        return "SaCapture: the Tool Options docker shows no slider for '%s'" % key
    slider.set_value_no_signal(clampf(float(spec.get("value", 0.0)), slider.min_value, slider.max_value))
    slider.value_changed.emit(slider.value)
    return "SaCapture: option %s = %s" % [key, slider.value]


## Every row the Tool Options docker is showing for the active tool, with the
## label drawn on it and the tooltip behind it, for the state dump. A slider
## draws its own label as a child called "Label" and so does a labelled row, so
## one lookup serves both.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script.
static func capture_state(root: Window) -> Array:
    var docker := root.find_child(SaDockerIds.TOOL_OPTIONS, true, false)
    if docker == null:
        return []
    var rows_box := docker.find_child("Rows", true, false)
    if rows_box == null:
        return []
    var out: Array = []
    for child in rows_box.get_children():
        var row := child as Control
        if row == null or not row.visible or row.name == "EmptyLabel":
            continue
        var label := row.find_child("Label", true, false) as Label
        var entry := {
            "name": String(row.name),
            "label": label.text if label != null else "",
            "tooltip": row_tooltip(row),
            "value": row_value(row),
            # One line here because the dump is this file's and what dimmed means
            # is `SaOptionSpec`'s, which is the exception the protocol names.
            "enabled": SaOptionSpec.row_reads_enabled(row),
        }
        # A ramp row holds stops rather than a value, and a photograph of a ramp
        # cannot say where a stop is or what alpha it carries. The control
        # reports itself, the way the minimap and the Display page do.
        var reporter := row if row.has_method("stop_report") else _ramp_in(row)
        if reporter != null:
            entry["ramp"] = reporter.call("stop_report")
        out.append(entry)
    return out


## What a Tool Options row is showing: a slider's number, the id of the item an
## enum has selected, a blend mode's id, or a toggle's state. Null for a row that
## holds no value. A settings key that came back from disk proves the file
## round-tripped, and this is the other half of that: the row the painter reads
## shows it too.
##
## **By id and never by index**, so a shot of a transform says which mode made
## it, and a reordered enum does not quietly rename what a past shot proved.
## `SaOptionSpec.make_enum` has already put each choice's id on its item
## metadata, which is the value the property is set to.
##
## A curve option row answers the summary its own button carries, because that is
## where its state is: the button says "60%, Pressure" and leaves the dump's half
## here. An
## action row calls a method and holds no value, and answers the word on its
## button, which is the only text the row carries. A ramp is null here and
## reports its stops under `ramp`.
static func row_value(row: Control) -> Variant:
    var control := _row_control(row)
    var slider := control as FactorSlider
    if slider != null:
        return slider.value
    var option := control as OptionButton
    if option != null:
        if option.selected < 0:
            return null
        return option.get_item_metadata(option.selected)
    var blend := control as BlendModeButton
    if blend != null:
        return String(blend.current)
    # Before the plain `Button` below, because an `SaChoiceButton` is one, and
    # every `ENUM` row is built on it rather than on an `OptionButton`. Taken as
    # a plain button it would read null while the screen reads Rope. It answers
    # the value
    # `ToolOptionControls._show_value` gave `select_value`, which is the choice id
    # the dump carries.
    var choice := control as SaChoiceButton
    if choice != null:
        return choice.selected_value()
    # The Tip Image grid answers the path its pressed cell holds.
    if control is SaTipGrid:
        return (control as SaTipGrid).chosen
    var button := control as Button
    if button == null:
        return null
    if button.toggle_mode:
        return button.button_pressed
    # Two kinds of plain button reach here, and both are showing the only text
    # their row has: `ToolOptionControls._node_name` ends a curve option's
    # control in "Curve" and an action's in "Action". An action row has no label
    # column, so its button is the row's only name, and a shot of the docker
    # has something to be read against.
    if String(button.name).ends_with("Curve") or String(button.name).ends_with("Action"):
        return button.text
    return null


## The control a Tool Options row is built around: the row itself for a slider,
## which draws its own label, and the child beside the label column for every
## other kind.
static func _row_control(row: Control) -> Control:
    if row == null:
        return null
    if _holds_a_value(row):
        return row
    for child in row.get_children():
        var control := child as Control
        if control != null and _holds_a_value(control):
            return control
    return null


## Whether *node* is one of the controls a row's value can be read off. A label
## and a ramp editor are not, which is what keeps the label column of a row from
## being mistaken for the control beside it.
static func _holds_a_value(node: Control) -> bool:
    return node is FactorSlider or node is OptionButton or node is Button or node is SaTipGrid


## The colour ramp control inside a Tool Options row, when the row is a box
## around one rather than the control itself. Found by method rather than by
## cast: a cast to a `class_name` in a static function leaks the script.
static func _ramp_in(row: Control) -> Node:
    for node in row.find_children("*", "VBoxContainer", true, false):
        if node.has_method("stop_report"):
            return node
    return null


## The tooltip of a Tool Options row. A slider is the row and carries its own,
## while a labelled row is a box whose tooltip sits on the control inside it.
static func row_tooltip(row: Control) -> String:
    if not row.tooltip_text.is_empty():
        return row.tooltip_text
    for child in row.get_children():
        var control := child as Control
        if control != null and not control.tooltip_text.is_empty():
            return control.tooltip_text
    return ""
