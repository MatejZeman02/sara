## A blend mode as data, so a module (or the user) can add one.
##
## Data rather than a closed list, so a mode a module registers reaches every
## dropdown the built-in modes do.
class_name SaBlendModeDescriptor
extends RefCounted

## How the mode behaves outside the 0-1 range, where a scene-linear document's
## colours live.
enum Domain {
    ## Well defined on unbounded linear data: over, add, multiply, difference.
    ARITHMETIC,
    ## Formula assumes 0-1 (screen, overlay, soft light, the Oklab family), so it
    ## is evaluated against the document's blend reference white W:
    ##     out = W * f(src / W, dst / W)
    DISPLAY_REFERRED,
}

## Stable ID, persisted in .sad files. Never renamed.
var id: StringName

var display_name: String = ""

## What the mode does to paint, in one line of plain English, shown on the hover
## of its row in the blend list and on the dropdown that shows it.
##
## Here for the same reason a command carries its own: the list is drawn in the
## bar, in Tool Options and in the Layers docker from one control, and a module's
## mode is explained the way a built-in's is. It is what tells the Normals apart,
## which the names alone did not: on an Oklab document the list held "Normal
## (Oklab)" and "Oklab Normal" a few rows apart, two modes that differ, and a row
## whose hover said only its own name.
##
## Written for both places the mode is picked, so it speaks of the colour on top
## and the paint underneath rather than of a layer or a brush. Empty is allowed
## and leaves the row saying its own name.
var sentence: String = ""

## Shader that owns the kernel. Modules ship their own .gmacs.
var shader_name: String = "composite"

## Kernel name, resolved to an index at registration through
## GlobalShaderCompiler.get_kernel_index(). Never an ordinal from the caller.
var kernel_name: String = ""

var domain: Domain = Domain.ARITHMETIC

## The sections a blend menu shows, in the order it shows them, as
## `[id, title]`. Krita's groups, with the two Sara has that Krita does not:
## Erase is its own section because a painter switches to it all day, and the
## three explicit Normals sit with Normal.
##
## The last one is where a mode with no category of its own lands, which is
## every mode a module registers without saying anything about grouping. An
## unknown category is treated the same way rather than opening a section of
## its own: a menu cannot show a section it has no title for.
const SECTIONS: Array = [
    [&"normal", "Normal"],
    [&"erase", "Erase"],
    [&"darken", "Darken"],
    [&"lighten", "Lighten"],
    [&"contrast", "Contrast"],
    [&"comparative", "Comparative"],
    # Hue, Saturation, Colour and Lightness. "Component" is what the group is
    # called in the literature, "Colour" is what it is called on screen.
    [&"component", "Colour"],
    [&"other", "Other"],
]

const CATEGORY_OTHER: StringName = &"other"

## Grouping in the menu: one of the ids in [constant SECTIONS]. The default is
## the one every other descriptor in the API uses for "unsaid", and it is not a
## section, so a mode that leaves it alone is shown under Other.
var category: StringName = &"general"

## Ordering within a category.
var sort_order: int = 0

## Hidden from the layer dropdown (Erase is a brush concept, not a layer one).
var hidden_in_layer_list: bool = false

## Never offered in any menu, layer or brush.
##
## Stronger than [member hidden_in_layer_list], which is for a mode a painter
## still picks from the bar. An internal mode is one the app selects on its own
## behalf: the alpha lock a wash stroke commits with is a rule about how a
## stroke lands rather than a mode anyone chooses, so it registers through the
## same public door as every other mode and stays out of the two dropdowns.
var internal: bool = false

## True for a mode with no blending space of its own, which mixes in whatever the
## document stores. Plain Normal is the only one: Porter-Duff is a lerp and a lerp
## is well defined wherever the values live, so it never has to convert.
##
## A dropdown appends the document's space to such a mode's label, because "Normal"
## alone does not say whether it is about to mix encoded RGB, light or perceptual
## coordinates, and those give visibly different results.
var follows_document_space: bool = false


## The label a dropdown should show for this mode in a document of *space*.
##
## Identical to [member display_name] for every mode with a space of its own,
## which is all of them but one.
##
## **The bracket is a fact about the document and not a name**, so nothing with a
## space of its own may be called `Normal (<space>)` or the menu draws two rows
## in the same words. The three pinned Normals lead with their space for that
## reason, `Oklab Normal` beside plain Normal's `Normal (Oklab)`, and
## `core/api/color/tests/test_ledger_returns.gd` fails the run if any two registered modes
## ever collide on any space Sara can make.
func label_for(space: SaColorSpace) -> String:
    if not follows_document_space or space == null:
        return display_name
    return "%s (%s)" % [display_name, space.blend_space_name()]


## What the hover of this mode's row says in a document of *space*: the label,
## and under it [member sentence] when there is one.
##
## The label leads because the dropdown on the bar clips it, and its hover is the
## one place the whole of a long Normal is read. A mode that follows the document
## names the space it mixes in today, the bracket's own fact in words, so the
## hover of plain Normal and of the pinned Normal it equals still read apart.
func tip_for(space: SaColorSpace) -> String:
    var label := label_for(space)
    if sentence.is_empty():
        return label
    var said := sentence
    if follows_document_space and space != null:
        said += " On this document it mixes in %s." % space.blend_space_name()
    return "%s\n%s" % [label, said]


## Optional extra GPU resources this kernel binds beyond the canvas and chunk
## textures, as { binding: int -> RID }. Declared and still not bound: no mode
## has needed an image of its own yet, and [member extra_buffers] is the door
## the first customer walked through.
var extra_textures: Dictionary[int, RID] = {}

## Storage buffers this kernel binds beside the canvas and the chunk, as
## { name -> RID }, the name being the one its `.gmacs` gives the `buffer`
## line. The compositor binds every entry by that name before each dispatch of
## the mode, so the kernel's numbering stays the file's business.
##
## A mixing module's table is the first customer: a blend that needs
## a fitted model is a blend with side data, and the push constant is spent on
## the composite block. The descriptor carries the RID only, so the module
## holds the `SaCompute.Buffer` that owns it for as long as the mode is
## registered, or the dispatch reads a freed buffer.
var extra_buffers: Dictionary[String, RID] = {}

var owner_module: StringName = &""

## The ids this mode was saved under before it was renamed, newest first.
##
## [member id] is what a `.sad` records, so renaming a mode changes what an old
## painting looks like: the registry answers nothing for the id in the file and
## the compositor falls back to Normal without a word. A mode that names its
## former ids here keeps those documents, because the registry files each one as
## an alias and rewrites the layer on load.
##
## Empty for every mode that has never been renamed, which is all of them but
## one. An alias is not a second name a painter can pick: it never reaches a
## menu, and the id a save writes is always [member id].
var former_ids: Array[StringName] = []


## The section id this mode belongs in: its own when [constant SECTIONS] has
## one by that name, and Other when it does not.
func section() -> StringName:
    for entry: Array in SECTIONS:
        if entry[0] == category:
            return category
    return CATEGORY_OTHER


## The title a menu writes above a section, or an empty string for an id no
## section carries.
static func section_title(section_id: StringName) -> String:
    for entry: Array in SECTIONS:
        if entry[0] == section_id:
            return entry[1]
    return ""


static func create(mode_id: StringName, kernel: String, shader: String = "composite") -> SaBlendModeDescriptor:
    var descriptor := SaBlendModeDescriptor.new()
    descriptor.id = mode_id
    descriptor.kernel_name = kernel
    descriptor.shader_name = shader
    descriptor.display_name = String(mode_id).capitalize()
    return descriptor
