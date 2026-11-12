## Modules › Local Server's dialog: what the server the row just opened is, and
## a button that copies the first message for a coding agent.
##
## A student connecting a notebook is no agent, a row that opens a server
## should say so, and a press should put nothing on the clipboard unasked. So
## the row is a tick that opens and closes the server, and this says
## what it opened: that it answers this computer alone, the file that says
## where, how a notebook connects, and the paragraph `SaAgentInvite` writes,
## behind a button. Nothing reaches the clipboard until that button is pressed.
##
## Built by the harness, which owns the door, with the file the door wrote. The
## menu reads the tick through [constant LISTENING_GROUP] rather than through
## the harness, which nothing in `ui` but the boot names.
##
## **A press outside it puts it away, as the Welcome window's does.** While it
## is up it hears the
## main window and every docker, and a press on either hides it and goes no
## further than the canvas, which paints nothing for it, the way
## [SaWelcomeWindow] and [SaPutAway] say. A press on the dialog itself, its copy
## button among them, leaves it up. It only hides: the server stays open and the
## Modules row stays ticked, and the row is what closes the server.
@tool
class_name SaLocalServerDialog
extends SaDialogWindow

const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")

## The group a capture node is in while its door listens, a door `--agent-door`
## opened at boot as well as one the row opened. Whether it holds a node is the
## row's tick.
const LISTENING_GROUP := &"sa_local_server"

## What the copy button prints, so a run read from outside finds the paragraph
## on standard output where a nested compositor hands it no clipboard.
const COPIED := "SaLocalServerDialog: copied the prompt for an agent: "

## The call that puts the paragraph on the clipboard, `DisplayServer.clipboard_set`
## in everything but a suite, which also counts the calls: a nested compositor
## hands a client with no keyboard focus an empty clipboard, so reading it back
## cannot tell "untouched" from "never readable".
## Test seam. A suite that replaces it puts `DisplayServer.clipboard_set` back.
static var clipboard: Callable = DisplayServer.clipboard_set

var copy_button: Button = null

## Hears the presses beside this dialog that put it away while it is up.
var _put_away := SaWelcomeWindow.PressElsewhere.new()

## The file that says where the door listens, as a path outside Godot.
var _where: String = ""


func _init(where: String = "") -> void:
    _where = where
    SaPutAway.join(self)
    _init_dialog("LocalServerDialog", tr("Local Server"), Vector2i(520, 280), Vector2i(420, 240))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    # The text scrolls when the host is shorter than it is, so the buttons stay
    # on it, and a long data folder wraps to as many lines as it takes.
    var view := SaMake.scroll(column, "AboutScroll")
    view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
    view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = view
    var body := SaMake.column(view, "About", 10)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var opening := tr("Sara is listening on this computer only, at 127.0.0.1, so nothing on the network can reach it.")
    _wrapping(body, "Listening", opening)
    var file_line := tr("The address, port and access token are in this file. Sara deletes it when the server stops:")
    _wrapping(body, "Where", file_line)
    # Anywhere rather than at a space, because a folder has none to break at.
    _wrapping(body, "File", where).autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
    var notebook := tr("A notebook connects with sara.connect(). A coding agent needs a first message, which the button copies.")
    _wrapping(body, "Notebook", notebook)

    var buttons := pinned_buttons(column)
    var close := SaMake.button(buttons, "CloseButton", tr("Close"))
    close.pressed.connect(hide)
    var tip := tr("Paste it into the agent's conversation. It names the file, never the token.")
    copy_button = SaMake.button(buttons, "CopyPromptButton", tr("Copy Prompt for Agent"), tip)
    copy_button.pressed.connect(copy_prompt)
    default_button = copy_button
    visibility_changed.connect(_on_shown)
    # A `Window` joins the tree already visible, and a show that changes
    # nothing announces nothing, so a dialog added to the tree shown starts
    # hearing here.
    tree_entered.connect(_on_shown)
    tree_exiting.connect(_put_away.stop_hearing)


## Asks every wrapping label for its height again before the base reads the
## body's, for the reason `SaAboutDialog.fit_opening_size` gives: a label a
## level below the scroll keeps the lines of a width of one character.
func fit_opening_size() -> void:
    for label: Node in scrolling_body.find_children("*", "Label", true, false):
        (label as Label).update_minimum_size()
    super.fit_opening_size()


## The paragraph the button copies, for a door that listens.
func prompt_text() -> String:
    return AgentInvite.paragraph(_where, true)


## Puts the paragraph on the clipboard, prints it and says so in the corner.
func copy_prompt() -> void:
    var text := prompt_text()
    clipboard.call(text)
    print(COPIED + text)
    SaMessage.notice(tr("Copied the prompt for an agent. Paste it into the agent's conversation."))


## Whether a door listens anywhere in *tree*, which ticks Modules › Local Server.
static func listening(tree: SceneTree) -> bool:
    return tree != null and tree.get_first_node_in_group(LISTENING_GROUP) != null


## Starts or stops hearing the presses that put the dialog away, as it is
## shown or hidden.
func _on_shown() -> void:
    if visible and is_inside_tree():
        _put_away.hear(self)
    else:
        _put_away.stop_hearing()


func _wrapping(parent: Node, label_name: String, text: String) -> Label:
    var label := SaMake.label(parent, label_name, text)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return label
