## The line a first launch shows between the panes and New and Open, for a
## painter who has never painted: one sentence and the two places to begin,
## the lessons and the manual's first page, each a button that opens it.
##
## Both buttons run their command through the registry, the call Help's own
## rows make, so the window they open is the one there is. The Tutorials
## button is drawn only while a module has registered `help_tutorials`: a Sara
## without the tutorials module has no lessons to point at, and the sentence
## then names the manual alone. The boot builds the welcome window before any
## registry exists, so the line reads it again when the boot is done and when
## the registry announces a change.
class_name WelcomeBeginnerLine
extends HBoxContainer

## What a driver and a suite find the line and its buttons by.
const NODE_NAME := "BeginnerLine"
const TEXT := "BeginnerText"
const TUTORIALS := "BeginnerTutorials"
const MANUAL := "BeginnerManual"

## The command a module registers for its lessons, and the manual's.
const TUTORIALS_COMMAND := &"help_tutorials"
const MANUAL_COMMAND := &"help_manual"

## The command registry the buttons run through. Found on `Main` once it
## exists, and set by a suite that builds its own. Null before the boot is
## done, when the Tutorials button stays hidden.
var commands: SaCommandRegistry

var _text: Label
var _tutorials: Button
var _manual: Button


func _init() -> void:
    name = NODE_NAME
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    _text = SaMake.label(self, TEXT, _sentence(false))
    _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _tutorials = SaMake.button(self, TUTORIALS, tr("Tutorials"), _tooltip())
    _tutorials.pressed.connect(_run.bind(TUTORIALS_COMMAND))
    _manual = SaMake.button(self, MANUAL, tr("Manual"), tr("The painter's manual, from its first page."))
    _manual.pressed.connect(_run.bind(MANUAL_COMMAND))
    tree_entered.connect(refresh)
    EventBus.boot_finished.connect(refresh)


## Shows the Tutorials button when the lessons are loaded, and says the
## sentence that matches.
func refresh() -> void:
    var registry := _command_registry()
    var lessons := registry != null and registry.has(TUTORIALS_COMMAND)
    _tutorials.visible = lessons
    _text.text = _sentence(lessons)
    _tutorials.tooltip_text = _tooltip()


## Whether the Tutorials button is offered, for a suite and a shot.
func offers_lessons() -> bool:
    return _tutorials.visible


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and _text != null:
        _tutorials.text = tr("Tutorials")
        _tutorials.tooltip_text = _tooltip()
        _manual.text = tr("Manual")
        _manual.tooltip_text = tr("The painter's manual, from its first page.")
        _text.text = _sentence(_tutorials.visible)


## The sentence, naming the lessons only when the module that has them supplied
## one. The skeleton holds no words about a lesson.
func _sentence(lessons: bool) -> String:
    var descriptor := _lessons_descriptor() if lessons else null
    var said := descriptor.beginner_line if descriptor != null else ""
    if not said.is_empty():
        return tr(said)
    return tr("New to painting? Begin with the manual's first page.")


## The words the lessons' module gave the button, its command's sentence, empty
## when no module registered one.
func _tooltip() -> String:
    var descriptor := _lessons_descriptor()
    return tr(descriptor.sentence) if descriptor != null and not descriptor.sentence.is_empty() else ""


## The descriptor of the command a module registered for its lessons, or null.
func _lessons_descriptor() -> SaCommandDescriptor:
    var registry := _command_registry()
    return registry.get_descriptor(TUTORIALS_COMMAND) if registry != null else null


func _run(command_id: StringName) -> void:
    var registry := _command_registry()
    if registry != null:
        registry.execute(command_id)


## The command registry, found on `Main` on first use and kept, the way the
## Tips pane finds its own.
func _command_registry() -> SaCommandRegistry:
    if commands == null and is_inside_tree() and get_tree().current_scene != null:
        var registries := get_tree().current_scene.get("registries") as SaRegistries
        commands = registries.commands if registries != null else null
    if commands != null and not commands.changed.is_connected(refresh):
        commands.changed.connect(refresh)
    return commands
