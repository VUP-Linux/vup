# Vuru local mode: official Void binaries, recursively built VUP dependencies.
# This runs in the xbps-src driver, using evaluated templates (not text parsing).

vuru_official_repositories() {
    local machine="$1" file suffix= line
    if [ -s "$XBPS_DISTDIR/etc/xbps.d/repos-remote-${machine}.conf" ]; then
        file="$XBPS_DISTDIR/etc/xbps.d/repos-remote-${machine}.conf"
    else
        case "$machine" in *-musl) suffix=-musl ;; esac
        file="$XBPS_DISTDIR/etc/xbps.d/repos-remote${suffix}.conf"
    fi
    # Only the tree's official repository definitions, never host/custom VUP repos.
    while IFS= read -r line; do
        case "$line" in
            repository=*)
                line=${line#repository=}
                if [ -n "$XBPS_MIRROR" ]; then
                    line="${XBPS_MIRROR}${line#*/current}"
                fi
                printf '%s\n' "$line"
                ;;
        esac
    done < "$file"
}

vuru_dependency_template() {
    local name="$1" path
    if [ -f "$XBPS_SRCPKGDIR/$name/template" ]; then
        printf '%s\n' "$XBPS_SRCPKGDIR/$name/template"
        return
    fi
    for path in "$XBPS_SRCPKGDIR"/*/"$name"/template; do
        if [ -f "$path" ]; then
            printf '%s\n' "$path"
            return
        fi
    done
    return 1
}

vuru_dependency_stack() {
    local failed="$1" chain="${XBPS_DEPENDS_CHAIN#, }" entry name
    local root="${XBPS_VURU_ROOT_PKG:-${pkg:-unknown target}}"
    if [ -s "$XBPS_VURU_LOCAL_BUILD_STATE/failed_chain" ]; then
        chain=$(cat "$XBPS_VURU_LOCAL_BUILD_STATE/failed_chain")
        chain="${chain#, }"
    fi
    printf '\nVuru dependency stack:\n' >&2
    if [ "$failed" = "$root" ]; then
        printf '  %s  [FAILED target]\n' "$failed" >&2
        return
    fi
    printf '  %s  [target]\n' "$root" >&2
    if [ -n "$chain" ]; then
        while IFS= read -r entry; do
            entry="${entry# }"
            name="${entry%%(*}"
            if [ -n "$name" ] && [ "$name" != "$root" ] && [ "$name" != "$failed" ]; then
                printf '  -> %s  [dependency]\n' "$name" >&2
            fi
        done < <(printf '%s\n' "$chain" | tr ',' '\n')
    fi
    printf '  -> %s  [FAILED dependency]\n' "$failed" >&2
}

vuru_record_dependency_failure() {
    local failed="$1" marker="$XBPS_VURU_LOCAL_BUILD_STATE/failed"
    if [ ! -s "$marker" ]; then
        printf '%s\n' "$failed" > "$marker"
        printf '%s\n' "$XBPS_DEPENDS_CHAIN" > "$XBPS_VURU_LOCAL_BUILD_STATE/failed_chain"
    fi
    # Direct policy tests have no root driver to report the recorded failure.
    if [ -z "$XBPS_VURU_ROOT_PKG" ]; then
        vuru_dependency_stack "$failed"
    fi
}

# Resolve/build a dependency. Official results are pinned to the queried version;
# diagnostics/build output go to stderr so the caller can collect the expression.
vuru_prepare_dependency() {
    local dep="$1" cross="$2" machine="$3" query="$4" name template source key
    local repo official_version parent="${sourcepkg:-${pkgname:-${pkg:-unknown}}}" child_chain
    local -a repos
    while IFS= read -r repo; do repos+=(--repository "$repo"); done < <(vuru_official_repositories "$machine")
    [ ${#repos[@]} -gt 0 ] || { msg_error "No official repositories for $machine\n" >&2; return 1; }
    if official_version=$($query -i "${repos[@]}" -R -ppkgver "$dep" 2>/dev/null); then
        [ -n "$official_version" ] || return 1
        echo "   [Vuru] $dep: official Void binary ($machine)" >&2
        printf '%s\n' "$official_version"
        return
    fi

    name=$(xbps-uhelper getpkgdepname "$dep" 2>/dev/null)
    [ -n "$name" ] || name="$dep"
    template=$(vuru_dependency_template "$name") || {
        msg_error "VUP dependency '$dep' has no local template and no official binary\n" >&2
        vuru_record_dependency_failure "$name"
        return 1
    }
    # setup_pkg handles subpackages, category paths and conditional template values.
    source=$( (setup_pkg "$name" "$cross"; printf '%s' "$sourcepkg") ) || {
        vuru_record_dependency_failure "$name"
        return 1
    }
    key="$XBPS_VURU_LOCAL_BUILD_STATE/$machine-${source//\//_}"
    if [ ! -f "$key.done" ]; then
        if [ -f "$key.active" ]; then
            msg_error "VUP dependency cycle at $name ($machine)\n" >&2
            vuru_record_dependency_failure "$name"
            return 1
        fi
        : > "$key.active"
        echo "   [Vuru] $dep: building VUP dependency locally ($machine)" >&2
        child_chain="$XBPS_DEPENDS_CHAIN, $parent(${cross:-host})"
        (
            setup_pkg "$name" "$cross"
            [ "$XBPS_CHECK_PKGS" == full ] || unset XBPS_CHECK_PKGS
            export XBPS_DEPENDENCY=1 XBPS_BUILD_FORCEMODE=1
            export XBPS_DEPENDS_CHAIN="$child_chain"
            exec "$XBPS_LIBEXECDIR/build.sh" "$sourcepkg" "$pkg" pkg "$cross"
        ) >&2 || {
            rm -f "$key.active"
            XBPS_DEPENDS_CHAIN="$child_chain"
            vuru_record_dependency_failure "$name"
            return 1
        }
        rm -f "$key.active"
        : > "$key.done"
    fi
    printf '%s\n' "$dep"
}

# Installs into the build root/sysroot only. Include locally built repositories
# and official binaries, excluding remote VUP repositories even if configured.
vuru_install_build_dependencies() {
    local cross="$1" machine="$2" repo cmd="$XBPS_INSTALL_CMD"
    shift 2
    [ $# -gt 0 ] || return 0
    [ -z "$cross" ] || cmd="$XBPS_INSTALL_XCMD"
    local -a repos
    repos+=(--repository "$XBPS_HOSTDIR/binpkgs")
    for repo in "$XBPS_HOSTDIR"/binpkgs/*; do
        [ ! -d "$repo" ] || repos+=(--repository "$repo")
    done
    while IFS= read -r repo; do repos+=(--repository "$repo"); done < <(vuru_official_repositories "$machine")
    $cmd -i "${repos[@]}" -Ay "$@"
}

vuru_install_pkg_deps() {
    local pkg="$1" targetpkg="$2" cross="$4" cross_prepare="$5" dep resolved
    local -a host_deps target_deps
    [ -d "$XBPS_VURU_LOCAL_BUILD_STATE" ] || { msg_error "Missing Vuru local-build state\n"; return 1; }
    skip_check_step && unset checkdepends
    for dep in $hostmakedepends $checkdepends; do
        resolved=$(vuru_prepare_dependency "$dep" "$cross_prepare" "$XBPS_MACHINE" "$XBPS_QUERY_CMD") || return 1
        host_deps+=("$resolved")
    done
    for dep in $makedepends; do
        resolved=$(vuru_prepare_dependency "$dep" "$cross" "$XBPS_TARGET_MACHINE" "$XBPS_QUERY_XCMD") || return 1
        target_deps+=("$resolved")
    done
    # setup_pkg_depends includes subpackage runtime dependencies and virtuals.
    local runtime_names
    runtime_names=$(setup_pkg_depends "" 1 1) || return 1
    for dep in $runtime_names; do
        # Dependencies on the source package's own subpackages need no recursion.
        case " $pkgname $subpackages " in *" $dep "*) continue ;; esac
        vuru_prepare_dependency "$dep" "$cross" "$XBPS_TARGET_MACHINE" "$XBPS_QUERY_XCMD" >/dev/null || return 1
    done
    vuru_install_build_dependencies "$cross_prepare" "$XBPS_MACHINE" "${host_deps[@]}" || return 1
    vuru_install_build_dependencies "$cross" "$XBPS_TARGET_MACHINE" "${target_deps[@]}"
}
