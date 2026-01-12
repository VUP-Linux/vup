package vuru

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"

// Get cache directory path, respecting XDG_CACHE_HOME
get_cache_dir :: proc(allocator := context.allocator) -> (path: string, ok: bool) {
    xdg_cache := getenv("XDG_CACHE_HOME")
    if len(xdg_cache) > 0 && xdg_cache[0] == '/' {
        return strings.concatenate({xdg_cache, "/vup"}, allocator), true
    }
    
    home := getenv("HOME")
    if len(home) == 0 || home[0] != '/' {
        return "", false
    }
    
    return strings.concatenate({home, "/.cache/vup"}, allocator), true
}

// Get templates cache directory
get_templates_dir :: proc(allocator := context.allocator) -> (path: string, ok: bool) {
    cache_dir, cache_ok := get_cache_dir(allocator)
    if !cache_ok {
        return "", false
    }
    defer if !ok do delete(cache_dir, allocator)
    
    return strings.concatenate({cache_dir, "/templates"}, allocator), true
}

// Ensure directory exists (creates recursively)
ensure_dir :: proc(path: string) -> bool {
    if os.exists(path) {
        return os.is_dir(path)
    }
    
    err := os.make_directory(path)
    if err == nil {
        return true
    }
    
    // Try creating parent directories
    parent := filepath.dir(path)
    if parent == path || len(parent) == 0 {
        return false
    }
    
    if !ensure_dir(parent) {
        return false
    }
    
    err = os.make_directory(path)
    return err == nil
}

// Validate package name to prevent path traversal
is_valid_pkg_name :: proc(name: string) -> bool {
    if len(name) == 0 || name[0] == '.' {
        return false
    }
    
    for c in name {
        valid := (c >= 'a' && c <= 'z') ||
                 (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9') ||
                 c == '-' || c == '_' || c == '.'
        if !valid {
            return false
        }
    }
    
    // Prevent directory traversal
    if strings.contains(name, "..") {
        return false
    }
    
    return true
}

// Get cached template for a package
cache_get_template :: proc(pkg_name: string, allocator := context.allocator) -> (content: string, ok: bool) {
    if !is_valid_pkg_name(pkg_name) {
        return "", false
    }
    
    templates_dir, dir_ok := get_templates_dir(context.temp_allocator)
    if !dir_ok {
        return "", false
    }
    
    path := strings.concatenate({templates_dir, "/", pkg_name}, context.temp_allocator)
    
    return read_file(path, allocator)
}

// Save template to cache
cache_set_template :: proc(pkg_name: string, content: string) -> bool {
    if !is_valid_pkg_name(pkg_name) {
        return false
    }
    
    templates_dir, dir_ok := get_templates_dir(context.temp_allocator)
    if !dir_ok {
        return false
    }
    
    if !ensure_dir(templates_dir) {
        return false
    }
    
    path := strings.concatenate({templates_dir, "/", pkg_name}, context.temp_allocator)
    
    return write_file(path, content)
}

// Remove template from cache
cache_remove_template :: proc(pkg_name: string) -> bool {
    if !is_valid_pkg_name(pkg_name) {
        return false
    }
    
    templates_dir, dir_ok := get_templates_dir(context.temp_allocator)
    if !dir_ok {
        return false
    }
    
    path := strings.concatenate({templates_dir, "/", pkg_name}, context.temp_allocator)
    
    if !os.exists(path) {
        return true  // Already doesn't exist
    }
    
    return os.remove(path) == nil
}

// Get index cache path
get_index_cache_path :: proc(allocator := context.allocator) -> (path: string, ok: bool) {
    cache_dir, cache_ok := get_cache_dir(allocator)
    if !cache_ok {
        return "", false
    }
    defer if !ok do delete(cache_dir, allocator)
    
    return strings.concatenate({cache_dir, "/index.json"}, allocator), true
}
