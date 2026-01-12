package xbps

import common "../common"



// Remove a package
remove_pkg :: proc(idx: ^common.Index, pkg_name: string, yes: bool) -> bool {
    if !common.is_valid_pkg_name(pkg_name) {
        common.log_error("Invalid package name")
        return false
    }
    
    // Check if package is in VUP index (optional, just for info)
    if pkg, found := common.index_get_package(idx, pkg_name); found {
        common.log_info("Removing %s (from category '%s')", pkg_name, pkg.category)
    } else {
        common.log_info("Removing %s", pkg_name)
    }
    
    // Confirm unless --yes
    if !yes {
        if !common.prompt_yes_no("Remove package?") {
            common.log_info("Removal cancelled")
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
    
    if !common.exec_command(args[:], use_sudo = true) {
        common.log_error("Failed to remove %s", pkg_name)
        return false
    }
    
    // Remove cached template
    common.cache_remove_template(pkg_name)
    
    common.log_success("Successfully removed %s", pkg_name)
    return true
}
