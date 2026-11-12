## The parts of the Stats docker, one line each, in the order the docker shows
## them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A number joins the docker as a file of its own in this folder that extends
## [SaStatsPart], and as one `preload` here. The docker makes one of each when
## it is built, so every number, and every control that sets how one is
## computed, adds a line to this list and edits nothing else of the docker.
extends RefCounted

const ALL: Array[GDScript] = [
    preload("value_groups.gd"),
    preload("dominant_hues.gd"),
    preload("saturation_by_value.gd"),
    preload("quantizer.gd"),
    preload("coverage_and_edges.gd"),
    preload("session_numbers.gd"),
]
