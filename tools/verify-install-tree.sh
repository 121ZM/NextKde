#!/usr/bin/env bash
# verify-install-tree.sh - gates the `cmake --install` staging tree.
#
# CMake's job in this repo is to COMPILE; user-side deployment of the QML
# trees (shell, shared, shared/qml) is owned by tools/kosctl (deploy_artifacts)
# and the Nix installPhase, which copy from the source tree. So `cmake
# --install` only ever stages the *compiled* artifacts below -- and this script
# proves they all landed. A target that builds but lost its install() rule
# fails the check instead of shipping a binary that the runtime can never find.
#
# The QML trees that CMake does NOT stage are verified separately, end to end,
# by tools/verify-real-install.sh against the deployed user tree (~/.local).
#
# Usage: tools/verify-install-tree.sh <install-prefix>
#   e.g. tools/verify-install-tree.sh .build/staging/usr
#        tools/verify-install-tree.sh "$stage"   # after `DESTDIR=$stage cmake --install`
set -euo pipefail

prefix="${1:?usage: verify-install-tree.sh <install-prefix>}"
prefix="$(cd "$prefix" && pwd)"

failures=0

expect() {
    # expect <description> <path>... - every path must exist
    local description="$1" path missing=0
    shift
    for path in "$@"; do
        if [ ! -e "$path" ]; then
            printf 'MISSING %s: %s\n' "$description" "${path#"$prefix"/}" >&2
            missing=1
        fi
    done
    if [ "$missing" -eq 0 ]; then
        printf 'ok      %s\n' "$description"
    else
        failures=$((failures + 1))
    fi
}

expect_glob() {
    # expect_glob <description> <glob> - the glob must match at least once
    local description="$1" pattern="$2"
    # shellcheck disable=SC2086  # the glob must stay unquoted
    if compgen -G $pattern > /dev/null 2>&1; then
        printf 'ok      %s\n' "$description"
    else
        printf 'MISSING %s: %s\n' "$description" "${pattern#"$prefix"/}" >&2
        failures=$((failures + 1))
    fi
}

# Optional components (apps, pim) are preset-gated: a default or CI build does
# not stage them, so their files are simply not expected. But if the binary IS
# present, the component was built and its full file set must be too -- this is
# what catches a half-wired target (binary installed, desktop/icon forgotten).
component() {
    # component <name> <binary> <companion>...
    local name="$1" bin="$2"; shift 2
    if [ -e "$bin" ]; then
        expect "$name (binary present -> full set required)" "$bin" "$@"
    fi
}

# --- Core artifacts: always staged by `cmake --install` on an install build ---
expect "settings app"          "$prefix/bin/kos-settings"
expect "settings QML"          "$prefix/share/kos/settings/main.qml"
expect "platform daemon"       "$prefix/libexec/kos-platform"
expect "KWin window-bridge JS" "$prefix/share/kos/platform/kwin/window-bridge.js"
expect "data service"          "$prefix/libexec/kos-data-service"
expect "data systemd unit"     "$prefix/share/systemd/user/kos-data.service"

# --- KWin side: two effects, one decoration and the SurfaceShape QML module ---
# lib/qt6/plugins is what KDEInstallDirs resolves on this toolchain; the globs
# tolerate the prefixed, versioned names CMake gives plugin targets.
expect_glob "dock effect plugin"         "$prefix/lib/qt6/plugins/kwin/effects/plugins/"*kos_dock_window_animation*.so
expect_glob "context-menu effect plugin" "$prefix/lib/qt6/plugins/kwin/effects/plugins/"*kos_context_menu_input*.so
expect_glob "liquid-glass decoration"    "$prefix/lib/qt6/plugins/org.kde.kdecoration3/"*kos_liquid_glass*.so
expect "SurfaceShape qmldir"             "$prefix/lib/qt6/qml/Kos/SurfaceShape/qmldir"
expect_glob "SurfaceShape plugin"        "$prefix/lib/qt6/qml/Kos/SurfaceShape/"*kos_surface_shape*.so

# --- Optional apps: binary + desktop entry + icon move together ---
for app in calendar todo weather music; do
    component "kos-$app app" "$prefix/bin/kos-$app" \
        "$prefix/share/applications/kos-$app.desktop" \
        "$prefix/share/icons/hicolor/scalable/apps/kos-$app.svg"
    if [ -e "$prefix/bin/kos-$app" ]; then
        expect "AppStream metadata for kos-$app" \
            "$prefix/share/metainfo/org.nextkde.Kos.${app^}.metainfo.xml"
    fi
done

# --- Optional PIM service: D-Bus activated, run from a systemd user unit ---
component "pim service" "$prefix/bin/kos-pim-service" \
    "$prefix/share/dbus-1/services/org.nextkde.Kos.Pim1.service" \
    "$prefix/share/systemd/user/kos-pim-service.service"

# NOTE: the shell tree (share/kos/shell), the shared contracts
# (share/kos/shared) and the shared QML modules (share/shared/qml) are NOT
# staged by CMake -- tools/kosctl deploy_artifacts and the Nix installPhase
# copy them from the source tree. Their completeness is verified end to end by
# tools/verify-real-install.sh against the deployed user tree, not here.

echo
if [ "$failures" -ne 0 ]; then
    printf 'FAIL: %d install-tree group(s) incomplete\n' "$failures" >&2
    exit 1
fi
printf 'PASS: install tree under %s is complete (compiled artifacts)\n' "$prefix"
