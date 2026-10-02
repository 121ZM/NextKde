# Qt Quick 3D depth orbit test

This isolated Qt Quick 3D prototype converts a 16-bit depth map to a textured
triangle mesh once on the CPU, then lets Qt Quick 3D render the orbiting camera
with its depth-tested renderer. A reconstructed background plane sits behind
the mesh and supplies pixels exposed by the orbit. This test does not run in
Quickshell and does not change the production shaders.

The center pixel depth is the camera pivot. Mesh depth is remapped around that
plane: foreground relief is compressed while background relief is expanded,
so the focal region moves less and distant pixels contribute more parallax.
The source mesh is enlarged by 16% while retaining UVs inside the original
image bounds. Camera motion therefore crops into the image instead of sampling
past its edges. The background plane uses the same scale and follows the
farthest generated mesh depth.

```sh
cmake -S experiments/qtquick3d-depth-orbit-poc -B .build/qtquick3d-depth-orbit-poc
cmake --build .build/qtquick3d-depth-orbit-poc -j2
.build/qtquick3d-depth-orbit-poc/qtquick3d-depth-orbit-poc IMAGE DEPTH16 BACKGROUND OUTPUT_DIR
```

On the current Intel Arc system the test window reached about 45 fps at a
1600 x 900 logical size. This is a promising rendering path, but the extra
Qt Quick 3D module is optional in Qt distributions and may not be installed
with every Quickshell build. The current mesh also shows small holes at steep
depth boundaries; the quality of the cached background fill and depth map
still controls the result.
