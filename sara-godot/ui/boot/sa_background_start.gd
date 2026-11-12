## Keeps a Sara that a notebook started behind the window the student is in.
##
## A lesson needs only Sara's door and shows its pictures in the notebook, so
## a Sara that opened over the browser would cover the page being read and take
## its keyboard for nothing. `sara.py` adds the flag after `--agent-door` when it
## starts a Sara itself, and this reads it once: the main window goes to the
## taskbar, and nothing at start raises it or asks for attention. From the
## first time the student brings it up it is any Sara. The painter's own starts
## never carry the flag.
##
## An autoload, second after the run log, because the main window is on screen
## from the engine's start and the next autoload loads the script graph, which
## took 5.3 s under the nested weston with the window showing a blank frame all
## that while. The first scene would minimise it only after that. No class name,
## since an autoload's name is its global and the boot preloads this by path.
extends Node

## The user argument that keeps the main window back.
const FLAG := "--in-background"


func _init() -> void:
    apply(OS.get_cmdline_user_args())


## What the start asks of the main window for *args*: `minimised` with the flag
## among them, and `raise` never, since no start of Sara raises its own window
## and one kept back must not be the first.
static func asks(args: PackedStringArray) -> Dictionary:
    return {"minimised": args.has(FLAG), "raise": false}


## Sends the main window to the taskbar when *args* ask for it, and never under
## the headless display server, which has no window. True when they asked.
static func apply(args: PackedStringArray) -> bool:
    if not asks(args)["minimised"]:
        return false
    if DisplayServer.get_name() != "headless":
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED, DisplayServer.MAIN_WINDOW_ID)
    return true
