## The modules a build ships switched off, by id: what a fresh profile's
## Preferences > Modules starts with, and what a reset puts back. The painter
## switches any of them on there, and the next start loads it.
##
## A module is on this list when few painters reach for it and its start costs
## the rest of them something. Each id says why it is here. The skeleton is
## never on it, and the loader never files it as off whatever the list says.
##
## A module that is off has its script left unread at the start as well as its
## registration skipped, which is where the time comes from: the script graph of
## a module is compiled before a line of it runs.
class_name SaOffByDefault
extends RefCounted

const IDS: Array[String] = [
    # A controller on the desk is rare, and the module listens for one from
    # the start.
    "midi",
    # Numbers about the picture for the painter who asks for them, and the
    # third dearest module of a start to register, 62 ms on a desktop GPU.
    "sara-stats",
    # A filter for the painter who looks for it rather than one most reach
    # for, so it waits in Preferences > Modules until switched on.
    "kaleidoscope",
]


## The list as the setting holds it, a fresh copy so a caller cannot edit the
## build's own.
static func ids() -> Array:
    var copy: Array = []
    copy.assign(IDS)
    return copy
