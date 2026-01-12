package xbps

import common "../common"

import "core:fmt"
import "core:strings"



// Install a package from the VUP index
install_pkg :: proc(idx: ^common.Index, pkg_name: string, yes: bool) -> bool {
    if idx == nil || !common.is_valid_pkg_name(pkg_name) {
        common.log_error("Invalid arguments")
        return false
    }
    
    pkg, found := common.index_get_package(idx, pkg_name)
    if !found {
        common.log_error("Package '%s' not found in VUP index", pkg_name)
        return false
    }
    
    if len(pkg.category) == 0 {
        common.log_error("Invalid package metadata for '%s'", pkg_name)
        return false
    }
    
    // Get system architecture and find matching repo URL
    system_arch := common.get_system_arch()
    repo_url, url_ok := common.get_repo_url_for_arch(&pkg, system_arch)
    
    if !url_ok {
        common.log_error("Package '%s' is not available for architecture '%s'", pkg_name, system_arch)
        common.log_info("Available architectures: %v", pkg.archs[:])
        return false
    }
    
    common.log_info("Found %s in category '%s' (arch: %s)", pkg_name, pkg.category, system_arch)
    
    // Fetch template for review
    common.log_info("Fetching template for review...")
    new_tmpl, tmpl_ok := common.fetch_template(pkg.category, pkg_name)
    if !tmpl_ok {
        common.log_error("Failed to fetch template")
        return false
    }
    defer delete(new_tmpl)
    
    // Get cached template for diff
    cached_tmpl, cached_ok := common.cache_get_template(pkg_name)
    defer if cached_ok do delete(cached_tmpl)
    
    // Review unless --yes flag
    if !yes {
        if cached_ok {
            // Show diff if template changed
            if cached_tmpl != new_tmpl {
                common.log_warn("Template has changed since last install:")
                show_diff(cached_tmpl, new_tmpl)
            } else {
                common.log_info("Template unchanged since last install")
            }
        } else {
            // Show full template for new packages
            common.log_info("Template for %s:", pkg_name)
            print_template(new_tmpl)
        }
        
        if !common.prompt_yes_no("Proceed with installation?") {
            common.log_info("Installation cancelled")
            return false
        }
    }
    
    // Run xbps-install
    common.log_info("Installing %s...", pkg_name)
    
    args: [dynamic]string
    defer delete(args)
    
    append(&args, "xbps-install")
    append(&args, "-R", repo_url)
    append(&args, "-S")
    if yes {
        append(&args, "-y")
    }
    append(&args, pkg_name)
    
    if !common.exec_command(args[:], use_sudo = true) {
        common.log_error("Failed to install %s", pkg_name)
        return false
    }
    
    // Cache the template
    common.cache_set_template(pkg_name, new_tmpl)
    
    common.log_success("Successfully installed %s", pkg_name)
    return true
}

// Print template with line numbers
print_template :: proc(content: string) {
    lines := strings.split_lines(content)
    defer delete(lines)
    
    for line, i in lines {
        fmt.printfln("%4d | %s", i + 1, line)
    }
}
