# GPU depth orbit: ShaderEffect mesh test

This Qt Quick prototype applies a perspective camera orbit in a vertex shader
on a `GridMesh`, sampling the depth texture at each vertex. It is deliberately
separate from the running shell. Build and run with:

```sh
cmake -S experiments/gpu-depth-orbit-poc -B .build/gpu-depth-orbit-poc
cmake --build .build/gpu-depth-orbit-poc -j2
.build/gpu-depth-orbit-poc/gpu-depth-orbit-poc IMAGE DEPTH16 OUTPUT_DIR
```

The test on the current Intel Arc system rendered at about 38 fps at a
1600 x 900 logical window with a 320 x 180 grid. This is substantially faster
than the CPU rasterizer, but `ShaderEffect` does not provide a depth buffer
for this mesh. Depth discontinuities expose holes and jagged subject edges,
so this path is not suitable as the production renderer by itself.
