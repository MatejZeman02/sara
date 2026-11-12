## The pen read from Linux itself: the kernel's node for the tablet's pen,
## read on a thread, so the upper barrel button's release in the air is heard
## where Godot's Wayland driver loses it (godotengine/godot#124067).
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It registers one pen source through the door, which the tool machine asks
## before it presumes the upper held, and does nothing anywhere the driver does
## not lose the button: another platform, or Linux under X11 or XWayland, where
## the upper already arrives as the middle button. Pressure, tilt and which
## device moved stay Godot's for now.
extends SaModule

const PenNode := preload("pen_node.gd")

## Names the node to read in place of looking for one, `--pen-node=<path>`,
## after the `--` of the command line. It is how a capture shows the module
## refusing a node the user may not read, on a machine where the real nodes
## are readable or absent.
const NODE_FLAG := "--pen-node="

var _pen: PenNode = null


func get_id() -> StringName:
    return &"linux_pen"


func get_name() -> String:
    return "Linux Pen"


func register(ctx: SaContext) -> void:
    if not wanted(OS.get_name(), DisplayServer.get_name()):
        return
    _pen = PenNode.new(named_node(OS.get_cmdline_user_args()))
    ctx.register_pen_source(_pen)
    _pen.start()


func unregister(_ctx: SaContext) -> void:
    if _pen != null:
        _pen.stop()
        _pen = null


## Whether the module has anything to do on *platform* under the display
## *driver*: Linux under Wayland, the one place the upper is lost.
static func wanted(platform: String, driver: String) -> bool:
    return platform == "Linux" and driver == "Wayland"


## The node *args* name with [constant NODE_FLAG], or empty.
static func named_node(args: PackedStringArray) -> String:
    for arg: String in args:
        if arg.begins_with(NODE_FLAG):
            return arg.substr(NODE_FLAG.length())
    return ""
