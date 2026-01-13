package main

import "core:os"
import "core:strings"

// Retrieve a cached package template
cache_get_template :: proc(pkg_name: string, allocator := context.allocator) -> (string, bool) {
	if !is_valid_identifier(pkg_name) {
		log_error("Invalid package name: %s", pkg_name)
		return "", false
	}

	cache_dir, ok := get_cache_dir(context.temp_allocator)
	if !ok {
		return "", false
	}

	path := path_join(cache_dir, "templates", pkg_name, allocator = context.temp_allocator)

	return read_file(path, allocator)
}

// Save a package template to the cache
cache_save_template :: proc(pkg_name: string, content: string) -> bool {
	if !is_valid_identifier(pkg_name) || len(content) == 0 {
		return false
	}

	cache_dir, ok := get_cache_dir(context.temp_allocator)
	if !ok {
		return false
	}

	dir_path := path_join(cache_dir, "templates", allocator = context.temp_allocator)

	if !mkdir_p(dir_path) {
		log_error("Failed to create cache directory: %s", dir_path)
		return false
	}

	file_path := path_join(dir_path, pkg_name, allocator = context.temp_allocator)

	if !write_file(file_path, content) {
		log_error("Failed to save template")
		return false
	}

	return true
}
