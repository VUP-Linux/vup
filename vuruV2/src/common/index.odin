package common

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:c"
import "core:sys/posix"

// Package metadata from the index
Package :: struct {
    category:    string,
    version:     string,
    description: string,
    archs:       [dynamic]string,
    repo_urls:   map[string]string,  // arch -> url
}

// The package index
Index :: struct {
    packages: map[string]Package,
    raw_json: json.Value,
}

// Get current system architecture
get_system_arch :: proc() -> string {
    // Use uname to get machine type
    pipe_fds: [2]posix.FD
    if posix.pipe(&pipe_fds) != .OK {
        return "x86_64"  // fallback
    }
    
    pid := posix.fork()
    
    if pid < 0 {
        posix.close(pipe_fds[0])
        posix.close(pipe_fds[1])
        return "x86_64"
    }
    
    if pid == 0 {
        posix.close(pipe_fds[0])
        posix.dup2(pipe_fds[1], posix.STDOUT_FILENO)
        posix.close(pipe_fds[1])
        
        args: []cstring = {"uname", "-m", nil}
        posix.execvp("uname", raw_data(args))
        posix._exit(127)
    }
    
    posix.close(pipe_fds[1])
    
    buf: [64]byte
    n := posix.read(pipe_fds[0], raw_data(buf[:]), len(buf))
    posix.close(pipe_fds[0])
    
    status: c.int
    posix.waitpid(pid, &status, {})
    
    if n > 0 {
        arch := strings.trim_space(string(buf[:n]))
        // Map uname output to xbps arch names
        if arch == "x86_64" { return "x86_64" }
        if arch == "aarch64" { return "aarch64" }
        if arch == "armv7l" { return "armv7l" }
        if arch == "armv6l" { return "armv6l" }
        if arch == "i686" || arch == "i386" { return "i686" }
        return arch
    }
    
    return "x86_64"
}

// Get repo URL for current architecture
get_repo_url_for_arch :: proc(pkg: ^Package, arch: string) -> (url: string, ok: bool) {
    if pkg == nil {
        return "", false
    }
    url, ok = pkg.repo_urls[arch]
    return url, ok
}

// Free index resources
index_free :: proc(idx: ^Index) {
    if idx == nil {
        return
    }
    delete(idx.packages)
    json.destroy_value(idx.raw_json)
}

// Validate URL to prevent command injection
is_valid_url :: proc(url: string) -> bool {
    if len(url) == 0 {
        return false
    }
    
    // Must start with http:// or https://
    if !strings.has_prefix(url, "https://") && !strings.has_prefix(url, "http://") {
        return false
    }
    
    // Check for shell metacharacters
    bad_chars := ";|&$`'\"\\><(){}"
    for c in url {
        if strings.contains_rune(bad_chars, c) || c == '\n' || c == '\r' {
            return false
        }
    }
    
    return true
}

// Fetch URL content using curl
fetch_url :: proc(url: string, allocator := context.allocator) -> (content: string, ok: bool) {
    if !is_valid_url(url) {
        log_error("Invalid URL: %s", url)
        return "", false
    }
    
    // Create pipe for reading curl output
    pipe_fds: [2]posix.FD
    if posix.pipe(&pipe_fds) != .OK {
        log_error("pipe() failed")
        return "", false
    }
    
    pid := posix.fork()
    
    if pid < 0 {
        posix.close(pipe_fds[0])
        posix.close(pipe_fds[1])
        log_error("fork() failed")
        return "", false
    }
    
    if pid == 0 {
        // Child process
        posix.close(pipe_fds[0])
        posix.dup2(pipe_fds[1], posix.STDOUT_FILENO)
        posix.close(pipe_fds[1])
        
        url_cstr := strings.clone_to_cstring(url, context.temp_allocator)
        args: []cstring = {"curl", "-sfL", "--max-time", "30", url_cstr, nil}
        posix.execvp("curl", raw_data(args))
        posix._exit(127)
    }
    
    // Parent process
    posix.close(pipe_fds[1])
    
    // Read output
    builder := strings.builder_make(allocator)
    buf: [4096]byte
    
    for {
        n := posix.read(pipe_fds[0], raw_data(buf[:]), len(buf))
        if n <= 0 {
            break
        }
        strings.write_bytes(&builder, buf[:n])
    }
    
    posix.close(pipe_fds[0])
    
    // Wait for child
    status: c.int
    posix.waitpid(pid, &status, {})
    
    if !posix.WIFEXITED(status) || posix.WEXITSTATUS(status) != 0 {
        strings.builder_destroy(&builder)
        return "", false
    }
    
    return strings.to_string(builder), true
}

// Parse JSON index into Index struct
parse_index :: proc(json_str: string) -> (idx: Index, ok: bool) {
    parsed, err := json.parse_string(json_str)
    if err != nil {
        log_error("Failed to parse JSON: %v", err)
        return {}, false
    }
    
    root, root_ok := parsed.(json.Object)
    if !root_ok {
        json.destroy_value(parsed)
        log_error("Invalid index format: expected object")
        return {}, false
    }
    
    idx.raw_json = parsed
    idx.packages = make(map[string]Package)
    
    for name, value in root {
        pkg_obj, pkg_ok := value.(json.Object)
        if !pkg_ok {
            continue
        }
        
        pkg := Package{}
        
        if cat, cat_ok := pkg_obj["category"].(json.String); cat_ok {
            pkg.category = cat
        }
        if ver, ver_ok := pkg_obj["version"].(json.String); ver_ok {
            pkg.version = ver
        }
        if desc, desc_ok := pkg_obj["description"].(json.String); desc_ok {
            pkg.description = desc
        }
        
        // Parse archs array
        if archs_arr, archs_ok := pkg_obj["archs"].(json.Array); archs_ok {
            for arch_val in archs_arr {
                if arch_str, str_ok := arch_val.(json.String); str_ok {
                    append(&pkg.archs, arch_str)
                }
            }
        }
        
        // Parse repo_urls map
        if urls_obj, urls_ok := pkg_obj["repo_urls"].(json.Object); urls_ok {
            pkg.repo_urls = make(map[string]string)
            for arch, url_val in urls_obj {
                if url_str, str_ok := url_val.(json.String); str_ok {
                    pkg.repo_urls[arch] = url_str
                }
            }
        }
        
        idx.packages[name] = pkg
    }
    
    return idx, true
}

// Load index from cache
index_load_cached :: proc() -> (idx: Index, ok: bool) {
    cache_path, path_ok := get_index_cache_path(context.temp_allocator)
    if !path_ok {
        return {}, false
    }
    
    content, read_ok := read_file(cache_path)
    if !read_ok {
        return {}, false
    }
    defer delete(content)
    
    return parse_index(content)
}

// Fetch index from remote URL
index_fetch :: proc(url: string) -> (idx: Index, ok: bool) {
    log_info("Fetching package index...")
    
    content, fetch_ok := fetch_url(url)
    if !fetch_ok {
        log_error("Failed to fetch index from %s", url)
        return {}, false
    }
    defer delete(content)
    
    // Save to cache
    cache_path, path_ok := get_index_cache_path(context.temp_allocator)
    if path_ok {
        cache_dir, dir_ok := get_cache_dir(context.temp_allocator)
        if dir_ok && ensure_dir(cache_dir) {
            write_file(cache_path, content)
        }
    }
    
    return parse_index(content)
}

// Load or fetch index
index_load_or_fetch :: proc(url: string, force_sync: bool = false) -> (idx: Index, ok: bool) {
    if !force_sync {
        cached_idx, cached_ok := index_load_cached()
        if cached_ok {
            return cached_idx, true
        }
    }
    
    return index_fetch(url)
}

// Get package from index
index_get_package :: proc(idx: ^Index, name: string) -> (pkg: Package, ok: bool) {
    if idx == nil {
        return {}, false
    }
    return idx.packages[name]
}

// Fetch template for a package
fetch_template :: proc(category: string, pkg_name: string, allocator := context.allocator) -> (content: string, ok: bool) {
    if !is_valid_pkg_name(pkg_name) {
        return "", false
    }
    
    // Build template URL
    base_url := "https://raw.githubusercontent.com/vup-linux/vup/main/vup/srcpkgs"
    url := strings.concatenate({base_url, "/", category, "/", pkg_name, "/template"}, context.temp_allocator)
    
    return fetch_url(url, allocator)
}
