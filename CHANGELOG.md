# Changelog

## 1.0.0-alpha.1

A document can be an equirectangular panorama, shown as the sky around you and painted in that view. Strokes and filters cross the seam whole, and `.hdr` files open and convert.
The Graph docker shows a picture's Fourier spectrogram and its radial average.
A new Stats docker reads value groups, dominant hues, coverage, edge density, the saturation profile, strokes a minute and mean pressure, and the time spent per tool and per layer. Each row can be turned off alone.
Any paint layer can run a simulation (Spread, Life or Gray-Scott), and a filter can play over time into numbered frames.
New filters: Posterise, Vignette, Laplacian map, Bloom, Chromatic Aberration, Lens Correction, Hot Pixels, Grain, Low Pass, High Pass, Red-eye Removal, White Point, a `.cube` lookup table and a tonemapper layer. The Filters docker browses them and keeps saved looks.
A layer can carry a live transform that the Transform and Crop tools drive and Bake Transform writes.
A mirror layer reads its source's paint alone, and its line is dragged on the canvas.
Image > Colour Space and File > New share one colour space picker, which takes an ICC profile file and keeps the spaces you save.
Docker layouts can hold elements of your own: a composed docker is made on Layouts and dockers, filled on its Elements page, and Reset to shipped undoes its edits.
Load Tip reads GIMP pipes and `.abr` tips, and brushes can use a gradient as their colour source.
The Magnetic Lasso joins the Lasso in the toolbox, and the Colourise layer helps colour line art.
Vector layers draw rectangles and ellipses with a fill and a stroke in float colour through the Shape tool, and the Object tool moves and resizes them.
Sara has a Czech translation, a machine draft marked as not yet reviewed.
A file saved before this release may export a few levels differently where an Effect Layer blurs what its own mirror made, because the blur now reads the mirrored neighbour across a chunk's edge rather than the unmirrored one, and the seam an older build drew there is gone.

## 0.19.1

Filter › Gradient Map lays a colour ramp over a layer's lightness, applied once or attached so it follows the painting.
Ungrouping a filtered group keeps the picture as it was, every texel of it.
A stroke made with the right button, an extra button or a pen's barrel button no longer stops over a docker.
A docker layout you have changed fits the window again after a live change of the interface scale.
The Import Fit dialog names the gamut a PNG or a TIFF says it holds.
A module can register a brush field that runs its own kernel, and ship its own generator kernel for a generated layer.

## 0.19.0

The Welcome window opens on a picture painted in Sara, "Over the ridges", across its top.
The picture's light follows the hour the window opens at: dawn, day, dusk and night, each fading into the next.
A Welcome picture can come in seasons, picked by the month and the country of your locale, the south of the world included. The shipped picture has one season for now.
A document opens on the layer that was active when it was saved.
On Linux, Sara reads the pen's buttons from the kernel, so letting go of the upper button in the air is heard and the next stroke paints. `packaging/install.sh` offers the rule that lets it read them, and never runs `sudo` itself.

## 0.18.0

The noise brush paints one smooth stroke with no dabs in it. Its texture runs along the stroke, the pressure decides how much of it shows, and the tip shapes the edge after that.
The noise brush's randomness changes along a stroke. A bend keeps the holes a straight stroke has, and a light stroke keeps them under a pen that wobbles or rests.
The noise brush's Tip row loads an image tip, picked from a grid of pictures you can filter by folder, which scrolls once it fills.
The first noise stroke after picking a noise preset no longer lags.
Impasto heights go up and down and add together. A stroke moves the surface towards its own height and pushes the old height, and its layer's old colour, ahead of it.
Paint piles at a stroke's edges only under a hard press.
Layer › Rasterise Impasto bakes a layer's relief into its pixels.
The Brush Presets tag filter names each tag alone, and a chosen tag stays chosen.
The mouse's wheel press pans by default, with a binding of its own.
A second touch with the pen's upper button still held erases again.
An open menu gives way to the menu title the pointer moves onto. A press that closes a menu or the Welcome window does not paint.
A right press or Escape during a slider's drag puts the value back.
Modules › Local Server is a toggle, and its dialog copies a prompt for an agent. Opening it leaves the pointer where it is, and a press outside closes the dialog.

## 0.17.4

The Brush Editor's Save As keeps the preset you started from and loads the copy.
A Transform flipped in Mirrored mode keeps the layer's paint, and its box fits the paint with every handle in reach.
The mirror axes stand on two handles you can place anywhere.
A fill seeded on a dark colour leaves empty pixels alone, and it closes small gaps.
Every selection change is an undo step. Shift+Alt intersects, Grow and Shrink are in the Select menu, and a drag inside a selection moves its outline.
The Ellipse selection offers anti-aliasing, and the wand has a Contiguous switch.
Colour Range picks from a click on the canvas, previews, and at its default fuzziness keeps off a neutral ground.
Flip and Rotate work on the image, a layer and a selection. The Edit menu fills and clears a selection.
Paste takes a picture from the desktop clipboard, and Copy puts one there.
An EXR export holds linear sRGB, a JPG export flattens transparency onto one colour, and Export takes its format from the name's extension.
Sara opens TIFF. Save As adds .sad, and warns when the name ends in a picture's extension.
The eyedropper over an empty pixel leaves the colour as it was.
Flatten and Merge Down work over a ground or filter layer at the bottom, and Merge Down merges every selected layer.
Deleting several layers is one undo step, and so is renaming one, which now opens a small dialog.
Moving a layer up or down keeps a group's children together. Isolate Group says what it does.
An attached filter keeps to the selection, its slider edits are undo steps, and its panel leaves when another layer is active.
A layer's attached filters are listed in the order you read a stack, and an adjustment layer is one row named for its filter.
Threshold gives two clean tones on soft edges. Brightness and Contrast span their sliders, and Wrap Offset is centred on zero.
Levels and Curves give a readable histogram with eyedroppers. Invert, Desaturate and Pixelate are in the Filter menu.
Every filter explains itself, and a filter that cannot run on the active layer says why.
No filter writes a broken pixel into the canvas or the colour.
A normal map shows its encoded colour on the canvas.
Soft proof offers a target and shows its effect.
The Colour Lookup opens with a hint, shows only the palette's colours, and blends a pixel between two colours instead of jumping.
Swatches carry names, and removing one can be undone. The hex field commits when it loses the keyboard.
The colour picker's shape is chosen in the docker, and the foreground's alpha is shown or dropped.
The default brush lays the chosen colour in one stroke. Dotted Line and Canvas Scumble draw what their names say.
Shift+click draws a straight line from the last stroke.
The gradient follows your two colours until you edit its ramp, keeps its handles after the release, and stock ramps ship.
Every drawn tip paints its own picture, and a brush pipe loads before the press.
The Pop-up Palette's Eraser gives the blend mode back afterwards.
A shortcut can be cleared, and Back to Sara Default puts every chord back.
The Zoom tool zooms in on a click and out on Shift+click. The zoom reads as the picture's size on screen, and Ctrl+0 does what you set.
Flip View Vertically no longer stalls, and the preset pictures fill quickly again.
A docker's grip keeps its top edge, and a floating docker stops at the window's edge.
Focus mode left on at a close gives the dockers back at the next start.
A Paper layer is named Paper, shows its paper and goes under the paint.
The upper barrel button is told from the tip while Preferences holds the focus.
The Recorder counts frames as taken and says when the video is done.
`sara --version` prints the version and exits.
In a notebook, a cell over an empty layer runs over the canvas, a duplicated layer takes the name asked for, and a change shows when Sara's window comes back. A notebook with no Sara running starts it.

## 0.17.3

Sara ships a painter's own drawn brush tips, a brush on each of the 23, as the bundle "Sara drawn".
Size by pressure follows the pen nearly in proportion.
Tab hides the dockers whatever was pressed last, and with the dockers hidden a change of colour, size or preset is one gesture.
Fit places the painting between the docker columns, and a painting is shown closer at the default zoom.
The size slider takes a typed number and a fine step and says it is a radius. Backspace over a brush slider puts back the preset's value.
The Colour Picker gives its wheel the width and reads in degrees, per cent and 0 to 255. A press on a swatch picks what the wheel edits, and the pair has a swap.
Every control you press carries a tooltip.
Ctrl+Shift+A deselects, and Alpha Lock says when it turns on.
A lasso selection is anti-aliased by default, and one that closes with no area says so. The ellipse selection has a toolbox button of its own.
A press anywhere on a preset tile picks it and puts the brush in your hand. Each tile shows its own stroke, and slash swaps to the preset before.
The Layers docker holds fourteen rows at the default height, with Duplicate, Group, Merge and Mask in its action row. A thumbnail shows dark paint on a checker, a row's toggles and locks read on and off, and a key steps the active layer up and down.
A stroke whose disc covers the canvas paints to the edge, and a stroke that paints nothing says why.
Shift and a drag sizes the brush, and Shift+Space or a pen drag turns the view.
Symmetry and Flip View are two words for two jobs.
The top bar's second row is on and holds every tool option, in the groups Brush, Stroke and View. A choice that does not fit moves to the overflow.
A status line shows the zoom, the size and the colour space, and the View menu hides it.
New Document names the default colour space, offers sizes, picks the background and a ground, and opens from a template or saves one. A picture opens at 16-bit float unless you chose otherwise.
Preferences groups its pages by what you are doing. Its search finds rows by a painter's words and by key, every door to it lands on its row, every number carries its unit, and Reset All asks first.
The thirteen docker pages are one Layouts and Dockers page, and every shipped layout fits its columns at any interface scale.
Every dialog opens inside the window at every size and scale, with its buttons in one row and one order, Cancel first. Escape cancels a dialog once no text field holds the keyboard.
A second dialog opens down and to the right of the first, and Rename Layer and the welcome window open in the middle of the main window.
The Krita profile saves and samples in two steps and keeps the brush slots on Ctrl+Alt digits, and Import from Krita reads every key name Krita writes.
The Krita jobs Sara lacked have commands, every menu command has a row on the shortcuts page, and the page finds a command by its key.
F1 opens the manual.
The frame rate follows the display by default, and a cold start's first frames no longer stall.
The Reference docker opens closed and gives a picture its room, the Info docker leads with the document, and the recorder shows where it writes.
Adjustment and effect layers ask what they hold.
The paper and woven grounds past the document scale with the zoom, and the paper ground has its scale and its other settings.
An impasto eraser flattens the height while it erases.
The patch tool fills from the picture's own texture.
The eyedropper's sample size is a slider on the bar.
Liquify's Smooth evens out any pixels, and over empty canvas it makes nothing and no undo step. An undo during a liquify session closes the session first.
A file dialog opens in the folder it was last left in.
A painter's pink theme ships as a built-in palette, and the welcome window has a Tips tab.
Sara spells every shown word one way, and every settings label says what you get.
A pure primary stored at 16-bit float is shown as itself.
On Windows, a let-out docker dragged with the pen follows it under both drivers, and the start shows no window before its picture is whole.
GIMP opens a pass-through group as Sara draws it, or the export says it will not.
In a notebook, sara.init() connects, opens an sRGB document and reads the whole canvas. A slider is declared with hint_range and reruns the kernel at once, a NumPy slider writes at 30 frames a second, a cell can read a second layer or import a picture as a layer, and the notebook attaches again after the door drops it.

## 0.17.2

Turning the top bar's overflow off no longer hangs or crashes Sara.
The noise brush is one of the Brush tool's engines rather than a tool of its own.
Impasto's relief is drawn half as steep by default. A strength you chose yourself stays.
A text box keeps its own editing keys, so Ctrl+A in the Hex field selects the text and not the picture.
Enter presses the button the outline is on.
A press just after Tab, where a docker stood a moment before, no longer paints on the picture.
A fill with nothing selected says that it filled the whole layer.
Rebinding a key onto one already taken asks first and leaves no key dead, and Start again restores the shipped keymap.
Two filters of one kind attached to a layer are numbered apart.
The eyedropper can pick what the view shows with its filters on.
The Maximize and Hide button switches are set once for every docker.
A group's name in the Layers docker keeps its ellipsis when the list scrolls, and every name Sara shortens ends in an ellipsis.
The About window fits a screen 1024 pixels high, and its address opens the repository.
The FPS graph says Sara is resting instead of falling to zero.
The welcome window stands above the blur while Sara starts.
Reload Modules reads a module of your own the way a start does.
On Windows, the pen's barrel buttons pick with the eyedropper and erase, the ring keeps up with the pointer and follows the pen onto a docker under Windows Ink, a small brush keeps up with the pen, no frame of the start holds the window, a file picker opens at once with a network drive mapped, the corner notice stands above let-out dockers, a summoned docker leaves no ghost, a freeze leaves a line in the log, and a Python script can read a layer and show a picture.
A note taken with the subwindows off notes the row under the pen.

## 0.17.1

Every brush preset carries a star to click, in the Brush Presets docker and in the brush editor, and a Starred toggle above the presets lists only the starred ones, together with the tag and the search. The stars are kept in your profile and never travel in a shared bundle.
A stabilised stroke ends where the pen lifted, even after a fast movement.
Flattening a filter placed after a Dither bakes that filter alone and leaves the Dither attached, still last.
The previews of a Dither in the Filter dialog and in the filter browser no longer repeat the pattern every 256 pixels, so they match what Apply writes.
An attached Levels filter and a Levels adjustment layer graph the picture Equalize reads, instead of the active layer.
The Info docker's FPS row shows a number at rest too, where it used to read "resting".

## 0.17.0

A filter can now become an adjustment layer, which changes everything below it and keeps its settings editable. It runs point filters and blur, and flatten or merge down bakes it in. The Filter dialog offers Bake, Attach or Layer, and Bake stays the default.
Levels has an Equalize button that fills the map from the layer's histogram, in the dialog, on an attached Levels filter and on a Levels adjustment layer.
A Liquify tool pushes, smooths, twirls, shrinks and grows paint.
The hue ring carries grey marks at red, green, blue, cyan, magenta and yellow, and a Keep chroma switch on the Colour Picker's page holds a colour's distance from grey when its hue changes.
The Reference docker can show one picture alone.
Transform has a Mirrored mode, where dragging a corner moves the opposite corner too.
The view's gamut mapping finds the edge of the gamut exactly instead of searching for it.
The Info docker draws a rolling FPS graph.
A group's own filters on a double-resolution layer run at that layer's detail.
New filters: Dither (Bayer, interleaved gradient noise or blue noise), which always runs last, and Wobble, which ripples a layer by a noise field.
An effect layer runs its filters over another layer or group it names, and a scene layer shows a live Godot viewport as the canvas's background.
The noise brush can smudge as the stamp brush does.
Typing a number over the canvas sets the brush opacity.
The dockers' hide button is on by default. A painter who switched it off keeps it off.
An open list beside a menu no longer has the brush ring drawn under it.
A new profile starts painting with a shipped preset, and its ten brush slots come filled.
Every text size follows the theme's font, and each thing has one name wherever it appears.
Menu commands and buttons that would do nothing are disabled, and Welcome opens with nothing empty or dimmed.
Clicking a docker's title bar no longer changes the saved layout.
Preferences fits its pane and opens each page at the top, and its rows say what they do. The file settings have a Files page of their own, and the Colour Spaces page names the default space and scrolls.
Menus show their shortcuts the way the Keyboard Shortcuts page writes them.
For an agent, the door lists its steps when asked, every build carries a guide for agents, and Help › Connect an agent or `--agent-help` gives the first message to send.

## 0.16.3

The HSV and OKHSV hue rings put each colour at the same angle, yellow at the bottom.
Fullscreen is on F11 alone. A shortcut you bound yourself stays as it was.
Gamut Mapping is a view toggle of its own beside Tonemap Highlights, on by default, so a colour pushed below zero maps on screen even with tonemapping off.
The Levels histogram's Lightness channel counts Oklab lightness.
The Patch tool's circle follows the bracket keys and a shift-drag, as a brush does.
Keep blend is a toggle button like the Stabilizer switch, and a rotation typed outside -180 to 180 wraps instead of stopping at the end.
A layer dragged above or below the list lands at that end of it.
The fit dialog's explanations are a size smaller, and the brush presets load after the first frame, so Sara opens sooner.
A live stroke on a masked, clipped or filtered layer at twice the document's resolution shows its detail, and the first dab of a stamp preset reads its paper even with no hover before the press.
A stroke off the canvas stores nothing past its edge.

## 0.16.2

A tidying release, so a painter should see nothing change. Underneath, every file declares its types, the comments were swept again and the checks now hold them, and each test sits beside the feature it tests.
Changing the theme no longer stalls Sara, and five scripted sessions that used to hang now finish.
For a student or an agent, Sara's door speaks plain HTTP, so `curl` alone can start Sara, paint and write the picture out. The step kinds are listed on one generated page.
The Python clients speak HTTP as well, and the old MCP server and line protocol are gone.
A door answer reports the errors since the last answer once each, and says whether a step ran.

## 0.16.1

The magic wand on a painted layer holds up a click for far less time, and waits on the graphics card fewer times per click.
No frame of Sara's start holds the window longer than a third of a second.
A filter section opens beside the Filter menu, and the menu stays open behind it.
A picture opened as a document keeps its picture on its card in the Welcome window.
A stamp preset's texture sensor reads the stamp's own pattern, so a curve on it follows the texture you paint with.
A module can add a brush field through the door, as the three built-in fields now do.
Zoomed in on a layer at twice the document's resolution, a stroke shows its detail while it is painted, and the layer keeps its detail under a mask, a clip and inside an isolated group.
A paint tool that will not paint on a generated layer says why.
Merge down refuses a group or a generated layer, and a duplicate keeps its kind, its members and its mask.
Moving a layer up or down takes a group's members with it, and crop and resample take a group's mask.
Opening a file starts with no selection and none of the last document's module data.
A layer clipped to a generated layer shows, and moving a filter is refused where attaching it would be.
A TIFF too large for the format is refused before it is written, and the transform never hands on a flat matrix.
The palette panel's add chip keeps the panel's own colours, and a lock taken mid-stroke ends the stroke.
For a student, `sara.py` leaves Sara open when it hangs up, the Fourier lab is one undo step, and the door sends its state dump only when asked.
The EXR gradient test carries a value of four and reads it back unclamped.

## 0.16.0

Sara says where its Python door listens, so a notebook or a script attaches to the Sara already open.
`sara.py` is the client a student copies, a layer's pixels cross the door as a `.npy` file, and one step lists the layer stack in a line.
In a notebook, the `%%gmacs` cell magic compiles a kernel from the cell and runs it on the canvas, with sliders for its parameters, and a reduce step sums a layer on the GPU.
An array can live on the GPU between cells, and the Fourier lab and the Voronoi notebook ship as lessons.
The Windows zip starts Sara with its door open, and a student's module runs in the installed build.
The door answers in short verdict lines a small model can read, takes a stroke in document coordinates, fills a polygon or a circle, and reports the engine's errors from inside Sara.
OpenRaster files open with their layers and groups, File, Import takes their layers, and a file Sara writes opens the same elsewhere.
A layer can hold twice the document's resolution: it saves and opens, composites, paints, crops, resizes, takes filters, fills, copies and transforms, and the canvas shows its own detail when zoomed in.
The Bake button brings such a layer back to the document's resolution.
A preset feels the same whatever each painter's own pressure curve, and a Krita preset is read against Krita's own curve.
Ctrl and a click on a layer's thumbnail selects what the layer holds.
Two fingers pan, pinch and turn the canvas, and the pen's barrel buttons can be bound.
While Sara boots, a picture of the last session covers the window with a progress line.
On Windows the first dab of a stroke takes the pen's pressure, a small brush and Sara's ring keep up with the pen, the driver row names the driver in use, and an idle Sara takes under a tenth of a core.
The kaleidoscope dialog fits a 1280 by 1024 screen, a note can be taken on a menu row with the pen, and a docker never turns into a picture that takes no input.
A watery lift stroke ends on its faded tail.
A mask hides a new chunk where it hid the empty canvas, a copy leaves the mask behind, the box blur weighs a colour by its coverage, and the bucket with contiguous off fills every match.
A sweep for faults over the whole tree fixed what it found.

## 0.15.0

A new brush, the noise brush, paints from a texture that decides where the paint goes, so a stroke never shows its dabs.
Its texture is one of three fields, bristle, grain or a picture, and it drifts along the stroke, warps the tip, and moves the hue and saturation with it.
Every slider of the noise brush has a randomise slider beside it, per stroke or per dab.
Leaning the pen widens the noise brush like a real one, and a fast stroke drags its texture further.
A first shelf of noise brush presets ships, and a stamp brush preset converts to the noise brush and back.
A lift-up setting thins the paint towards the end of a stroke like water, on both brushes.
Paint has height: a paint layer can carry it, thick paint builds towards a ceiling, and the canvas shows the relief under a light.
The paper lends its tooth to the relief and thick paint buries it, and a woven canvas ground that never repeats can be picked in the layer's properties.
Smudging moves the height with the colour, and a transform or a copy and paste carries the height too.
An export shows the relief the canvas shows.

## 0.14.1

On Windows the pen paints where the pen is: Sara starts on the Wintab driver, and the driver is a choice in Preferences.
Text is sharp at every interface scale, not only at one.
The numpad chords of the palette work, a dropdown closes on its own button, and a full undo history no longer throws a pop-up.
The brush's blend mode offers every mode, and the two fill chords fill.
The fill, the magic wand, the gradient, a transform's commit, a smudge's first stroke and attaching or applying a filter no longer stall, and the first stroke of a session does not wait for its shaders.
Sara shows its welcome window before the rest of the boot, and the welcome window closes once a document is made or opened.
When the top bar has no room, its second row overflows behind an arrow instead of growing another row, and dropdowns open inside the window.
A summoned docker can be locked open, stays where a drag drops it, and the cursor is right over a docker that is a window of its own.
A docker that is a window of its own no longer sinks behind the main window on Windows, and Sara's dialogs stay above it.
The kaleidoscope's mirror count has a control a pen can reach.
Closing a filter window cancels it, Attach is an option inside the filter dialog, and filters are sorted into sections.
Brightness and contrast no longer turn a colour negative, and their step buttons move the picture as well as the number.
The waveform counts every pixel it shows.
An export follows the tonemapper, and a recent document shows its picture after a close.
Undoing back to where the document was saved clears the modified mark.
The top bar, the tablet page and the default layout fit a 1280 pixel screen, and the interface scale row names the scale on screen.
A fast pencil stroke is solid, spatter paints down to the document's bottom edge, and a shipped preset's dab fills its ring at full pressure.
A smudge dab costs the processor no more than a paint dab, and Sara left idle uses under a tenth of a core instead of half.
A freeze leaves a line in the log that says where Sara was.
Sara has a Windows build of its own, made from the repository.

## 0.14.0

A fast stroke follows a curve between the pen's samples rather than a chain of straight pieces.
Sara composites only what the window shows, so a zoomed-in canvas paints and pans with less work.
Switching tools is quicker: nothing is read from disk, the top bar refits only when its controls change, and the tool options docker follows without reloading the layout.
A Performance page in Preferences gathers what costs the GPU, with one switch for a light mode that composites the view at half size while it moves.
A weak GPU is offered the light mode once, at start.
The New document dialog says what one full layer of the chosen size and depth costs in memory.
Help opens a painter's manual inside Sara, with pages on painting, presets and colour, layers, selections and filters, the tablet, saving and shortcuts.
A picture exports as OpenRaster with its layers, and an exported PNG or TIFF names its author and its date.
The export menu and a painter hint name every format Sara writes.
A Krita preset's texturing mode paints the way Krita paints it, and a masking brush carries its own flow, rotation and scatter and composites the way its preset says.
A pipe tip the importer refuses now says why, and re-importing a bundle offers to replace what came from it before.
Painting a mask with a dark brush hides the layer under it.
An attached filter can be taken off from the minus button or the row's menu.
A colour picked with the eyedropper joins the recent colours.
A double click renames the layer row it lands on, and a layer row that cannot act is dimmed and refuses a press.
The E key ticks the erase row, a stroke no longer marks a loaded preset as changed, and the magic wand's merged option no longer names the eyedropper.
Opening a file no longer hands the layers docker a layer that is already gone.

## 0.13.0

Layer masks: add one to a layer or to a group, paint it with any brush, and the layers docker shows it beside the thumbnail.
A mask can be inverted, switched off, applied, deleted, made from a selection or turned back into one, each a single step you can take back.
Filters attach under a layer or a group and stay editable for as long as the document lives, so a blur you set on Monday can be changed on Tuesday.
Attached filters are listed under their layer in the layers docker, reordered by dragging, switched off one at a time, and flattened into the pixels when you are ready.
An attached filter carries a mask of its own, so it can be painted in and out.
A click on a filter opens its controls in the tool options docker rather than in a dialog, and a double click on the row does the same.
The usual filters ship in the base modules: add noise, denoise three ways, sharpen and unsharp mask, Gaussian, motion and lens blur, threshold, edge detection, height to normal map, bump map, and a wrap offset for painting tileable textures.
Colour range picks a colour, takes a fuzziness and selects every texel within it.
A kaleidoscope ships as a module of its own beside the box blur.
Gamut mapping sits beside the tonemapper on the Display page.
Modules, Reload picks up a module you changed on disk without restarting Sara, and rebuilds its layers, filters and menus with it.
Any docker can be summoned under the pointer with a chord and goes again when you move away, and a pop-up palette does the same for the brush slots.
Changing the shortcut profile no longer changes the colour picker with it.
Letters typed into a number field no longer write the minimum.
A boot without ffmpeg no longer prints an error, and the tooltip says what is missing.

## 0.12.1

A refactoring release: the tree behind Sara moved into packages and almost nothing on screen changed.
The six adjustments under Filter (brightness and contrast, hue, saturation and lightness, curves, levels, colour balance and the palette) are now filters of the base module, with the same dialogs, live preview and one history step, and a module's filter can bring its own widget and a keyboard chord.
The Preferences pages are built from one declarative layer, so every page searches, lays out and scales the same way, and a locked theme shade stays locked when another row moves.
The sample modules are named box blur and hard mix, and nothing in the program names the course they were once called after.
The alpha is a debug export, so a crash prints the script frames it died in, and the notes export carries the engine's log.
A recent document shows its picture on the welcome window again.
A dialog opens large enough to show its own buttons, and Alt with the right button resizes a docker towards any corner.
An export to PNG or TIFF keeps a bright colour the view had rolled off.
The filter browser opens no taller than the screen.
The top bar's second row keeps its controls in the first row's order.
The tool options docker lists a brush's dynamics in the order of its pages.
A Krita bundle imported while the gradient tool is active no longer writes a brush into the gradient's settings.
A tooltip that was left showing over the reference bar goes with the pointer.
Sara measures itself: a profiling scenario and a committed baseline of boot time, per-stroke dispatch counts and VRAM, which the next refactoring reads.

## 0.12.0

A welcome window opens at start: your recent documents as thumbnails with their dates, quick settings, and the news.
When a session ended badly, the recovery offer is the top row of the recent pane.
The welcome window can be turned off, and Help brings it back.
Quick settings hold the UI scale, the colour theme, the pressure calibration and the embedded subwindows switch, the same controls Preferences holds.
The changelog ships inside the build, and the News pane shows what changed since the version you last ran.
Testers can zip a session's notes from the News pane and send them.
PNG and TIFF export at 16 bits, between the 8-bit and the float exports, and the dialog remembers the depth per format.
A 16-bit PNG comes back at full depth on import.
Twenty basic brushes ship with Sara, among them an airbrush, a pencil, charcoal, a chisel marker, a wash, two smudge brushes, two erasers, a halftone, a spatter and a masked stipple.
A new version adds the presets it brings and leaves the ones you deleted deleted.
Every preset bundle carries its licence, shown in the cell's tooltip and in the docker.
Bundles and papers shipped inside a module install at first run.
Krita presets import more faithfully: pipe tips, the lightness map of a colourful tip, the lightness and height texturing modes, the masking brush's size and strength dynamics, and smudge radius and dulling.
Sample merged is a toggle, so a brush reads either the visible stack or the active layer alone.
A Settings menu opens the display profile, tablet and shortcuts pages, and the dockers and layouts move under Window.
A layer has a rename dialog that carries its note, and a right press on a layer row opens its menu.
Loading a palette asks whether to replace the swatches or add to them, and the palette can be cleared.
A saved document carries a preview, drawn in the document's true colours.
Every factor slider keeps its trailing noughts again, so 1.00 reads as 1.00.

## 0.11.1

The bar's buttons no longer take the keyboard, so Space pans the canvas the moment you press it.
The brush size slider now reaches below one pixel, on a logarithmic scale.
Holding Ctrl+Z repeats undo, so a long press steps back through history quickly.
The presets docker lays out correctly on its first open, not only after a resize.
The Info docker now shows the version, the commit and the build date.
The learned cursor lead, the gap between pen and ring, is a Preferences row that trains itself, Auto by default.
A second click on an open dropdown closes it instead of reopening it.
A secondary workspace can leave the app window as a native OS window.
The UI scale follows whichever monitor a window sits on.

## 0.11.0

The masking brush: a second tip breaks the dab into a scatter of smaller marks, with its own size and spacing.
Pipe tips, the animated multi-image brushes Krita calls .gih, now import and play their cells.
The smudge brush picks up colour and carries it along the stroke, held on the GPU.
Colour dynamics: hue, saturation, value, darken and mix can each follow a sensor.
Papers arrive: GIMP .pat patterns and four built-in grains, with brightness, contrast and a cutoff.
Two texturing modes, multiply and subtract, let a paper press into the paint differently.
A fan mode throws dabs around an unlocked corner.
Ten brush slots put your favourite presets one chord away.
Flow and Opacity become one slider on the bar.
Export carries the document's colour profile into PNG, JPEG and TIFF.

## 0.10.1

The toolbox no longer switches itself to a grid at narrow widths.
The brush ring follows the pointer with far less lag.
Levels now reads like Photoshop's histogram.
Cropping can grow the canvas, and the zoom stays where it was.
A dragged tool can leave its group in the toolbox.
Preset tags can be made, renamed and removed.
A light Paper White palette ships alongside the dark ones.
Deleting a preset or a palette asks first.
The reference docker accepts a file dropped from the file manager.
The grid can go down to one pixel, and the CIE diagram is now a proper horseshoe.
Tooltips appear without a click, and menu titles are drawn at a readable size.

## 0.10.0

Levels works like Photoshop's, with a live histogram.
The patch tool heals a spot in one undoable step.
Brushes can paint through a paper pattern, and the pattern is a resource of its own.
The smudge brush reads a merged snapshot of the stack.
The Reference docker keeps a picture beside the canvas, and both graphs follow it.
Krita preset bundles import, mapping their options onto Sara's.
The colour picker gains HSV square, triangle and HSL shapes.
Cropping clears everything outside the rectangle.
Ctrl+Space maximises the focused docker.

## 0.9.1

Mostly internal: long files were cut by responsibility rather than by length, and the wand and gradient tools moved out of the core. Nothing on screen changed.

## 0.9.0

Scripting arrives: a module can now ship a filter that appears in the Filter menu.
A pixel function wrapper turns a short script into a filter with generated sliders.
A box blur module ships as a template for writing your own.
A first-hour guide walks a student from an empty document to a running filter.

## 0.8.3

The cursor can show the ring and the system pointer together.
Escape cancels an edit without closing the window.
The Presets button toggles on a second press, and presets show their defaults.
Filling a layer converts through the document's colour space, so the colour lands as you picked it.

## 0.8.2

Mostly internal: Sara's shaders moved to a Python-shaped dialect that compiles to the same output, with a formatter and a grammar. Nothing on screen changed.

## 0.8.1

Holding the size brackets repeats, so the brush grows and shrinks smoothly.
Space pans reliably, even after clicking a button on the bar.
Backspace resets a slider to its default.
The Presets button opens the docker rather than a cramped menu.
Dragging across the eye icons toggles several layers at once.
The image tip's outline follows the cursor.
Editing a docker layout forks a preset instead of rewriting the shipped one.
The pen settings row is on by default.

## 0.8.0

The brush engine and its dynamics land: sensors, curve options, a brush editor and live preset thumbnails.
The toolbox folds into five categories with a flyout.
The Flood Fill tool fills a region on the GPU.
Image Size resamples every layer in one undoable step.
Pressing H mirrors the canvas.
The Undo History docker lists the steps you can step back through.
The Eraser now removes paint instead of painting it.
The minimap can proof in grayscale.
The first stroke no longer paints nothing at zero pressure.

## 0.7.0

The Transform tool arrives with translate, scale, rotate and shear.
The Reference docker opens a picture beside the canvas with its own zoom and pan.
TIFF export ships, and the gradient tool remembers its colours.
The colour picker gains numeric sliders and a stretched triangle.
Colour Balance adjusts shadows, midtones and highlights.
New Document defaults become a preset you can pick.
Five docker layout presets ship, and editing one forks a copy.
Soft proofing simulates a narrower gamut.
Layers can be grouped and collapsed.

## 0.6.0

A Display page in Preferences chooses the view transform.
The Info docker shows colour rows and splits its stats into sections.
Every docker gets a hide button.
Marching ants now spread evenly along the selection edge.
The brush size brackets are discoverable, and their shortcuts work from a saved profile.
A font-size slider joins the UI scale control.
