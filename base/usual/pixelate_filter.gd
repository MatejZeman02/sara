## Filter > Pixelate, the picture as square blocks of one colour each.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `pixelate.gmacs`: every texel takes the texel at
## the centre of its block, and the blocks are laid from the document's corner,
## so they line up across chunks and do not move when the painter strokes beside
## them. The first filter of the Pixelate section, which the base module had
## registered empty.
##
## The pass declares a radius of the block size, as the row asked, and the
## dispatch grows by that ring round the dirty rectangle and no more (hard rule
## 2). It holds every read with room to spare, because the centre is never more
## than half a block from a texel of its block, and nothing is averaged: the
## colour and the alpha are the centre's.
class_name SaPixelateFilter
extends SaFilter

const SHADER := "sara-base-modules/pixelate"
const KERNEL := "pixelate"
const DEFAULT_BLOCK := 8
## The largest block a typed value may ask for, in document pixels. It is the
## radius too, and a gather reaches one chunk of the layer, which is 256
## document pixels at any resolution, so the largest block is gathered whole.
const HARD_BLOCK := 256


func title() -> String:
    return "Pixelate"


## Listed under Pixelate in the Filter menu and the browser.
func family() -> StringName:
    return &"pixelate"


func sentence() -> String:
    return "Cut the picture into square blocks, each filled with the colour at its centre."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Block size", 2, 64, DEFAULT_BLOCK, {"hard_max": HARD_BLOCK, "suffix": " px"})


func run(ctx: SaFilterContext) -> void:
    var block := clampi(int(parameter(&"block_size")), 1, HARD_BLOCK)
    ctx.neighbourhood_pass(SHADER, KERNEL, {"block": float(block)}, reach(block))


## The radius a block of *block* pixels declares: the block itself, as the row
## asked, twice the half block that reaches the centre from its farthest texel.
static func reach(block: int) -> int:
    return block
