# synth/nangate45_upstream.v — provenance

## Source

Vendored 2026-10-09 from `~/workspace/dft-trial/lib/NangateOpenCellLibrary.v`
(present on this machine from an earlier project; itself sourced from the
Nangate 45nm Open Cell Library distribution).

- sha256: `7b80af03f2ed72d40f014b836b13526aff3f64105415587c74f2260588b74363`
- Size: 220307 bytes, 134 cell modules, 60 UDP primitives.
- The file is copied **byte-identical**; do not edit it. Regenerate provenance
  (not content) if the source changes.

## Why this file (F4 SDF flow)

The project's generated models (`synth/nangate45_cells.v`) are zero-delay
functional models with no `specify` blocks, so SDF back-annotation has
nothing to attach to. These upstream models carry `specify` blocks in
125/134 cells (the 9 without — ANTENNA/FILLCELL_x/LOGIC0_X1/LOGIC1_X1 —
have no timing arcs, correctly omitted) plus `$setuphold` timing checks in
the sequential cells. Path delays default to 0.1 placeholders, which the SDF
overrides with real liberty-derived values at `$sdf_annotate` time.

## License terms (from the file header — preserved, not modified)

```
// *                   Copyright (C) 2004-2010, Nangate Inc.                    *
// *                           All rights reserved.                             *
// * Nangate and the Nangate logo are trademarks of Nangate Inc.                *
// * All trademarks, logos, software marks, and trade names (collectively the   *
// * "Marks") in this program are proprietary to Nangate or other respective    *
// * owners that have granted Nangate the right and license to use such Marks.  *
// * You are not permitted to use the Marks without the prior written consent   *
// * of Nangate or such third party that may own the Marks.                     *
// * This file has been provided pursuant to a License Agreement containing     *
// * restrictions on its use. This file contains valuable trade secrets and     *
// * proprietary information of Nangate Inc., and is protected by U.S. and      *
// * international laws and/or treaties.                                        *
```

**Note for the maintainer:** this header asserts proprietary restrictions.
The Nangate 45nm Open Cell Library is widely distributed and used in
open-source flows (including OpenROAD's own test suite), but if the
repository is ever made public, confirm the distribution terms cover this
file before pushing it. The SDF flow documents this as a known item; the
file is required for delay-annotated simulation and has no functional
substitute in the open-source flow.
