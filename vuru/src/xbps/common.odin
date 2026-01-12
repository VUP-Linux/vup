package xbps

import common "../common"

// Re-export functions under vuru-compatible names


// Wrapper functions that match the calling convention from main.odin
xbps_install_pkg :: proc(idx: ^common.Index, pkg_name: string, yes: bool) -> bool {
    return install_pkg(idx, pkg_name, yes)
}

xbps_remove_pkg :: proc(idx: ^common.Index, pkg_name: string, yes: bool) -> bool {
    return remove_pkg(idx, pkg_name, yes)
}

xbps_upgrade_all :: proc(idx: ^common.Index, yes: bool) -> bool {
    return upgrade_all(idx, yes)
}

xbps_search :: proc(idx: ^common.Index, query: string) {
    search(idx, query)
}
