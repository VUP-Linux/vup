package xbps

// Re-export functions under vuru-compatible names
import vuru ".."

// Wrapper functions that match the calling convention from main.odin
xbps_install_pkg :: proc(idx: ^vuru.Index, pkg_name: string, yes: bool) -> bool {
    return install_pkg(idx, pkg_name, yes)
}

xbps_remove_pkg :: proc(idx: ^vuru.Index, pkg_name: string, yes: bool) -> bool {
    return remove_pkg(idx, pkg_name, yes)
}

xbps_upgrade_all :: proc(idx: ^vuru.Index, yes: bool) -> bool {
    return upgrade_all(idx, yes)
}

xbps_search :: proc(idx: ^vuru.Index, query: string) {
    search(idx, query)
}
