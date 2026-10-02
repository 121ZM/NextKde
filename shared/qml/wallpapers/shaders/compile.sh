#!/bin/sh
set -eu
cd "$(dirname "$0")"
QSB=${QSB:-/usr/lib/qt6/bin/qsb}
"$QSB" --qsbversion 64 --qt6 -o physical_scene.frag.qsb physical_scene.frag
"$QSB" --qsbversion 64 --qt6 -o bloom.frag.qsb bloom.frag
"$QSB" --qsbversion 64 --qt6 -o foreground_effects.frag.qsb foreground_effects.frag
"$QSB" --qsbversion 64 --qt6 -o cinematic_blackhole.frag.qsb cinematic_blackhole.frag

"$QSB" --qsbversion 64 --qt6 -o flow_simulate.frag.qsb flow_simulate.frag
"$QSB" --qsbversion 64 --qt6 -o flow_particle.vert.qsb flow_particle.vert
"$QSB" --qsbversion 64 --qt6 -o flow_particle.frag.qsb flow_particle.frag

"$QSB" --qsbversion 64 --glsl "330,300 es" --hlsl 50 --msl 12 -o decode_table.frag.qsb decode_table.frag

"$QSB" --qsbversion 64 --qt6 -o nature_wallpaper.frag.qsb nature_wallpaper.frag

"$QSB" --qsbversion 64 --qt6 -o forest_card_light.frag.qsb forest_card_light.frag

"$QSB" --qsbversion 64 --qt6 -o foreground_clip.frag.qsb foreground_clip.frag

"$QSB" --qsbversion 64 --qt6 -o orbital_ribbon.frag.qsb orbital_ribbon.frag
