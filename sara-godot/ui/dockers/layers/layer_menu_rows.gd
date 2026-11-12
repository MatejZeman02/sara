## The rows the Layer menu and the Layers docker's More menu share, in the one
## order both draw them, so a job reads the same words in the same place behind
## either door.
##
## One list rather than one per menu, because two lists drift apart in their
## words, their rows and their order.
##
## **Blend Group on Its Own rather than Isolate Group**, which a painter from
## Krita or Photoshop reads as a view showing only the group. Its id is
## `layer_isolate` and the property `isolated`, the names a saved file holds.
##
## **A row is a command id where there is a command**, and its words, its chord
## and its sentence are then the command's, read from the registry. Blend
## Group on Its Own is no command, and Rename is one registered by the Layers
## docker rather than the skeleton, for Krita's F2, so the two carry
## their own words here and stand when a registry does not hold them. So does
## every command row, for a docker in a suite that has no registry to ask.
##
## **Whether a row can act is asked here, of the document the menu shows**,
## through the `can_` functions the commands' own dims ask. The Layer menu's
## commands see the main easel's document and the docker sees its canvas's,
## which are one document in the app and two in a suite.
##
## **The More menu leaves out the adds and Delete**, because plus, the arrow and
## minus stand on the docker's row for them, and whichever of the four
## operation buttons stands there too. The right click's menu at the pointer
## has no row of buttons beside it, so it draws every row the Layer menu
## does, which `SaLayerPointerMenu` asks for.
##
## **The docker's two menus draw only the mask rows that can run**: on
## a layer with no mask the two adds stand and the five that act on a mask are
## not drawn, since six greyed mask rows read as a menu full of nothing. The
## Layer menu keeps every row, dimmed, because a scenario presses it by number.
##
## **The grounds are one Ground row**, `SaGroundChoice`, which opens the list of
## every ground and swaps the one the document stands on rather than adding a
## second. A ground keeps its number among the kinds all the same, so a
## scenario's `menu_item` step that presses Paper by 450 picks Paper, and
## Search's New Paper Layer, which presses that number, does what the list does.
class_name SaLayerMenuRows
extends RefCounted

## Which layers a row acts on. A row that does not suit the active layer is
## dimmed, and a layer-only row says why on a group.
enum Suits { ANY, LAYER, GROUP }

## Where a line goes across both menus.
const LINE := &"---"

## The two rows that stand when the registry holds no command for them.
const RENAME := &"layer_rename"
const ISOLATE := &"layer_isolate"

## Where the kinds of layer the registry offers go, the plain one left out
## because New Layer is that row. Each is keyed on its kind's own id and
## numbered from `FIRST_KIND` in the registry's order.
const KINDS := &"layer_kinds"
## The Ground row, `SaGroundChoice`'s, named here so the Layer menu asks this
## file and not one inside the docker's package.
const GROUND := SaGroundChoice.ROW
## The Duplicate To row, `SaDuplicateToChoice`'s, a branch listing the other
## open documents.
const DUPLICATE_TO := SaDuplicateToChoice.ROW
const FIRST_KIND := 450

## A layer-only row's hover on a group, in place of its sentence: a group's
## lock is on whatever it says, and there is nothing in one to clear, merge or
## bake.
const NOT_ON_A_GROUP := "A group has no pixels of its own for this to act on."

## Each row is its id, its number in the Layer menu, which the door's
## `menu_item` step and the suites press it by, what it suits, whether the More
## menu draws it, its words and its sentence. A command row's words are the
## ones it reads when no registry answers, and its sentence is the command's.
const ROWS: Array = [
    [&"layer_new_paint", 400, Suits.ANY, false, "New Layer", ""],
    [&"layer_new_double", 440, Suits.ANY, false, "New Layer at Double Resolution", ""],
    [KINDS, FIRST_KIND, Suits.ANY, false, "", ""],
    [SaGroundChoice.ROW, 430, Suits.ANY, false, SaGroundChoice.WORDS, SaGroundChoice.SENTENCE],
    [&"layer_via_copy", 419, Suits.ANY, false, "Layer via Copy", ""],
    [&"layer_via_cut", 420, Suits.ANY, false, "Layer via Cut", ""],
    [&"layer_via_seamless_cut", 429, Suits.ANY, false, "Layer via Seamless Cut", ""],
    LINE,
    [RENAME, 442, Suits.ANY, true, "Rename...", "Rename the layer and edit its note."],
    [&"layer_duplicate", 401, Suits.ANY, true, "Duplicate Layer", ""],
    [SaDuplicateToChoice.ROW, 428, Suits.ANY, false, SaDuplicateToChoice.WORDS, SaDuplicateToChoice.SENTENCE],
    [&"layer_delete", 402, Suits.ANY, false, "Delete Layer", ""],
    LINE,
    [&"layer_group", 407, Suits.ANY, true, "Group", ""],
    [
        ISOLATE,
        443,
        Suits.GROUP,
        true,
        "Blend Group on Its Own",
        "Blend the group's layers with each other first, and the result with what is below it."
    ],
    [&"layer_clip_to_below", 408, Suits.ANY, true, "Clip to Layer Below", ""],
    LINE,
    [&"layer_move_up", 403, Suits.ANY, true, "Move Up", ""],
    [&"layer_move_down", 404, Suits.ANY, true, "Move Down", ""],
    LINE,
    [&"layer_merge_down", 405, Suits.LAYER, true, "Merge Down", ""],
    [&"layer_merge_visible", 448, Suits.ANY, true, "Merge Visible", ""],
    [&"layer_flatten", 406, Suits.ANY, true, "Flatten", ""],
    [&"layer_bake", 441, Suits.LAYER, true, "Resample to Document Resolution", ""],
    [&"layer_rasterize_impasto", 446, Suits.LAYER, true, "Rasterize Impasto", ""],
    [&"layer_export_lut", 449, Suits.ANY, true, "Export Effects as LUT...", ""],
    LINE,
    [&"layer_lock", 410, Suits.LAYER, true, "Lock Layer", ""],
    [&"layer_alpha_lock", 411, Suits.LAYER, true, "Lock Alpha", ""],
    LINE,
    [&"layer_clear", 409, Suits.LAYER, true, "Clear Layer", ""],
    LINE,
    [&"layer_mask_add", 412, Suits.ANY, true, "Add Mask", ""],
    [&"layer_mask_add_from_selection", 413, Suits.ANY, true, "Add Mask from Selection", ""],
    [&"layer_mask_delete", 414, Suits.ANY, true, "Delete Mask", ""],
    [&"layer_mask_apply", 415, Suits.ANY, true, "Apply Mask", ""],
    [&"layer_rasterize", 427, Suits.ANY, true, "Rasterize Layer", ""],
    [&"layer_mask_invert", 416, Suits.ANY, true, "Invert Mask", ""],
    [&"layer_mask_disable", 417, Suits.ANY, true, "Disable Mask", ""],
    [&"layer_mask_to_selection", 418, Suits.ANY, true, "Mask to Selection", ""],
]

## The rows with a tick, the ones whose command carries a `checked`, and
## Blend Group on Its Own. The suite holds this against the commands.
const TICKS: Array[StringName] = [&"layer_lock", &"layer_alpha_lock", ISOLATE, &"layer_mask_disable"]

var _document: SaDocument
var _commands: SaCommandRegistry
var _kinds: SaLayerTypeRegistry


## One row as a menu draws it, everything it shows worked out.
class Row:
    extends RefCounted

    var id: StringName
    var number: int
    var words: String = ""
    var chord: String = ""
    var sentence: String = ""
    var tick: bool = false
    var ticked: bool = false
    var disabled: bool = false
    ## Whether the row opens a child list beside it rather than acting.
    var branch: bool = false
    ## What the box says on hover, for Blend Group on Its Own held by its mask
    ## or a filter.
    var box_tip: String = ""

    func _init(row_id: StringName, row_number: int) -> void:
        id = row_id
        number = row_number

    ## Adds the row to *popup* under *key*, the tick's box dimmed with the row
    ## because `add_row` leaves a box alone, and the sentence on hover in place
    ## of the label the popup puts there.
    func draw(popup: SaChoicePopup, key: StringName, icon_name: String = "") -> void:
        if branch:
            popup.add_branch_row(key, words, "", disabled)
            popup.label_button(key).tooltip_text = sentence
            return
        popup.add_row(key, words, tick, ticked, icon_name, chord, disabled, box_tip)
        if tick:
            popup.check_box(key).disabled = disabled
        popup.label_button(key).tooltip_text = sentence


## *document* is what the rows act on, and null dims every row. *commands* gives
## a command row its words, chord and sentence, and *kinds* the kinds to add.
func _init(document: SaDocument, commands: SaCommandRegistry = null, kinds: SaLayerTypeRegistry = null) -> void:
    _document = document
    _commands = commands
    _kinds = kinds


## Every kind a painter can add from the docker's arrow: the registry's, the
## background left out because a document is born with one, made at New.
##
## **Left out by its id, not for storing nothing**. The paper stores nothing as
## well, and a filter on that would leave it out of the app.
static func addable(registry: SaLayerTypeRegistry) -> Array[SaLayerTypeDescriptor]:
    var out: Array[SaLayerTypeDescriptor] = []
    if registry == null:
        return out
    for descriptor: SaLayerTypeDescriptor in registry.list_descriptors():
        if descriptor.id != &"background" and descriptor.offered():
            out.append(descriptor)
    return out


## The words a kind's row reads, its registered name or its id.
static func kind_words(descriptor: SaLayerTypeDescriptor) -> String:
    return descriptor.display_name if not descriptor.display_name.is_empty() else String(descriptor.id)


## What a kind's row shows where a command row shows its chord: the mark of a
## row that opens another list for a kind that holds filters, whose row opens
## `SaLayerKindBrowser`'s list of them as `run` says, and nothing for any other.
static func kind_hint(descriptor: SaLayerTypeDescriptor) -> String:
    return SaChoiceRow.BRANCH_MARK if not descriptor.input.is_empty() else ""


## The five mask rows that act on a mask, which a docker's menu leaves out
## while no picked layer has one.
const ON_A_MASK: Array[StringName] = [
    SaMaskOps.DELETE, SaMaskOps.APPLY, SaMaskOps.INVERT, SaMaskOps.DISABLE, SaMaskOps.TO_SELECTION
]


## The rows in order, and [constant LINE] between blocks, with no line doubled
## and none at either end. *more* is the docker's More menu, and *standing* the
## ids whose button stands on the docker's row. *live_masks* is a docker's
## menu, the More menu or the one at the pointer, which draws the five rows
## of [constant ON_A_MASK] only while a picked layer has a mask.
func rows(more: bool, standing: Array[StringName] = [], live_masks: bool = false) -> Array:
    var out: Array = []
    var line_waiting := false
    for entry: Variant in ROWS:
        if entry is StringName:
            line_waiting = not out.is_empty()
            continue
        var fields: Array = entry
        if (more and not fields[3]) or standing.has(fields[0]):
            continue
        if live_masks and ON_A_MASK.has(fields[0]) and not _a_mask_is_picked():
            continue
        var drawn: Array = _kind_rows() if fields[0] == KINDS else _row(fields)
        if fields[0] == SaGroundChoice.ROW:
            drawn = _ground_row(fields)
        if fields[0] == DUPLICATE_TO:
            drawn = _duplicate_to_row(fields)
        if drawn.is_empty():
            continue
        if line_waiting:
            out.append(LINE)
            line_waiting = false
        out.append_array(drawn)
    return out


## The id of the Layer menu's row numbered *number*, or `&""` for none.
func id_at(number: int) -> StringName:
    for entry: Variant in ROWS:
        if entry is Array and entry[1] == number and entry[0] != KINDS:
            return entry[0]
    var kinds := _addable_kinds()
    var index := number - FIRST_KIND
    return kinds[index].id if index >= 0 and index < kinds.size() else &""


## The Layer menu's number of the row *id*, or -1, for a suite that presses a
## row by its command.
static func number_of(id: StringName) -> int:
    for entry: Variant in ROWS:
        if entry is Array and entry[0] == id:
            return entry[1]
    return -1


## Runs one of the rows that is no command, on the document: Blend Group on
## Its Own flipped, a ground picked through `SaGroundChoice`, or a kind added
## above the active layer. Rename and the Ground row's list are the caller's,
## because the dialog and the list are. Answers whether anything was done.
##
## **A kind that holds filters rather than paint asks which first**, an
## adjustment or an effect layer: its row opens `SaLayerKindBrowser` under
## *host*, and the filter picked there makes the layer. Added bare, it was a
## layer that did nothing, named Layer 2, with no sign of where it was set.
## Without a host, which is a caller with no tree, it is added bare still.
func run(id: StringName, host: Node = null) -> bool:
    if _document == null:
        return false
    var layer := _document.active_layer
    if id == ISOLATE:
        if not _live(ISOLATE, layer):
            return false
        SaLayerOps.new(_document).set_isolated(layer, not layer.isolated)
        return true
    if SaGroundChoice.new(_document, _kinds).pick(id):
        return true
    for descriptor: SaLayerTypeDescriptor in addable(_kinds):
        if descriptor.id == id and host != null and not descriptor.input.is_empty():
            return SaLayerKindBrowser.open_on(host, _document, descriptor, _kinds) != null
        if descriptor.id == id:
            SaLayerOps.new(_document).add(id, _kinds)
            return true
    return false


## Fills the Ground row's list, the standing ground marked, opens it beside
## *popup*'s row *key* and answers it. A pick reaches *on_chosen* with the
## ground's id, which `run` takes.
func open_grounds(popup: SaChoicePopup, on_chosen: Callable, key: StringName) -> SaChoicePopup:
    return SaGroundChoice.new(_document, _kinds).open_beside(popup, on_chosen, key)


## *fields*' row, or none for a command a registry is bound and does not hold,
## which is a module that is not loaded.
func _row(fields: Array) -> Array:
    var id: StringName = fields[0]
    var descriptor := _commands.get_descriptor(id) if _commands != null else null
    if descriptor == null and _commands != null and id != RENAME and id != ISOLATE:
        return []
    var layer := _document.active_layer if _document != null else null
    var on_group := layer != null and layer.is_group
    var row := Row.new(id, fields[1])
    row.words = tr(descriptor.menu_label() if descriptor != null else fields[4])
    row.sentence = tr(descriptor.sentence if descriptor != null else fields[5])
    if descriptor != null:
        row.chord = _commands.shown_chord(id, 1)
    if id == &"layer_group" and on_group:
        row.words = tr("Ungroup")
    row.tick = TICKS.has(id)
    row.ticked = row.tick and _ticked(id, layer)
    row.disabled = not _live(id, layer)
    if id == &"layer_merge_down" and row.disabled and layer != null:
        row.sentence = merge_refusal(layer, row.sentence)
    if id == &"layer_rasterize" and row.disabled and layer != null:
        row.sentence = SaRasterizeLayer.refusal(_document, layer)
    if fields[2] == Suits.LAYER and on_group:
        row.disabled = true
        row.ticked = false
        row.sentence = tr(NOT_ON_A_GROUP)
    if id == ISOLATE and SaLayerStack.held_isolated(layer):
        row.box_tip = tr("The group's mask makes it blend on its own. Delete the mask to blend its layers one by one.")
        if layer.mask == null:
            row.box_tip = tr(
                "A filter on the group makes it blend on its own. Detach it or switch it off to blend its layers one by one."
            )
    return [row]


## Why Merge Down is dimmed on *layer*, the first thing `SaLayerRefusals.merge`
## finds, in the words the corner says when the merge is pressed, or
## *otherwise* when it finds nothing. The dimmed row read the command's own
## sentence, so above a ground it said what Merge Down does and not why it
## would not. The docker's Merge Down button asks it too, for its hover.
func merge_refusal(layer: SaLayer, otherwise: String) -> String:
    var stack := SaLayerOps.new(_document).layers()
    var index := stack.find(layer)
    if index == 0:
        return tr("'%s' is the bottom layer, with nothing below it to merge into.") % layer.name
    if index < 0:
        return otherwise
    var found := SaLayerRefusals.new(_document).merge(layer, stack[index - 1])
    return tr(str(found[0])) % found[1] if not found.is_empty() else otherwise


## The Ground row, `SaGroundChoice`'s, a branch live while there is a
## document, and none when no ground is registered.
func _ground_row(fields: Array) -> Array:
    if SaGroundChoice.new(_document, _kinds).kinds().is_empty():
        return []
    var row := Row.new(fields[0], fields[1])
    row.words = tr(fields[4])
    row.sentence = tr(fields[5])
    row.branch = true
    row.disabled = _document == null
    return [row]


## The Duplicate To row, a branch live while there is a layer to copy and
## another document open to copy it into.
func _duplicate_to_row(fields: Array) -> Array:
    var row := Row.new(fields[0], fields[1])
    row.words = tr(fields[4])
    row.sentence = tr(fields[5])
    row.branch = true
    row.disabled = not SaDuplicateToChoice.new(_document).live()
    return [row]


## Opens the Duplicate To row's list of the other open documents beside
## *popup*'s row *key*, and answers it. A pick copies there.
func open_duplicate_to(popup: SaChoicePopup, key: StringName) -> SaChoicePopup:
    return SaDuplicateToChoice.new(_document, popup).open_beside(popup, key)


## The kinds' rows, plain and the grounds left out, each live while there is a
## document, saying on hover what its kind does and ending in the mark when it
## opens the list of filters. A ground keeps its number,
## so every other kind's stays what it was.
func _kind_rows() -> Array:
    var out: Array = []
    var kinds := _addable_kinds()
    for index in kinds.size():
        if SaGeneratedLayer.answers_height(kinds[index]):
            continue
        var row := Row.new(kinds[index].id, FIRST_KIND + index)
        row.words = tr(kind_words(kinds[index]))
        row.sentence = tr(kinds[index].hint)
        row.chord = kind_hint(kinds[index])
        row.disabled = _document == null
        out.append(row)
    return out


func _addable_kinds() -> Array[SaLayerTypeDescriptor]:
    var out: Array[SaLayerTypeDescriptor] = []
    for descriptor: SaLayerTypeDescriptor in addable(_kinds):
        if descriptor.id != SaLayerTypeDescriptor.PLAIN:
            out.append(descriptor)
    return out


## Whether the row *id* would act on *layer*, the question each command's own
## dim asks, and nothing without a document.
func _live(id: StringName, layer: SaLayer) -> bool:
    if _document == null:
        return false
    if id in [&"layer_new_paint", &"layer_new_double", &"layer_flatten", &"layer_merge_visible"]:
        return true
    if layer == null:
        return false
    var ops := SaLayerOps.new(_document)
    match id:
        &"layer_bake":
            return ops.can_bake(layer)
        &"layer_rasterize_impasto":
            return SaRasterizeImpasto.can_rasterize(_document, layer)
        &"layer_rasterize":
            return SaRasterizeLayer.can_rasterize(_document, layer)
        &"layer_export_lut":
            return SaEffectsLut.can_export(layer)
        &"layer_delete":
            return ops.can_remove(layer)
        &"layer_via_cut", &"layer_via_seamless_cut":
            return _document.selection.active
        &"layer_move_up":
            return SaLayerSetStep.new(_document).can_move(_document.picked.acted_on(_document), 1)
        &"layer_move_down":
            return SaLayerSetStep.new(_document).can_move(_document.picked.acted_on(_document), -1)
        &"layer_merge_down":
            return ops.can_merge_down(layer)
        ISOLATE:
            return layer.is_group and not SaLayerStack.held_isolated(layer)
    if SaMaskOps.ALL.has(id):
        return SaLayerSetStep.can_mask(id, _document.picked.acted_on(_document))
    return true


## Whether any layer the rows act on has a mask.
func _a_mask_is_picked() -> bool:
    if _document == null:
        return false
    for owner: Object in _document.picked.acted_on(_document):
        if SaMaskOps.mask_of(owner) != null:
            return true
    return false


## What a tick row's box shows for *layer*.
static func _ticked(id: StringName, layer: SaLayer) -> bool:
    if layer == null:
        return false
    match id:
        &"layer_lock":
            return layer.is_locked
        &"layer_alpha_lock":
            return layer.alpha_locked
        ISOLATE:
            return SaLayerStack.isolates(layer)
        &"layer_mask_disable":
            return layer.mask != null and not layer.mask.enabled
    return false
