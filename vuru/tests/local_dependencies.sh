#!/bin/bash
# Exercise the real dependency policy with an isolated, synthetic build tree.
set -eo pipefail
policy=$(cd "$(dirname "$0")/../../vup/common/xbps-src/shutils" && pwd)/vuru_local_dependencies.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export XBPS_DISTDIR="$work/tree" XBPS_HOSTDIR="$work/host" XBPS_LIBEXECDIR="$work/libexec"
export XBPS_SRCPKGDIR="$XBPS_DISTDIR/srcpkgs" XBPS_VURU_LOCAL_BUILD_STATE="$work/state"
export XBPS_MACHINE=x86_64 XBPS_TARGET_MACHINE=x86_64 XBPS_MIRROR=
export XBPS_QUERY_CMD=mock_query XBPS_QUERY_XCMD=mock_query XBPS_INSTALL_CMD=mock_install
export XBPS_INSTALL_XCMD=mock_install LOG="$work/log" POLICY="$policy"
mkdir -p "$XBPS_DISTDIR/etc/xbps.d" "$XBPS_LIBEXECDIR" "$XBPS_VURU_LOCAL_BUILD_STATE" "$XBPS_HOSTDIR/binpkgs/main"
for name in vlang vc cycle; do mkdir -p "$XBPS_SRCPKGDIR/languages/$name"; touch "$XBPS_SRCPKGDIR/languages/$name/template"; done
# Include a local template for an official package to prove official precedence.
mkdir -p "$XBPS_SRCPKGDIR/tools/unzip"
touch "$XBPS_SRCPKGDIR/tools/unzip/template"
printf 'repository=https://repo-default.voidlinux.org/current\n' > "$XBPS_DISTDIR/etc/xbps.d/repos-remote.conf"
mock_query() {
    echo "query $*" >> "$LOG"
    [[ " $* " == *' -i '* ]] || return 90
    case "${*: -1}" in unzip|clang) echo "${*: -1}-1.0_1" ;; *) return 1 ;; esac
}
mock_install() { echo "install $*" >> "$LOG"; }
xbps-uhelper() { echo "$2"; }
msg_error() { printf '%b' "$*" >&2; }
skip_check_step() { return 0; }
setup_pkg_depends() { echo "$depends"; }
setup_pkg() {
    sourcepkg=$1 pkgname=$1 hostmakedepends= makedepends= depends= subpackages=
    case "$1" in
        vlang) hostmakedepends='clang vc' ;;
        cycle) hostmakedepends=cycle ;;
    esac
}
export -f mock_query mock_install xbps-uhelper msg_error skip_check_step setup_pkg_depends setup_pkg
cat > "$XBPS_LIBEXECDIR/build.sh" <<'BUILD'
#!/bin/bash
source "$POLICY"
setup_pkg "$1"
echo "build $1" >> "$LOG"
if [[ ${FAIL_BUILD:-} == "$1" ]]; then
    echo "simulated build failure for $1" >&2
    exit 23
fi
vuru_install_pkg_deps "$1" "$2" pkg "$4"
BUILD
chmod +x "$XBPS_LIBEXECDIR/build.sh"
# The real template loader clears unrecognized exported variables. Preserve
# both mode and state through that boundary (the live test caught this).
export XBPS_VURU_BUILD_LOCAL=1
(
    source "$(dirname "$policy")/../../environment/setup/sourcepkg.sh"
    [[ $XBPS_VURU_BUILD_LOCAL == 1 && -d $XBPS_VURU_LOCAL_BUILD_STATE ]]
)
source "$policy"
pkgname=v-analyzer hostmakedepends='unzip vlang' depends=vlang
vuru_install_pkg_deps v-analyzer v-analyzer pkg '' ''
[[ $(grep -c '^build vlang$' "$LOG") == 1 ]]
[[ $(grep -c '^build vc$' "$LOG") == 1 ]]
! grep -q '^build unzip\|^build clang' "$LOG"
grep -q '^install -i .* -Ay unzip-1.0_1 vlang$' "$LOG"
# No host sudo install; build-only vc/clang are installed via the build-root runner.
! grep -q sudo "$LOG"
if vuru_prepare_dependency cycle '' x86_64 mock_query >/dev/null; then
    echo 'Cycle should fail' >&2; exit 1
fi
export FAIL_BUILD=vc
export XBPS_VURU_ROOT_PKG=v-analyzer
rm -rf "$XBPS_VURU_LOCAL_BUILD_STATE"
mkdir -p "$XBPS_VURU_LOCAL_BUILD_STATE"
if vuru_prepare_dependency vlang '' x86_64 mock_query >/tmp/vuru-dependency-output 2>/tmp/vuru-dependency-error; then
    echo 'Failed dependency should fail' >&2; exit 1
fi
vuru_dependency_stack "$(cat "$XBPS_VURU_LOCAL_BUILD_STATE/failed")" 2>>/tmp/vuru-dependency-error
grep -q 'Vuru dependency stack:' /tmp/vuru-dependency-error
grep -q 'vc.*FAILED' /tmp/vuru-dependency-error
grep -q 'vlang.*dependency' /tmp/vuru-dependency-error
grep -q 'v-analyzer.*target' /tmp/vuru-dependency-error
grep -q 'v-analyzer(host), vlang(host)' "$XBPS_VURU_LOCAL_BUILD_STATE/failed_chain"
unset FAIL_BUILD
unset XBPS_VURU_ROOT_PKG
if vuru_prepare_dependency missing '' x86_64 mock_query >/dev/null; then
    echo 'Missing template should fail' >&2; exit 1
fi
XBPS_MIRROR=https://mirror.example/void/current
[[ $(vuru_official_repositories x86_64) == https://mirror.example/void/current ]]
echo 'Local dependency policy tests passed'
