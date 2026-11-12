# What the patch tool's Texture method keeps of Krita's Smart Patch

The patch tool's Texture method, `patch_match.gmacs` and `sa_patch_match.gd`
beside this page, was written for the GPU from the two papers its headers
name: PatchMatch (Barnes, Shechtman, Finkelstein and Goldman, SIGGRAPH 2009)
and the completion of Wexler, Shechtman and Irani (IEEE PAMI 2007). It was read
against Krita 5.2.13's Smart Patch tool,
`plugins/tools/tool_smart_patch/kis_inpaint.cpp`, which runs the same pair on
the CPU. No line of that file is copied: its loops walk scanlines, and these
are four kernels over a pyramid with no order between texels.

What the two files keep of Krita's are its numbers, and the stamp brush's
[`PROVENANCE.md`](../../stamp-brush/PROVENANCE.md) already holds the rule for
those: a tuned constant a rewrite from the idea would not arrive at is carried
with the lines of the file it came from, which is why `pattern_modes.gmacs`
owes Krita's lines for the three and two of hard mix softer. The same
holds here.

- **The similarity curve**, `0.5 - 0.5 tanh(k (d - 0.1))` with a value of 0.999
  at a distance of nought, `SA_PM_HALF` and `SA_PM_STEEPNESS` in
  `patch_match.gmacs`. Krita's `init_similarity_curve` has `s_zero = 0.999`
  and `t_halfmax = 0.10`.
- **The distance's scale**, the mean squared difference per channel in 0 to 1,
  with a texel past the level or of the hole on the source side costing the
  most, in `sa_pm_distance`.
- **The floor under a vote**, `VOTE_FLOOR` in `sa_patch_match.gd`, which
  `patch_match_vote` reads, Krita's `if (wsum < 1)`.
- **The patch radius of four**, `RADIUS`, Krita's default. The pyramid's
  stopping rule is Sara's own, a level a patch wide where Krita stops at the
  radius, and owes nothing.
- **The rounds per level**, `min(2k, 4)` rounds of search and vote and
  `min(5, 1 + k)` search passes a round, Krita's `iterEM` and `iterNNF`, in
  `rounds_at` and `passes_at`.

**Krita's file is `GPL-2.0-or-later`**, which permits relicensing upwards, and
both files here carry `SPDX-License-Identifier: GPL-3.0-or-later` beside the
line below, as the stamp brush's port does. Krita's header also names "Original
author Xavier Philippeau" and "Code adopted from: David Chatting
https://github.com/davidchatting/PatchMatch". Chatting's repository carried no
licence file when it was read. Nothing here is taken from either
past what Krita's file holds under Krita's licence, so that chain is Krita's to
answer for, and it is written down for whoever reads the release's licences
after a clone.

## The lines

### `res://modules/sara-base-modules/base/patch/patch_match.gmacs`

```
SPDX-FileCopyrightText: 2017 Eugene Ingerman
```

### `res://modules/sara-base-modules/base/patch/sa_patch_match.gd`

```
SPDX-FileCopyrightText: 2017 Eugene Ingerman
```
