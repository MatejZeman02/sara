## The scroll a docker puts between its window and the column inside it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own file, and not a block in either docker, because two dockers want the
## same eight lines and the same paragraph of reasoning.
##
## **Why a scroll and not a taller window.** `DockerWindow` has a
## `column_min_height` and deliberately leaves the enforcement out: flooring a
## window at its column's minimum would make the Recorder and the Toolbox two
## and a half times taller, a change to what the painter sees rather than a
## repair. A scroll costs the painter nothing: content that would be drawn under
## the resize grip and clipped away is reachable by scrolling, and the window
## keeps its size.
##
## **Vertical only, always.** A docker column is a stack of full-width rows and a
## sideways scroll on one is a way to lose a row rather than to reach it. The
## Toolbox's grid also reflows with the docker's width already, so a horizontal
## scroll would be a second answer to a question the reflow has answered.
## `ScrollContainer` still passes a disabled axis's minimum up, so the width
## `DockerWindow.enforce_column_minimum` floors is still floored. Reached by path
## from both dockers rather than by `class_name`, so no editor rescan of the
## class cache stands between a fresh checkout and a docker that lays out.
@tool
extends RefCounted


## Puts *content* inside a vertical scroll and that scroll into *column*, where
## *content* was going to go. Returns the scroll, named `Scroll`.
##
## The docker's own path lookups then read `.../Scroll/<content>`, which is a
## change each docker makes for itself: a helper that silently reparents
## something a docker looks up by path would break the lookup from a distance.
static func wrap(column: Container, content: Control) -> ScrollContainer:
    var scroll := SaMake.scroll(column, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(content)
    return scroll
