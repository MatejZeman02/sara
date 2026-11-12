## One part of the Stats docker: a number, or a few controls, with the rows it
## shows and the reduction it computes them by.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A file of its own and one line of the list.** Every number joins the docker
## the same way, so that no two of them edit one function: a script in this
## folder that extends this class, and one `preload`
## in `stats_parts.gd`. The docker makes one of each when it is built, asks
## each to [method declare] its rows on the docker's page after its own switch
## and line, and registers each one's [member reduction] with `SaReductions`
## while it is open with its switch on.
##
## **A part that reduces nothing leaves [member reduction] null.** The
## quantizer's controls work with the switch off, and a number read off the
## session log has nothing to dispatch, so both are parts like any other and the
## service never hears of them.
##
## **No callable that holds the part.** A part holds its reduction, so a
## reduction that holds the part back, through a lambda that reads `self` or an
## argument bound to it, is a cycle of two `RefCounted` that nothing frees. A
## kernel's push constant is packed by a static function, or by a method passed
## as `_push` and not wrapped in a lambda, which holds the part by its id alone.
class_name SaStatsPart
extends RefCounted

## What the service runs for this part, or null for a part that reduces
## nothing. Set in the part's own `_init` and never replaced, because the docker
## registers the one it read when it was built.
var reduction: SaReductionService.Reduction = null


## Declares the part's rows on *page*, in a section of its own or more, after
## the docker's switch and the line saying when the numbers were computed.
## Called once, when the docker builds its page.
func declare(_page: SaPage) -> void:
    pass


## Writes what the last run found into the part's rows. Called after every run
## of the docker's computing, and again each time an answer the device handed
## back later is folded into [member reduction]'s total. *surface* is the front
## surface the docker found, or null before it has one, as in a suite.
func refresh(_surface: SaSurface) -> void:
    pass
