## Times a shortcut profile switch by its parts. Private to the Keyboard
## Shortcuts page's folder, which starts one for each switch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A switch has been seen to take half a minute and a minute on Windows with
## nothing saying where the time went. Each part is
## entered on the trail, so a stall line names the part that was running, and
## the switch prints one line with every part's milliseconds, so a slow switch
## on a machine nobody here can reach names its cause in the log.
class_name SaShortcutSwitchTimer
extends RefCounted

## The line a switch prints, the profile, the whole and the parts.
const LINE := "a shortcut profile switch to %s took %d ms: %s"

var _profile: String
var _began: int = Time.get_ticks_usec()
var _since: int = 0
var _name: String = ""
var _ticket: int = SaTrail.NOTED
var _parts: PackedStringArray = []


func _init(profile: String) -> void:
    _profile = profile


## Ends the part under way and begins *what*.
func part(what: String) -> void:
    _close()
    _name = what
    _since = Time.get_ticks_usec()
    _ticket = SaTrail.enter("the shortcut profile switch, %s" % what)


## Ends the last part and prints the line.
func done() -> void:
    _close()
    print(LINE % [_profile, int((Time.get_ticks_usec() - _began) / 1000.0), ", ".join(_parts)])


func _close() -> void:
    if _name.is_empty():
        return
    _parts.append("%s %d ms" % [_name, int((Time.get_ticks_usec() - _since) / 1000.0)])
    SaTrail.give_back(_ticket)
    _name = ""
