## The settings of where the painter lives: the country and its zone the
## Welcome picture's sun stands at, the town an export may name, and whether an
## export names any of it.
##
## The Location row stands in Preferences beside the Author information, with a
## switch for whether the exported picture's metadata names it. A file of its
## own and a family because the four are one subject: where the painter is.
##
## **It is a link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsShapeCheck` extends this extends
## `SaSettingsMemory`, so `SaSettings.location_country` is the property below and
## not a forward to it. It adds no signal, because [signal
## SaSettingsImporting.changed] is the one the rest of the chain shares.
##
## None of it is ever written into a `.sad` document. The document's writer
## reads none of these, and an export reads them through `SaExportMetadata`.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsLocation
extends SaSettingsMemory

## The country the painter lives in by its two capitals, `CZ`, or empty for
## Automatic, which keeps `SaLocation`'s guess from the time zone. Anything that
## is not two capitals is Automatic.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## reads Automatic, which is what a new one has.
var location_country: String = "":
    set(val):
        val = val.strip_edges()
        if val.length() != 2 or val != val.to_upper():
            val = ""
        if location_country == val:
            return
        location_country = val
        changed.emit(&"location_country")

## Which of the country's zones, a tzdata name, when its zones keep different
## clocks, and empty for its first. `SaLocation.chosen_place` reads a zone that
## is not the country's as empty.
var location_zone: String = "":
    set(val):
        val = val.strip_edges()
        if location_zone == val:
            return
        location_zone = val
        changed.emit(&"location_zone")

## The painter's town or region as typed, empty by default. Written into an
## export beside the country when the box below is ticked, and never read for
## the sun.
var location_place: String = "":
    set(val):
        val = val.strip_edges()
        if location_place == val:
            return
        location_place = val
        changed.emit(&"location_place")

## Whether an exported PNG or TIFF names the country, and the place when one is
## given. Off by default, since where a painter lives is theirs to give away.
var location_in_exports: bool = false:
    set(val):
        if location_in_exports == val:
            return
        location_in_exports = val
        changed.emit(&"location_in_exports")
