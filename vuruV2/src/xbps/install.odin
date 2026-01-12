package xbps

import vuru ".."

// Install a package from the VUP index
install_pkg :: proc(idx: ^vuru.Index, pkg_name: string, yes: bool) -> bool {
    if idx == nil || !vuru.is_valid_pkg_name(pkg_name) {
        vuru.log_error("Invalid arguments")
        return false
    }
    
    pkg, found := vuru.index_get_package(idx, pkg_name)
    if !found {
        vuru.log_error("Package '%s' not found in VUP index", pkg_name)
        return false
    }
    
    if len(pkg.repo_url) == 0 || len(pkg.category) == 0 {
        vuru.log_error("Invalid package metadata for '%s'", pkg_name)
        return false
    }
    
    vuru.log_info("Found %s in category '%s'", pkg_name, pkg.category)
    
    // Fetch template for review
    vuru.log_info("Fetching template for review...")
    new_tmpl, tmpl_ok := vuru.fetch_template(pkg.category, pkg_name)
    if !tmpl_ok {
        vuru.log_error("Failed to fetch template")
        return false
    }
    defer delete(new_tmpl)
    
    // Get cached template for diff
    cached_tmpl, cached_ok := vuru.cache_get_template(pkg_name)
    defer if cached_ok do delete(cached_tmpl)
    
    // Review unless --yes flag
    if !yes {
        if cached_ok {
            // Show diff if template changed
            if cached_tmpl != new_tmpl {
                vuru.log_warn("Template has changed since last install:")
                show_diff(cached_tmpl, new_tmpl)
            } else {
                vuru.log_info("Template unchanged since last install")
            }
        } else {
            // Show full template for new packages
            vuru.log_info("Template for %s:", pkg_name)
            print_template(new_tmpl)
        }
        
        if !vuru.prompt_yes_no("Proceed with installation?") {
            vuru.log_info("Installation cancelled")
            return false
        }
    }
    
    // Run xbps-install
    vuru.log_info("Installing %s...", pkg_name)
    
    args: [dynamic]string
    defer delete(args)
    
    append(&args, "xbps-install")
    append(&args, "-R", pkg.repo_url)
    append(&args, "-S")
    if yes {
        append(&args, "-y")
    }
    append(&args, pkg_name)
    
    if !vuru.exec_command(args[:], use_sudo = true) {
        vuru.log_error("Failed to install %s", pkg_name)
        return false
    }
    
    // Cache the template
    vuru.cache_set_template(pkg_name, new_tmpl)
    
    vuru.log_success("Successfully installed %s", pkg_name)
    return true
}

// Print template with line numbers
print_template :: proc(content: string) {
    import "core:strings"
    import "core:fmt"
    
    lines := strings.split_lines(content)
    defer delete(lines)
    
    for line, i in lines {
        fmt.printfln("%4d | %s", i + 1, line)
    }
}
