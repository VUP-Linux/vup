package xbps

import vuru ".."

// Remove a package
remove_pkg :: proc(idx: ^vuru.Index, pkg_name: string, yes: bool) -> bool {
    if !vuru.is_valid_pkg_name(pkg_name) {
        vuru.log_error("Invalid package name")
        return false
    }
    
    // Check if package is in VUP index (optional, just for info)
    if pkg, found := vuru.index_get_package(idx, pkg_name); found {
        vuru.log_info("Removing %s (from category '%s')", pkg_name, pkg.category)
    } else {
        vuru.log_info("Removing %s", pkg_name)
    }
    
    // Confirm unless --yes
    if !yes {
        if !vuru.prompt_yes_no("Remove package?") {
            vuru.log_info("Removal cancelled")
            return false
        }
    }
    
    // Run xbps-remove
    args: [dynamic]string
    defer delete(args)
    
    append(&args, "xbps-remove")
    if yes {
        append(&args, "-y")
    }
    append(&args, pkg_name)
    
    if !vuru.exec_command(args[:], use_sudo = true) {
        vuru.log_error("Failed to remove %s", pkg_name)
        return false
    }
    
    // Remove cached template
    vuru.cache_remove_template(pkg_name)
    
    vuru.log_success("Successfully removed %s", pkg_name)
    return true
}
