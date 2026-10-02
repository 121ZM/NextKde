# Depth mesh preview

This standalone C++/OpenCV experiment compares the current wallpaper shader
math with a textured depth mesh. It uses existing wallpaper and 16-bit depth
files. It does not run inside Quickshell and does not modify the live desktop.

The mesh lifts pixels onto camera rays using relative depth, rotates a
perspective camera around the depth at image center, rasterizes triangles with
a z-buffer, and fills small disocclusion gaps with OpenCV inpainting. Triangles
that cross a large depth discontinuity are omitted to avoid stretching a
foreground object into the background. The result is a diagnostic prototype,
not a production renderer: it uses a single-valued depth surface, an assumed
depth range, a fixed center focus, and small view angles.

```sh
cmake -S experiments/depth-mesh-poc -B .build/depth-mesh-poc
cmake --build .build/depth-mesh-poc -j2

.build/depth-mesh-poc/depth-mesh-poc IMAGE DEPTH16 OUTPUT_DIR
.build/depth-mesh-poc/depth-mesh-poc IMAGE DEPTH16 OUTPUT_DIR \
    BACKGROUND MATTE INFLUENCE
```

When scene layers are supplied, `baseline-*.jpg` renders the current layered
shader reference. Without layers, it uses the current depth shader reference.
`mesh-*.jpg` contains the depth mesh result. Five pointer poses are emitted,
including both horizontal extremes and two corners. `metrics.csv` records
render time and triangle coverage for each pose.

## First comparison (1600 x 900, CPU)

The prototype was run on the current dog wallpaper, the Iron Man wallpaper,
and a mountain landscape. See `.build/depth-mesh-poc/{dog,ironman,mountain}/`
for frames and per-pose metrics. The dog and Iron Man baselines use their
existing cached scene layers; the mountain baseline uses the current depth
shader reference.

The camera orbit does produce perspective changes around the center, with
depth-dependent displacement and z-buffer occlusion. The dog and Iron Man
show useful foreground/background separation. The ordinary mountain scene
has much weaker perceived depth because its depth map assigns similar depths
to large parts of the image. That is a depth-estimation/content limitation,
not something camera orbit alone can fix. The mesh avoids some flat-plane
parallax behavior, but the single-depth-surface model still cannot reveal
plausible hidden surfaces; its small holes are filled with generic inpainting.

On this CPU implementation, mesh frames took about 0.32-0.41 seconds each
(roughly 2.4-3.1 fps), with 97-100% raster coverage. This confirms the
geometry approach as a visual experiment, not as a real-time implementation.
A production trial should move mesh projection/rasterization to the GPU and
keep depth-aware inpainting/material preparation outside the frame loop.

## Stable foreground A/B

For the dog and Iron Man scene-layer assets, `*-ios/` also contains an
art-directed variant beside the current shader reference. It reduces
foreground travel from 0.8-1.2% to 0.15-0.25%, raises reconstructed-background
travel from 0.3% to 2.8%, and gives the background a stronger perspective
term. The subject stays steadier while the distant scene shifts more, which
matches the intended iOS-like feel better in these still comparisons. It is
an artistic depth response rather than a physically exact camera orbit.

The A/B stills suggest lower subject-edge shimmer risk, but moving the
background farther makes crop margin and background reconstruction more
important. The production shader has not been changed by this experiment.
