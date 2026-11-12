## What an exported picture says about itself: who painted it, when it was
## written and which program wrote it.
##
## Written in the two formats whose writers Sara owns, a PNG's `iTXt` chunks,
## spliced in by [method SaExportGamut.png_with_text], and a TIFF's tags 305,
## 306 and 315, written by the TIFF writer of the image formats module, which
## reads this record through the door. A JPEG goes through Godot's encoder
## and an EXR has no writer of Sara's own, so neither carries it.
##
## **Each date is in its format's own form, never the locale's.** A PNG's
## Creation Time is the RFC 1123 date the PNG specification suggests, with the
## offset of the clock it was read off, and a TIFF's `DateTime` is the fixed
## `YYYY:MM:DD HH:MM:SS` of TIFF 6.0, which has no place for a zone and so is
## the local clock, as every camera and editor writes it. Both are the same
## instant, read once when the metadata is made.
##
## An empty author is no author: the entry is left out rather than written
## empty, so a reader shows nothing instead of a blank name.
##
## **Where the painter lives** is written only when Preferences > Files has
## "Write the location into exported pictures" ticked. It is
## the country, under tzdata's long name, and the place the painter typed, as
## XMP's `photoshop:Country` and `photoshop:City`, in a PNG's `iTXt` chunk
## keyed `XML:com.adobe.xmp` and a TIFF's tag 700. XMP rather than a text
## chunk of Sara's own, because a reader such as `exiv2 -pa` lists a PNG's XMP
## and passes over its plain text. With the box off, or with neither a country
## nor a place, there is no packet at all.
class_name SaExportMetadata
extends RefCounted

## The `iTXt` keywords, as the PNG specification spells its predefined ones.
const KEY_AUTHOR: String = "Author"
const KEY_CREATION_TIME: String = "Creation Time"
const KEY_SOFTWARE: String = "Software"
## The keyword XMP's specification gives its packet in a PNG.
const KEY_XMP: String = "XML:com.adobe.xmp"

## RFC 1123's names, indexed by what `Time` answers: the weekday from Sunday at
## zero, and the month from January at one.
const WEEKDAYS: Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS: Array[String] = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## The painter's name, stripped, and empty for none.
var author: String
## The moment of the export, in seconds since the Unix epoch.
var unix_time: int
## How far the local clock ran ahead of UTC at that moment, in minutes, so a
## date can be written as the painter's clock read it.
var zone_minutes: int
## The program and its version, as the TIFF writer always wrote it.
var software: String
## The painter's country by its long name, and the town they typed, stripped,
## each empty for none.
var country: String
var place: String


## A record for an export by *author_name* at *at_unix_time*, read off a clock
## *at_zone_minutes* ahead of UTC, made in *in_country* and *at_place*. Given
## rather than read, so a suite can hold a date to the character.
func _init(
    author_name: String = "", at_unix_time: int = 0, at_zone_minutes: int = 0, in_country: String = "", at_place: String = ""
) -> void:
    author = author_name.strip_edges()
    unix_time = at_unix_time
    zone_minutes = at_zone_minutes
    software = "Sara %s" % SaBuildInfo.version()
    country = in_country.strip_edges()
    place = at_place.strip_edges()


## The record of an export made now, by whoever the Preferences row names, and
## where they live when the location box is ticked: the country set there or,
## with Automatic, the guessed one.
static func now() -> SaExportMetadata:
    var zone := Time.get_time_zone_from_system()
    var in_country := ""
    var at_place := ""
    if SaSettings.location_in_exports:
        in_country = SaLocation.country_here()
        at_place = SaSettings.location_place
    return SaExportMetadata.new(
        SaSettings.export_author, int(Time.get_unix_time_from_system()), SaTyped.int_at(zone, "bias", 0), in_country, at_place
    )


## The `iTXt` entries a PNG carries, as keyword and text pairs in the order
## they are written, with no Author pair when there is no author.
func png_entries() -> Array[PackedStringArray]:
    var out: Array[PackedStringArray] = []
    if not author.is_empty():
        out.append(PackedStringArray([KEY_AUTHOR, author]))
    out.append(PackedStringArray([KEY_CREATION_TIME, png_creation_time()]))
    out.append(PackedStringArray([KEY_SOFTWARE, software]))
    var packet := xmp()
    if not packet.is_empty():
        out.append(PackedStringArray([KEY_XMP, packet]))
    return out


## The XMP packet naming the country and the place, or empty when there is
## neither. A bare `x:xmpmeta` with one description, which is the least a
## reader takes, and every value escaped, since a town may be called
## Smith & Sons.
func xmp() -> String:
    if country.is_empty() and place.is_empty():
        return ""
    var fields := ""
    if not country.is_empty():
        fields += ' photoshop:Country="%s"' % _escaped(country)
    if not place.is_empty():
        fields += ' photoshop:City="%s"' % _escaped(place)
    return (
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        + '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        + '<rdf:Description rdf:about="" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"%s/>' % fields
        + "</rdf:RDF></x:xmpmeta>"
    )


## RFC 1123, section 5.2.14, with a numeric zone: `Wed, 23 Sep 2026 21:04:05
## +0200`. The names are English whatever the locale, because the RFC's are.
func png_creation_time() -> String:
    var local := Time.get_datetime_dict_from_unix_time(unix_time + zone_minutes * 60)
    var ahead := "+" if zone_minutes >= 0 else "-"
    var offset := absi(zone_minutes)
    return (
        "%s, %02d %s %04d %02d:%02d:%02d %s%02d%02d"
        % [
            WEEKDAYS[SaTyped.int_at(local, "weekday", 0)],
            SaTyped.int_at(local, "day", 0),
            MONTHS[SaTyped.int_at(local, "month", 0)],
            SaTyped.int_at(local, "year", 0),
            SaTyped.int_at(local, "hour", 0),
            SaTyped.int_at(local, "minute", 0),
            SaTyped.int_at(local, "second", 0),
            ahead,
            floori(offset / 60.0),
            offset % 60,
        ]
    )


## TIFF 6.0's `DateTime`, exactly nineteen characters: `2026:09:23 21:04:05`.
func tiff_date_time() -> String:
    var local := Time.get_datetime_dict_from_unix_time(unix_time + zone_minutes * 60)
    return (
        "%04d:%02d:%02d %02d:%02d:%02d"
        % [
            SaTyped.int_at(local, "year", 0),
            SaTyped.int_at(local, "month", 0),
            SaTyped.int_at(local, "day", 0),
            SaTyped.int_at(local, "hour", 0),
            SaTyped.int_at(local, "minute", 0),
            SaTyped.int_at(local, "second", 0),
        ]
    )


## *text* safe inside an XML attribute in double quotes.
static func _escaped(text: String) -> String:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
