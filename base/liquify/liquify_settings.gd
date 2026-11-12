## Liquify's settings: the mode, the twirl's direction, the size and the
## strength, which a preset of the engine keeps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Liquify is an engine of the Brush, so its four rows live here rather than on
## the tool state, because a preset is the settings resource saved and loaded
## whole. Every exported field is what a preset holds
## and nothing else is. The mode and the direction are numbered by
## `state_liquify.gd`, which says what each number does.
extends Resource

## The engine a preset written from these settings belongs to, which the preset
## store stamps into the file and reads back.
const PRESET_ENGINE: StringName = &"liquify"

## The brush's width to begin with, in document pixels.
const DEFAULT_SIZE: float = 120.0
## How much of the brush's motion the paint under its centre follows to begin
## with. Half, so a first stroke shows what the tool does without throwing the
## paint past the brush.
const DEFAULT_STRENGTH: float = 0.5

## Push, reconstruct, smooth, twirl, shrink or grow, the tool's `PUSH` to
## `SMOOTH`. Push to begin with, the tool's first mode.
@export var mode: int = 0

## Clockwise or anticlockwise, the tool's `CLOCKWISE` and `ANTICLOCKWISE`,
## which only a twirl reads. Clockwise to begin with.
@export var direction: int = 0

## The brush's width in document pixels. Plain pixels rather than a fraction of
## the canvas, because a warp's reach is a distance on the picture and the
## tool's Size row has always spoken it.
@export var size: float = DEFAULT_SIZE

## How much of the motion the paint under the brush's centre follows, or how
## fast a held mode works there, from nought to one.
@export var strength: float = DEFAULT_STRENGTH
