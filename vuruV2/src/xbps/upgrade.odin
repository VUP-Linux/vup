package xbps

import vuru ".."

// Upgrade all VUP packages
upgrade_all :: proc(idx: ^vuru.Index, yes: bool) -> bool {
    if idx == nil {
        vuru.log_error("Invalid index")
        return false
    }
    
    vuru.log_info("Checking for package updates...")
    
    // Get list of installed VUP packages
    installed := get_installed_vup_packages(idx)
    defer delete(installed)
    
    if len(installed) == 0 {
        vuru.log_info("No VUP packages installed")
        return true
    }
    
    vuru.log_info("Found %d VUP packages installed", len(installed))
    
    // Check each package for updates
    updates_available := false
    packages_to_update: [dynamic]string
    defer delete(packages_to_update)
    
    for pkg_name in installed {
        pkg, found := vuru.index_get_package(idx, pkg_name)
        if !found {
            continue
        }
        
        // Fetch current template
        new_tmpl, tmpl_ok := vuru.fetch_template(pkg.category, pkg_name, context.temp_allocator)
        if !tmpl_ok {
            continue
        }
        
        // Compare with cached
        cached_tmpl, cached_ok := vuru.cache_get_template(pkg_name, context.temp_allocator)
        if cached_ok && cached_tmpl != new_tmpl {
            vuru.log_info("Update available: %s", pkg_name)
            append(&packages_to_update, pkg_name)
            updates_available = true
        }
    }
    
    if !updates_available {
        vuru.log_success("All packages are up to date")
        return true
    }
    
    vuru.log_info("%d package(s) can be updated", len(packages_to_update))
    
    // Confirm unless --yes
    if !yes {
        if !vuru.prompt_yes_no("Proceed with updates?") {
            vuru.log_info("Update cancelled")
            return false
        }
    }
    
    // Update each package
    success := true
    for pkg_name in packages_to_update {
        if !install_pkg(idx, pkg_name, yes = true) {
            success = false
        }
    }
    
    if success {
        vuru.log_success("All updates completed")
    } else {
        vuru.log_warn("Some updates failed")
    }
    
    return success
}

// Get list of installed packages that are in the VUP index
get_installed_vup_packages :: proc(idx: ^vuru.Index, allocator := context.allocator) -> []string {
    import "core:strings"
    import "core:c"
    import "core:sys/posix"
    
    if idx == nil {
        return {}
    }
    
    // Run xbps-query to get installed packages
    pipe_fds: [2]c.int
    if posix.pipe(&pipe_fds) != .SUCCESS {
        return {}
    }
    
    pid := posix.fork()
    
    if pid < 0 {
        posix.close(pipe_fds[0])
        posix.close(pipe_fds[1])
        return {}
    }
    
    if pid == 0 {
        posix.close(pipe_fds[0])
        posix.dup2(pipe_fds[1], posix.STDOUT_FILENO)
        posix.close(pipe_fds[1])
        
        args: []cstring = {"xbps-query", "-l", nil}
        posix.execvp("xbps-query", raw_data(args))
        posix._exit(127)
    }
    
    posix.close(pipe_fds[1])
    
    // Read output
    builder := strings.builder_make(context.temp_allocator)
    buf: [4096]byte
    
    for {
        n := posix.read(pipe_fds[0], raw_data(buf[:]), len(buf))
        if n <= 0 {
            break
        }
        strings.write_bytes(&builder, buf[:n])
    }
    
    posix.close(pipe_fds[0])
    
    status: c.int
    posix.waitpid(pid, &status, {})
    
    output := strings.to_string(builder)
    lines := strings.split_lines(output)
    
    // Parse output and find VUP packages
    result: [dynamic]string
    result.allocator = allocator
    
    for line in lines {
        if len(line) == 0 {
            continue
        }
        
        // xbps-query -l format: "ii package-name-version ..."
        parts := strings.fields(line)
        if len(parts) < 2 {
            continue
        }
        
        // Extract package name (remove version suffix)
        pkg_with_version := parts[1]
        
        // Find last dash followed by version number
        name := extract_package_name(pkg_with_version)
        
        // Check if it's in our index
        if name in idx.packages {
            append(&result, strings.clone(name, allocator))
        }
    }
    
    return result[:]
}

// Extract package name from "name-version" string
extract_package_name :: proc(pkg_with_version: string) -> string {
    import "core:strings"
    
    // Find the last dash that's followed by a digit (version start)
    last_version_dash := -1
    
    for i := len(pkg_with_version) - 1; i >= 0; i -= 1 {
        if pkg_with_version[i] == '-' && i + 1 < len(pkg_with_version) {
            next_char := pkg_with_version[i + 1]
            if next_char >= '0' && next_char <= '9' {
                last_version_dash = i
                break
            }
        }
    }
    
    if last_version_dash > 0 {
        return pkg_with_version[:last_version_dash]
    }
    
    return pkg_with_version
}
