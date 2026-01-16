package index

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

import "../../utils"
import config "../config"
import errors "../errors"

// Validate URL - checks for valid scheme and dangerous characters
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
	idx := index_make(allocator)

	// Parse JSON using temp allocator since we clone what we need
	parsed, err := json.parse(transmute([]u8)content, allocator = context.temp_allocator)
	if err != .None {
		errors.log_error("Failed to parse index JSON")
		index_free(&idx)
		return {}, false
	}

	root, ok := parsed.(json.Object)
	if !ok {
		errors.log_error("Invalid index format")
		index_free(&idx)
		return {}, false
	}

	// Iterate packages
	for name, value in root {
		pkg_obj, is_obj := value.(json.Object)
		if !is_obj {
			continue
		}

		pkg := Package_Info{}

		// Parse version
		if v, has := pkg_obj["version"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.version = strings.clone(s, allocator)
			}
		}

		// Parse category
		if v, has := pkg_obj["category"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.category = strings.clone(s, allocator)
			}
		}

		// Parse short_desc
		if v, has := pkg_obj["short_desc"]; has {
			if s, is_str := v.(json.String); is_str {
				pkg.short_desc = strings.clone(s, allocator)
			}
		}

		// Parse repo_urls map
		if v, has := pkg_obj["repo_urls"]; has {
			if urls_obj, is_urls_obj := v.(json.Object); is_urls_obj {
				pkg.repo_urls = make(map[string]string, allocator = allocator)
				for arch, url_val in urls_obj {
					if url_str, is_url_str := url_val.(json.String); is_url_str {
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

// Get cache paths for index files
@(private)
Cache_Paths :: struct {
	dir:   string,
	index: string,
	etag:  string,
	temp:  string,
}

@(private)
get_cache_paths :: proc() -> (Cache_Paths, bool) {
	cache_dir, ok := config.get_cache_dir(context.temp_allocator)
	if !ok {
		return {}, false
	}

	return Cache_Paths {
			dir = cache_dir,
			index = utils.path_join(cache_dir, "index.json", allocator = context.temp_allocator),
			etag = utils.path_join(
				cache_dir,
				"index.json.etag",
				allocator = context.temp_allocator,
			),
			temp = utils.path_join(
				cache_dir,
				"index.json.tmp",
				allocator = context.temp_allocator,
			),
		},
		true
}

// Fetch index from URL, returns HTTP status code
@(private)
fetch_index_from_url :: proc(
	url: string,
	paths: Cache_Paths,
	old_etag: string,
) -> (
	status: string,
	ok: bool,
) {
	curl_args := make([dynamic]string, context.temp_allocator)

	append(&curl_args, "curl", "-s", "-L", "-w", "%{http_code}")

	// Use conditional request if we have an etag
	if len(old_etag) > 0 {
		append(&curl_args, "-H", fmt.tprintf("If-None-Match: %s", old_etag))
	}

	append(&curl_args, "-o", paths.temp, url)

	output, cmd_ok := utils.run_command_output(curl_args[:], context.temp_allocator)
	if !cmd_ok {
		return "", false
	}

	return strings.trim_space(output), true
}

// Load or fetch index - main entry point
index_load_or_fetch :: proc(
	url: string,
	force_update: bool,
	allocator := context.allocator,
) -> (
	Index,
	bool,
) {
	// Validate URL first
	if !is_valid_url(url) {
		errors.log_error("Invalid or unsafe URL provided")
		return {}, false
	}

	// Get cache paths
	paths, paths_ok := get_cache_paths()
	if !paths_ok {
		errors.log_error("Could not determine cache directory")
		return {}, false
	}

	// Ensure cache directory exists
	if !utils.mkdir_p(paths.dir) {
		errors.log_error("Failed to create cache directory: %s", paths.dir)
		return {}, false
	}

	// Try to load from cache if not forced
	if !force_update && os.exists(paths.index) {
		if idx, ok := load_index_from_file(paths.index, allocator); ok {
			return idx, true
		}
	}

	// Read existing ETag for conditional request
	old_etag := ""
	if !force_update && os.exists(paths.etag) {
		if content, ok := utils.read_file(paths.etag, context.temp_allocator); ok {
			old_etag = strings.trim_space(content)
		}
	}

	errors.log_info("Fetching index...")

	// Fetch from URL
	status, fetch_ok := fetch_index_from_url(url, paths, old_etag)
	if !fetch_ok {
		errors.log_error("Failed to fetch index")
		os.remove(paths.temp)
		return try_fallback_to_cache(paths.index, allocator)
	}

	// Handle response based on status
	switch status {
	case "304":
		// Not modified - use cache
		errors.log_info("Index not modified (cached)")
		os.remove(paths.temp)
		return load_index_from_file(paths.index, allocator)

	case "200":
		// Success - move temp file to index
		errors.log_info("Index updated")
		os.remove(paths.index)

		if os.rename(paths.temp, paths.index) != os.ERROR_NONE {
			errors.log_error("Failed to save index")
			os.remove(paths.temp)
			return {}, false
		}

		return load_index_from_file(paths.index, allocator)

	case:
		// Unexpected status
		errors.log_error("Unexpected HTTP status: %s", status)
		os.remove(paths.temp)
		return try_fallback_to_cache(paths.index, allocator)
	}
}

// Try to load from cache as fallback
@(private)
try_fallback_to_cache :: proc(
	index_path: string,
	allocator := context.allocator,
) -> (
	Index,
	bool,
) {
	if os.exists(index_path) {
		errors.log_info("Using cached index as fallback")
		return load_index_from_file(index_path, allocator)
	}
	return {}, false
}
