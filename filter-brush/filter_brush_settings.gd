## The filter brush's settings: the filter a stroke paints and its parameters,
## with the brush's size, opacity and softness.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A preset of the engine is this resource saved, so every exported field is
## what a preset holds and nothing else is. The filter is held by its registry
## key and its parameters in the record's own units, the pair an attached
## filter keeps, so a preset names a filter the way a `.sad` file does and a
## preset of a filter whose module is gone still loads and says so at the press.
##
## **Each filter keeps its own values while the brush is in hand.** The
## filter's rows are in the Tool Options under the Filter choice, and a painter
## who tries another filter and comes back finds the first one as they left it,
## so a choice of another filter files the parameters under the filter they
## were for and takes up what the new one had. Not exported, since a preset is
## one filter and its values and not a record of every filter tried.
extends Resource

## The engine a preset written from these settings belongs to, which the preset
## store stamps into the file and reads back.
const PRESET_ENGINE: StringName = &"filter"

## The filter a fresh brush paints, the base module's Gaussian Blur, so a brush
## nobody has set up yet does something a painter recognises.
const DEFAULT_FILTER: String = "sara-base-modules.gaussian_blur"

## The format a brush made now is written at, the soft tip's fade. A file with
## no such key is from before it and keeps the fade it was painted with.
const FORMAT_VERSION: int = 1

## The filter's registry key, `<module id>.<filter id>`. A new key files the
## parameters under the old one and takes up the new one's, empty for a filter
## not chosen before. A preset sets the key first and the parameters after it,
## the order the two are declared in, so what it carries is what is painted.
@export var filter_key: String = DEFAULT_FILTER:
    set(value):
        if value == filter_key:
            return
        _kept_by_filter[filter_key] = filter_parameters
        filter_key = value
        filter_parameters = _kept_by_filter.get(value, {})

## The filter's parameters in its record's units, empty for its own defaults.
## Copied whole on every write, because the preset store copies a dictionary by
## reference and a brush that shared one with its preset would edit the preset
## as its sliders moved.
@export var filter_parameters: Dictionary = {}:
    set(values):
        filter_parameters = values.duplicate(true)

## The brush's radius as a fraction of the canvas's smaller side, the unit
## every brush's Radius row and the tool machine's bracket keys speak.
@export var radius: float = 0.04

## How much of the filter's result the centre of the stroke takes, however
## often the stroke crosses itself, zero to one whatever writes it, as the
## stamp brush's opacity is: past one the mix would reach beyond the filter's
## own result, alpha included.
@export_range(0.0, 1.0) var opacity: float = 1.0:
    set(value):
        opacity = clampf(value, 0.0, 1.0)

## How much of the radius the edge fades over, from a hard edge at nought to a
## fade from the centre at one, which for a brush of the format of now is as
## soft as a soft tip's.
@export var softness: float = 0.5

## Whether the pen's pressure scales how much of the filter's result each
## sample lays, through [member pressure_curve], the way the stamp brush's
## opacity takes its pressure. Off at the declaration, which is what a brush
## saved before the brush read pressure loads with, since its file has no such
## key, so it paints as it did. A brush made now is on, [method made_now].
@export var opacity_by_pressure: bool = false

## The pressure in along x and the share of the opacity laid along y, read
## while [member opacity_by_pressure] is on and drawn under it in the Tool
## Options. A straight line from nought to one, so a light touch lays a faint
## filter and a full press the whole of it.
@export var pressure_curve: Curve = straight_curve()

## Which fade the softness draws. Nought, the declaration's, is the smoothstep a
## brush saved before this field lays, which reaches half strength halfway
## across the fade, and [constant FORMAT_VERSION] the soft tip's, a quarter of
## the centre's at most at half the radius when the softness is one. Not a
## field a painter sets: a brush made now carries the format of now.
@export var format_version: int = 0

## The chosen filter and its parameters as one value, which the Tool Options'
## rows of the filter read and write, so a surface that draws them is handed the
## filter with its values, the registry's instance under "filter" or null when
## no installed module offers it. A write names the filter its rows were drawn
## for, and one for a filter no longer chosen is dropped rather than given to
## another.
var filter_page: Dictionary:
    get:
        var named := StringName(filter_key)
        var registry := context.filters if context != null else null
        var filter: SaFilter = registry.get_filter(named) if registry != null and registry.has(named) else null
        return {"filter_key": filter_key, "parameters": filter_parameters, "filter": filter}
    set(page):
        if String(page.get("filter_key", "")) == filter_key:
            filter_parameters = page.get("parameters", {})

## A context carrying the filter registry the key is looked up in, which the
## module hands over. Held through the door rather than as the registry, whose
## class is outside it, and a bare one rather than the module's own, which
## holds these settings back through the tool registry. Not exported, since it
## is the app's and not the brush's, and null on a resource nobody handed one,
## a preset's thumbnail above all.
var context: SaContext = null

## The parameters of every filter chosen before the one in hand, by key.
var _kept_by_filter: Dictionary = {}


## Puts a brush built now at the format of now, with pressure on, and answers
## it, so the module's brush and a fresh tool's are written as
## `FilterBrushSettingsScript.new().made_now()`. Not the declarations' values,
## which a file saved before the pressure and the soft tip takes for every key
## it lacks.
func made_now() -> Resource:
    format_version = FORMAT_VERSION
    opacity_by_pressure = true
    return self


## How much of the opacity a sample laid at *pressure* takes: the whole of it
## with pressure off, and otherwise what [member pressure_curve] reads there.
func strength_at(pressure: float) -> float:
    if not opacity_by_pressure:
        return opacity
    var share := pressure_curve.sample(clampf(pressure, 0.0, 1.0)) if pressure_curve != null else pressure
    return opacity * clampf(share, 0.0, 1.0)


## Whether the softness draws the soft tip's fade rather than the smoothstep
## alone of a brush saved at format nought.
func soft_tip() -> bool:
    return format_version >= FORMAT_VERSION


## A straight curve from nought to one, a fresh brush's pressure curve.
static func straight_curve() -> Curve:
    var curve := Curve.new()
    curve.add_point(Vector2.ZERO, 0.0, 1.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
    curve.add_point(Vector2.ONE, 1.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
    return curve
