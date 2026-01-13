package index

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import "../../utils"

// Package metadata from index
Package_Info :: struct {
	version:    string,
	category:   string,
	short_desc: string,
	repo_urls:  map[string]string,
}

// Package index structure
Index :: struct {
	packages:  map[string]Package_Info,
	allocator: mem.Allocator,
}

// Free index and all its allocations
index_free :: proc(idx: ^Index) {
	for name, pkg in idx.packages {
		delete(pkg.repo_urls)
	}
	delete(idx.packages)
}

// Get package from index
index_get_package :: proc(idx: ^Index, name: string) -> (Package_Info, bool) {
	pkg, ok := idx.packages[name]
	return pkg, ok
}

// Validate URL
is_valid_url :: proc(url: string) -> bool {
	if len(url) == 0 {
		return false
	}

	if !strings.has_prefix(url, "https://") && !strings.has_prefix(url, "http://") {
		return false
	}

	// Check for shell metacharacters
	dangerous :: ";|&$`'\"\\>\n\r<(){}"
	for c in url {
		if strings.contains_rune(dangerous, c) {
			return false
		}
	}

	return true
}

// Parse index from JSON content
parse_index :: proc(content: string, allocator := context.allocator) -> (Index, bool) {
	idx := Index {
		packages  = make(map[string]Package_Info, allocator = allocator),
		allocator = allocator,
	}

	// Parse JSON
	parsed, err := json.parse(transmute([]u8)content, allocator = context.temp_allocator)
	if err != .None {
		utils.log_error("Failed to parse index JSON")
		return idx, false
	}

	root, ok := parsed.(json.Object)
	if !ok {
		utils.log_error("Invalid index format")
		return idx, false
	}

	// Iterate packages
	for name, value in root {
		pkg_obj, is_obj := value.(json.Object)
		if !is_obj {continue}

		pkg := Package_Info{}

		if v, has := pkg_obj["version"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.version = strings.clone(s, allocator)
			}
		}

		if v, has := pkg_obj["category"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.category = strings.clone(s, allocator)
			}
		}

		if v, has := pkg_obj["short_desc"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.short_desc = strings.clone(s, allocator)
			}
		}

		if v, has := pkg_obj["repo_urls"]; has {
			if urls_obj, is_obj := v.(json.Object); is_obj {
				pkg.repo_urls = make(map[string]string, allocator = allocator)
				for arch, url_val in urls_obj {
					if url_str, is_str := url_val.(json.String); is_str {
						pkg.repo_urls[strings.clone(arch, allocator)] = strings.clone(
							url_str,
							allocator,
						)
					}
				}
			}
		}

		idx.packages[strings.clone(name, allocator)] = pkg
	}

	return idx, true
}

// Load index from file
load_index_from_file :: proc(path: string, allocator := context.allocator) -> (Index, bool) {
	content, ok := utils.read_file(path, context.temp_allocator)
	if !ok {
		return {}, false
	}

	return parse_index(content, allocator)
}

// Load or fetch index
index_load_or_fetch :: proc(
	url: string,
	force_update: bool,
	allocator := context.allocator,
) -> (
	Index,
	bool,
) {
	if !is_valid_url(url) {
		utils.log_error("Invalid or unsafe URL provided")
		return {}, false
	}

	cache_dir, cache_ok := utils.get_cache_dir(context.temp_allocator)
	if !cache_ok {
		utils.log_error("Could not determine cache directory")
		return {}, false
	}

	if !utils.mkdir_p(cache_dir) {
		utils.log_error("Failed to create cache directory: %s", cache_dir)
		return {}, false
	}

	index_path := utils.path_join(cache_dir, "index.json", allocator = context.temp_allocator)
	etag_path := utils.path_join(cache_dir, "index.json.etag", allocator = context.temp_allocator)
	temp_path := utils.path_join(cache_dir, "index.json.tmp", allocator = context.temp_allocator)

	// Try to load from cache if not forced
	if !force_update && os.exists(index_path) {
		idx, ok := load_index_from_file(index_path, allocator)
		if ok {
			return idx, true
		}
	}

	// Read existing ETag
	old_etag := ""
	if !force_update && os.exists(etag_path) {
		if content, ok := utils.read_file(etag_path, context.temp_allocator); ok {
			old_etag = strings.trim_space(content)
		}
	}

	utils.log_info("Fetching index...")

	// Build curl command
	curl_args: [dynamic]string
	defer delete(curl_args)

	append(&curl_args, "curl", "-s", "-L", "-w", "%{http_code}")

	if len(old_etag) > 0 {
		append(&curl_args, "-H", fmt.tprintf("If-None-Match: %s", old_etag))
	}

	append(&curl_args, "-o", temp_path, url)

	output, ok := utils.run_command_output(curl_args[:])
	defer delete(output)

	if !ok {
		utils.log_error("Failed to fetch index")
		os.remove(temp_path)

		// Fallback to cache
		if os.exists(index_path) {
			utils.log_info("Using cached index")
			return load_index_from_file(index_path, allocator)
		}
		return {}, false
	}

	status := strings.trim_space(output)

	if status == "304" {
		utils.log_info("Index not modified (cached)")
		os.remove(temp_path)
		return load_index_from_file(index_path, allocator)
	}

	if status == "200" {
		utils.log_info("Index updated")

		// Move temp to index
		os.remove(index_path)
		if os.rename(temp_path, index_path) != os.ERROR_NONE {
			utils.log_error("Failed to save index")
			os.remove(temp_path)
			return {}, false
		}

		return load_index_from_file(index_path, allocator)
	}

	// Unexpected status
	utils.log_error("Unexpected HTTP status: %s", status)
	os.remove(temp_path)

	// Fallback to cache
	if os.exists(index_path) {
		utils.log_info("Using cached index as fallback")
		return load_index_from_file(index_path, allocator)
	}

	return {}, false
}
