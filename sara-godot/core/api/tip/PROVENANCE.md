# What the tips owe Krita, the one port in the door

The tip, its mask, the pipe and the tip image were the stamp brush's before
they moved into the door, so that any engine that lays dabs, the
noise brush first, shapes them through the same classes a third party's engine
would. One of the four carries a port of Krita 5.2.13, and its copyright lines
moved here with it from
[the stamp brush's page](../../../modules/sara-base-modules/stamp-brush/PROVENANCE.md),
which keeps the two ports the module still holds and says why the lines live
on a page rather than in headers.

**Krita 5.2.13 is `GPL-2.0-or-later` throughout the sources below.** That
permits relicensing upwards, and Sara is `GPL-3.0-or-later`, so a port carries
the original lines unmodified beside Sara's own identifier. The file below
carries `SPDX-License-Identifier: GPL-3.0-or-later` and a pointer to this page.

What was read rather than taken is recorded in the Provenance table of the
brush engine's specification, whose port row this is. That specification is part of the maintainers' design notes and is not
carried in the public source.

## The ports

**One port in one file, and no others.** A port added later adds a section
here in the same commit. `tests/test_dynamics_provenance.gd` reads this page
beside the dynamics page and fails the moment a file under `core` or
`ui/brush_editor` carries a line neither grants, and the stamp brush's
`tests/test_provenance.gd` holds the three pages' counts together to the spec
tables' port rows.

### `res://core/api/tip/sa_tip_image.gd`

The greyscale mask rule, `(255 - red) * alpha`, which turns a loaded tip image
into coverage. Read from `libs/brush/kis_brush.cpp` and `libs/brush/kis_brush.h`.
The characteristic size that shares the row is Sara's own: a tip has no
size of its own here, because the Size row is the diameter and the kernel samples
the mask at the dab's own inverse transform.

```
SPDX-FileCopyrightText: 1999 Matthias Elter <me@kde.org>
SPDX-FileCopyrightText: 2003 Patrick Julien <freak@codepimps.org>
SPDX-FileCopyrightText: 2004 Adrian Page <adrian@pagenet.plus.com>
SPDX-FileCopyrightText: 2004-2008 Boudewijn Rempt <boud@valdyas.org>
SPDX-FileCopyrightText: 2005 Bart Coppens <kde@bartcoppens.be>
SPDX-FileCopyrightText: 2007 Cyrille Berger <cberger@cberger.net>
```
