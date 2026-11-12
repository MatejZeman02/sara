## Layers' Layer List and Actions as views another docker can hold: a list of
## its own with a keeper of its own, and a strip of the Layers docker's actions.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A whole list is placed as readily as a slider, and a placed element is a
## second view of the same state as at home, in step with its home copy, with
## nothing pinned per placement. So a placed Layer List is an `SaLayerList` filled and answered by an
## `SaLayerListKeeper` of its own, on the canvas the Layers docker's keeper
## shows, and the keepers share the pick and the folds, so the two lists draw
## one stack and a press, a drop or a fold in either acts on it. A placed
## Actions is an `SaLayerActions` acting on the active layer and on the pick of
## the Layers docker's own list.
##
## **Which list's pick a placed strip reads.** The Layers docker's, in every
## docker it is placed in. The keepers hand every pick to every list on the
## document, so a Layer List placed beside the strip lights the very layers the
## strip acts on, and a strip placed with no list beside it acts on the layers
## the painter last picked in any list. Reading the list beside it instead
## would pin something per placement, and would act on nothing different.
##
## Each view follows its home: the canvas the Layers docker's keeper is handed,
## and the layer types its strip offers, when it is built and every time that
## keeper follows the document, which it does from the moment it has a canvas.
## So a view a composed docker built at boot, before main handed the Layers
## docker its canvas, takes the canvas when main does. The home is held weakly,
## so the door keeps no docker a suite has freed alive. Rename and Ground on a
## placed strip, and a placed row's note mark, are answered by the Layers
## docker as its own are, so there is one rename window and one ground panel,
## the panel opened under the strip that was pressed.
##
## Named by the keeper alone, whose folder this is, so the folder keeps its one
## facade.
class_name SaLayerListViews
extends RefCounted

## The two elements, by the names the Layers docker's layout and its Elements…
## page give them.
const LIST := "Layer List"
const ACTIONS := "Actions"


## Registers a view of Layer List that follows *keeper*, and one of Actions
## that follows *keeper* and *strip*, under *category*, through
## `SaSettings.register_layout_element`, the call a module makes (hard rule 6,
## built-ins go through the public door). Returns *strip*, so the docker builds
## its own and registers both on one line. A docker built again registers again, its views replacing the last
## one's.
static func register(category: String, keeper: SaLayerListKeeper, strip: SaLayerActions) -> SaLayerActions:
    var held_keeper: WeakRef = weakref(keeper)
    var held_strip: WeakRef = weakref(strip)
    var list_view := func() -> Control: return ListView.new(held_keeper.get_ref() as SaLayerListKeeper)
    var strip_view := func() -> Control:
        return ActionsView.new(held_strip.get_ref() as SaLayerActions, held_keeper.get_ref() as SaLayerListKeeper)
    SaSettings.register_layout_element(category, LIST, LIST, false, "", list_view)
    SaSettings.register_layout_element(category, ACTIONS, ACTIONS, false, "", strip_view)
    return strip


## A Layer List of its own: the list, and the keeper that fills it and answers
## it. As tall as its rows up to [constant TALLEST], because the column of a
## composed docker gives a placed element its own height and no more, where the
## Layers docker's list takes whatever the window has left.
class ListView:
    extends MarginContainer

    ## The tallest the list stands before it scrolls, in logical pixels, ten
    ## of the rows the Layers docker draws.
    const TALLEST := 300

    ## The list the view shows, and the keeper filling it.
    var list: SaLayerList
    var keeper: SaLayerListKeeper

    ## The Layers docker's keeper, whose canvas the view's keeper takes, held
    ## weakly.
    var _home: WeakRef

    ## With no *home* the list shows nothing and acts on nothing, as a keeper
    ## handed no canvas does.
    func _init(home: SaLayerListKeeper) -> void:
        name = "LayerListView"
        set_meta(SaMake.KIND_META, SaMake.Kind.MARGIN)
        list = SaLayerList.new()
        list.name = "ItemList"
        add_child(list)
        keeper = SaLayerListKeeper.new(list)
        keeper.followed.connect(_fit)
        list.note_pressed.connect(_on_note_pressed)
        _home = weakref(home)
        if home != null:
            home.followed.connect(_follow)
        _follow()
        keeper.listen()

    ## Takes the home keeper's canvas, and the filter registry and Tool Options
    ## a filter's row shows its panel in, which a suite hands that keeper.
    func _follow() -> void:
        var home := _home.get_ref() as SaLayerListKeeper
        if home == null:
            return
        keeper.filter_registry = home.filter_registry
        keeper.tool_options = home.tool_options
        if keeper.target_canvas != home.target_canvas:
            keeper.target_canvas = home.target_canvas

    ## Stands as tall as the rows, up to [constant TALLEST]. Summed over the
    ## rows the list holds rather than read off its column, which still holds
    ## the rows a rebuild let go of until the frame ends.
    func _fit() -> void:
        var gap := float(list.vbox.get_theme_constant(&"separation"))
        var tall := 0.0
        for row: Control in list.rows:
            tall += row.get_combined_minimum_size().y + gap
        custom_minimum_size = Vector2(0.0, minf(tall, float(SaUI.px(TALLEST))))

    ## A row's note mark, handed to the Layers docker as a press on the mark of
    ## its own row for the same layer, which makes that layer active and opens
    ## its note in the rename window.
    func _on_note_pressed(index: int) -> void:
        var home := _home.get_ref() as SaLayerListKeeper
        var layer := list.layer_at(index)
        if home == null or layer == null:
            return
        var docker_list := home._list
        for row: int in docker_list.row_count():
            if docker_list.layer_at(row) == layer:
                docker_list.note_pressed.emit(row)
                return


## The Layers docker's strip of actions, a second one: plus, the arrow, minus,
## Ground, the four on the row and More, acting on the active layer of the
## canvas the docker shows and on the pick of the docker's own list.
class ActionsView:
    extends SaLayerActions

    ## The Layers docker's strip, whose canvas and layer types this one takes
    ## and whose rename and Ground the docker answers, held weakly.
    var _home: WeakRef

    ## With no *home* the strip acts on nothing, and with no *keeper* it takes
    ## the home's canvas once, when it is built.
    func _init(home: SaLayerActions, keeper: SaLayerListKeeper) -> void:
        super(home.list if home != null else null)
        name = "ActionsView"
        _home = weakref(home)
        if home != null:
            rename_requested.connect(home.rename_requested.emit)
            ground_pressed.connect(home.ground_pressed.emit)
        if keeper != null:
            keeper.followed.connect(_follow)
        _follow()

    ## Takes the home strip's canvas and layer types, and lights and dims the
    ## buttons for the active layer and the pick, as the docker does its own.
    func _follow() -> void:
        var home := _home.get_ref() as SaLayerActions
        if home != null:
            target_canvas = home.target_canvas
            layer_types = home.layer_types
        sync_buttons()
        if menu.visible:
            sync_from_active_layer()
