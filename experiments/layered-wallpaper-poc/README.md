# Layered wallpaper proof of concept

This standalone C++/OpenCV experiment uses a wallpaper and its 16-bit depth
map. It requires no new model or Python. A
depth-guided GrabCut mask isolates the subject. OpenCV extends the surrounding
background inward and softens the fill boundary. The renderer moves background
and foreground at different speeds. A third
color-selected grass layer covers the animal's lower edge where it meets the
real foreground grass.

The `raccoon` and `ironman` foreground seeds are tuned to those photos. They are a
visual proof, not a reusable segmentation model or production asset contract.
No Quickshell or platform code loads these artifacts.

```sh
cmake -S experiments/layered-wallpaper-poc -B .build/layered-wallpaper-poc
cmake --build .build/layered-wallpaper-poc -j2
.build/layered-wallpaper-poc/layered-wallpaper-poc raccoon|ironman IMAGE DEPTH_PNG OUTPUT_DIR
.build/layered-wallpaper-poc/layered-wallpaper-poc assets IMAGE BACKGROUND MATTE INFLUENCE OUTPUT_DIR
```

Outputs are `foreground.png`, `background.png`, `mask.png`, `hand-mask.png`,
`hand-influence.png`, `grass-mask.png`,
and 1920×1080 `left.jpg`, `center.jpg`, and `right.jpg` preview frames. The
`frames/` folder contains a 72-frame left/right loop; encode it with:

```sh
ffmpeg -framerate 24 -i OUTPUT_DIR/frames/frame_%03d.jpg -c:v libx264 \
    -pix_fmt yuv420p -crf 18 -movflags +faststart OUTPUT_DIR/preview.mp4
```

For the raccoon, the background moves 0.3% and foreground 2% per axis at the
end positions, creating 1.7% relative movement. For Iron Man, clouds move
0.5% opposite the body's 2% movement; the extended hand adds up to another
1%. The hand is identified from depth, then its displacement is smoothed over
the wrist and shoulder so that fingers move together. This is a photo-specific
motion field, not a reusable hand segmentation or depth renderer. The previews
reserve 3.5% and 5% crops per edge, respectively. Small halos remain where
the hidden clouds are estimated behind the subject.
