## Floating colour picker docker window for selecting painting colours.
##
## Holds the picker, which wires itself to `SaColors` and the event bus the way
## every view of its elements in another docker does, and registers those views.
##
## **A removed swatch can come back.** The store remembers it, the
## strip's menu offers Undo remove, and the notice this docker puts up says
## so. While that notice is up Ctrl+Z puts the swatch back rather than
## stepping the picture's history, through [method answer_undo], which the
## shortcut router asks before the history. A swatch is no step of the
## document, so the binding lasts exactly as long as the line that offers it.
@tool
extends DockerWindow

class_name ColorDocker

## What the docker opens at, matching its row in `docker_layout_default.cfg`
## the way the Info and Tool Options dockers keep theirs in step, and pinned
## against that file by `ui/dockers/color/tests/test_color_docker_rows.gd`.
##
## 364 tall was the shipped height, and it had stopped being enough the day two
## slider rows were added: the column wants 422 logical pixels and 364 gives it
## 323, so the last four sliders were laid out ninety-nine pixels below the
## docker's own bottom edge with `visible` reading true for all six. 480 left
## the column its 422 with the drag bar and the margins paid for.
##
## The five rows under the pair are hidden by default, which left 84 pixels
## blank under it at 480, and the Layers docker below takes them, whose list
## holds fourteen rows with them. 396 held the shape and the pair with the drag
## bar, the margins and the grip paid for, and a painter who turns the rows on
## reaches them through the scroll the column sits in. 393 is that height to the
## unit: at 396 the column was given 343 for the 332 its rows need with the
## margins' 8, which left 3 empty under the pair.
const DEFAULT_SIZE := Vector2i(310, 393)

## The id the usage tally counts a Ctrl+Z that put a swatch back under.
const UNDO_REMOVE_ACTION := &"swatch_undo_remove"

var color_picker: Control

## The line the last Remove put up, which is how [method answer_undo] knows the
## notice on screen is still that one and not a later line over it.
static var _removed_notice: String = ""


func _init() -> void:
    _init_docker(SaDockerIds.COLOR, "Colour Picker", DEFAULT_SIZE, Vector2i(160, 200))

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Colour Picker")
    vbox.add_child(drag_handle)

    # The rows scroll, the way the Tool Options docker's do, because a bigger
    # default only fixes a fresh profile. A stored one keeps the geometry it was
    # saved at, which may be shorter than the rows it now holds. Vertical
    # only: the column is a stack of
    # full-width rows and a sideways scroll on it would be a way to lose one
    # rather than reach it.
    var scroll := SaMake.scroll(vbox, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var margin := SaMake.margin(scroll, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    color_picker = SaColorPickerView.new()
    color_picker.name = "ColorPicker"
    color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    color_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
    margin.add_child(color_picker)
    color_picker.unique_name_in_owner = true
    color_picker.owner = self
    SaColorPickerView.register_views()


## The settings key predates the docker id and every saved profile carries it.
func settings_category() -> String:
    return "ColorPicker"


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    assert(color_picker != null, "ColorPicker node not found")

    _setup_docker_ready()
    SaUI.apply_ui_theme(color_picker)

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout("ColorPicker")


## Remove from a chip's menu: the store takes the swatch and remembers it, and
## the corner says it went and how to have it back, where a silent delete
## would say neither.
static func remove_swatch(index: int) -> void:
    SaColors.remove_swatch(index)
    if SaColors.last_removed_swatch == null:
        return
    var chords := SaShortcutStore.chords_for(&"edit_undo")
    _removed_notice = _tr("Swatch removed")
    if not chords.is_empty():
        _removed_notice = _tr("Swatch removed. %s puts it back.") % chords[0]
    SaMessage.notice(_removed_notice)


## Undo remove, from the strip's menu or from Ctrl+Z under the notice. Answers
## whether a swatch came back.
static func undo_remove() -> bool:
    if not SaColors.undo_remove():
        return false
    _removed_notice = ""
    SaMessage.notice(_tr("Swatch restored"))
    return true


## What the router's history group answers for *event*: a Ctrl+Z while the
## "Swatch removed" notice is up puts the swatch back, and anything else is
## *otherwise*'s, which is the history. Asked first, because the notice is the
## promise and the canvas's last stroke is not what it promised to undo.
##
## The notice is read rather than a clock kept here, so the binding ends the
## moment the line does, and a later line over it ends it too.
static func answer_undo(event: InputEvent, otherwise: Callable) -> StringName:
    if _removed_notice_up() and SaShortcutKeys.pressed(event, ["ui_undo", "edit_undo"], true, true) and undo_remove():
        return UNDO_REMOVE_ACTION
    return otherwise.call(event)


static func _removed_notice_up() -> bool:
    if _removed_notice.is_empty() or SaColors.last_removed_swatch == null:
        return false
    var notice := SaMessage.notice_widget()
    return notice != null and notice.showing() and notice.label.text == _removed_notice


## `tr` for a static function, which has no object to ask.
static func _tr(text: String) -> String:
    return String(TranslationServer.translate(text))


## The colour picker's shape, the shapes it offers and where its cursors are,
## for the state dump. Empty when the docker is not built, the way the minimap's
## block is. `views` is what every view of one of its elements in another
## docker shows, each named `…View` after its element.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script at exit.
static func capture_state(root: Window) -> Dictionary:
    var docker := root.find_child(SaDockerIds.COLOR, true, false)
    if docker == null:
        return {}
    var picker: Variant = docker.get("color_picker")
    if picker == null:
        return {}
    var report: Dictionary = (picker as Object).call("picker_report")
    var views: Array[Dictionary] = []
    for node: Node in root.find_children("*View", "", true, false):
        var view := node as SaColorPickerView
        if view != null:
            views.append(view.view_report())
    report["views"] = views
    return report
