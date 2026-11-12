# Icons

Every icon the UI uses must live here. `SaUI.get_icon()` looks in this folder and
nowhere else: it deliberately does not fall back to the editor's `EditorIcons`
theme, because that theme is stripped from exported builds, so an icon reached
that way works while developing and silently disappears in a release.

`ui/themes/tests/test_icons.gd` holds the list of names the UI asks for and fails if any of
them stops resolving. Add the name there when you add an icon.

## Authoring

- Draw on a **16x16 grid**, matching the existing set: `viewBox="0 0 16 16"`.
- Drawn for Sara and released under its GPLv3. Some names follow the names of
  Godot's editor icons, because the interface once fell back to the editor's
  theme, and the shapes are Sara's own.
- 1px stroke, monochrome/symbolic, in the style of Krita or GNOME symbolic icons.
- Fill `#e0e0e0`. The UI does not recolour icons yet, so the source colour is
  what ships.
- No baked shadows or gradients.

## Import settings

The `.import` sidecars are committed, and they matter: icons are rasterised at
`svg/scale=4.0` (so a 16px icon becomes a 64px bitmap) with mipmaps on. The UI
then draws them at roughly 20-40px depending on display scale, so they are always
scaled *down*, which stays sharp. At `svg/scale=1.0` they were upscaled 2.5x on a
4K display and looked soft.

If you add an icon, check its generated `.import` has `svg/scale=4.0` and
`mipmaps/generate=true` before committing.
`ui/themes/tests/test_every_icon_is_rasterised_at_four_times.gd` fails the run on
one that does not, since `gradient.svg` and `crop.svg` once shipped at
one times.

## Naming

Lookup tries the lowercased name first, so a caller passing `"Paint"` and one
passing `"paint"` resolve to the same `paint.svg`. Names are otherwise literal:
there is no alias table, so `brush.svg` is not found by a caller asking for
`"Paint"`.

## Present

Tools: `paint`, `bucket`, `eraser`, `colorpick`, `toolpan`, `zoom`
Docker title bars: `wrench`, on the Toolbox
Layers: `tooladdnode`, `quad`, `duplicate`, `clear`, `lock`, `unlock`,
`guiminicheckerboard`, `guivisibilityvisible`, `guivisibilityhidden`, and
`group`, `merge_down` and `layer_mask` on the action row's buttons, drawn for Sara on the same grid
Title bar: `window_minimize`, `window_maximize`, `window_close`
Brush options: `size_pressure`, `opacity_pressure`
History: `undo`, `redo`, the bar's Undo and Redo, a hooked arrow back and one
forward, drawn for Sara on the same grid
Symmetry: `symmetry_horizontal`, `symmetry_vertical`, the bar's pair, an axis
between a shape and its reflection, drawn for Sara on the same grid
Preset stars: `star`, `star_outline`, on every preset cell and the chooser's Starred filter
Docker pins: `pin`, `pin_outline`, on every docker's bar, drawn for Sara on the
same grid
Reference: `folder_open`, `fit_view`, `normalize`, `solo` and `easel`, the
docker's five buttons on its tabs' row, drawn for Sara on the same grid
Reference hover bar: `greyscale`, a half filled circle, beside `symmetry_horizontal`,
`crop` and `pin`, the four toggles over a picture
Arrows: `chevron_down` and `chevron_right`, the Layers docker's kind button,
a group row's fold mark and the Recorder's and brush editor's folds, and `swap`
and `reset`, the Colour Picker's pair and the top bar's rotation reset, drawn
for Sara on the same grid. They were characters in the
buttons' text, which some shipped faces lack and drew as a box, so a symbol is
an icon here and never a glyph, and
`ui/themes/tests/test_no_glyph_is_missing_from_a_face.gd` fails the run on
a string under `ui/` that a shipped face cannot draw
Cursors: `cursor_rotate`, the curved arrow the Transform's pointer turns into
beside a corner, where a press would turn the box. A pointer
is read over paint of any colour, so unlike the rest of the set it has a
second colour, a dark rim round the set's fill, which keeps the arrow visible
on a white canvas as well as a dark one. A cursor is named `cursor_` first,
since it is drawn for over the canvas and is not a button's glyph: the top
bar's rotation is still a word because the set has no `rotate` icon
Layer rows: `visualshadernodecomment`, a speech bubble, the mark of a layer
with a note, and `container`, a layer held over a bar, the clip toggle. Both
names are Godot's and are asked for capitalised, which the lookup lowercases
Top bar toggles: `infinite_canvas`, an infinity sign, `double_resolution`, a
drawn 2x, and `wrap`, a grid of nine hollow cells, over which the Wrap icon
fills the cells its wrap fills (`wrap_all` and `wrap_sides` went away
with the menu that showed them)
Selection: `select_subject`, a person inside a dashed frame, a copy of the one
the Select Subject module carries in its own folder
The icon review put in 18 drawings the icon review of 2026-10-22 made,
twelve over old ones (`bucket`, `clear`, `container`, `ellipse_select`,
`guivisibilityhidden`, `lasso`, `liquify`, `patch`, `relief`, `toolpan`,
`visualshadernodecomment`, `wrench`) and the six above that were new. The
hidden eye is drawn in the set's fill with a slash, never dimmed, since a
dimmed control reads as disabled
Unused, kept for future use: `tools`

The cursor drawings of the same review, `arrow` and `hand`, a pointer and an
open hand, each an SVG and a 24 pixel PNG, are here as well, over the two
pictures of those names that were removed. They are 24 by 24 in two colours, a dark
rim round the set's fill, as `cursor_rotate` is. Nothing loads them yet: the
Pan tool keeps the system's hand shape and the canvas's own arrow is drawn as
geometry in `ui/canvas/cursor_overlay.gd`.

`tools` was the Toolbox's title glyph until the Toolbox asked for a wrench. It is kept
rather than deleted because it is a perfectly good spanner-and-screwdriver and a
module wanting one has nowhere else to reach, and `ui/themes/tests/test_icons.gd` still
holds the name so it cannot quietly stop resolving.
