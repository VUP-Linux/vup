package main

import "core:fmt"
import "core:os"
import "core:strings"

// Threshold for using pager
PAGER_THRESHOLD :: 5

// Search result entry
Search_Result :: struct {
	name:       string,
	version:    string,
	desc:       string,
	source:     string, // "vup", "official", "installed"
	installed:  bool,
	category:   string, // For VUP packages
}

// Search VUP index for packages matching a query
search_vup :: proc(idx: ^Index, query: string) -> [dynamic]Search_Result {
	results := make([dynamic]Search_Result, context.temp_allocator)
	query_lower := strings.to_lower(query, context.temp_allocator)

	for name, pkg in idx.packages {
		name_lower := strings.to_lower(name, context.temp_allocator)
		desc_lower := strings.to_lower(pkg.short_desc, context.temp_allocator)

		if strings.contains(name_lower, query_lower) || strings.contains(desc_lower, query_lower) {
			append(&results, Search_Result{
				name = name,
				version = pkg.version,
				desc = pkg.short_desc,
				source = "vup",
				installed = is_pkg_installed(name),
				category = pkg.category,
			})
		}
	}

	return results
}

// Search official Void repos
search_official :: proc(query: string) -> [dynamic]Search_Result {
	results := make([dynamic]Search_Result, context.temp_allocator)

	output, ok := run_command_output({"xbps-query", "-Rs", query}, context.temp_allocator)
	if !ok {
		return results
	}

	// Parse output: [*] pkgname-version  description
	for line in strings.split_lines_iterator(&output) {
		if len(line) < 5 {
			continue
		}

		installed := line[0] == '*' || (len(line) > 1 && line[1] == '*')

		// Skip the [*] or [-] prefix
		rest := strings.trim_left(line[3:], " ")
		if len(rest) == 0 {
			continue
		}

		// Split into pkgver and description
		parts := strings.split_n(rest, " ", 2, context.temp_allocator)
		if len(parts) < 1 {
			continue
		}

		pkgver := parts[0]
		desc := strings.trim_space(parts[1]) if len(parts) > 1 else ""

		// Parse pkgname-version
		if idx := strings.last_index(pkgver, "-"); idx > 0 {
			append(&results, Search_Result{
				name = pkgver[:idx],
				version = pkgver[idx+1:],
				desc = desc,
				source = "official",
				installed = installed,
			})
		}
	}

	return results
}

// Format search results into a string
format_search_results :: proc(
	vup_results: []Search_Result,
	official_results: []Search_Result,
	allocator := context.allocator,
) -> string {
	builder := strings.builder_make(allocator)

	strings.write_string(&builder, "\n")

	// Format VUP results
	if len(vup_results) > 0 {
		fmt.sbprintf(&builder, "%s==> VUP Packages (%d)%s\n", COLOR_INFO, len(vup_results), COLOR_RESET)
		fmt.sbprintf(&builder, "%-30s %-15s %-12s %s\n", "NAME", "VERSION", "CATEGORY", "DESCRIPTION")
		strings.write_string(&builder, strings.repeat("-", 80, context.temp_allocator))
		strings.write_string(&builder, "\n")

		for r in vup_results {
			status := "[installed]" if r.installed else ""
			fmt.sbprintf(&builder, "%-30s %-15s %-12s %s %s\n",
				r.name,
				r.version if len(r.version) > 0 else "?",
				r.category if len(r.category) > 0 else "?",
				truncate(r.desc, 30),
				status,
			)
		}
		strings.write_string(&builder, "\n")
	}

	// Format official results
	if len(official_results) > 0 {
		fmt.sbprintf(&builder, "%s==> Official Void Packages (%d)%s\n", COLOR_INFO, len(official_results), COLOR_RESET)
		fmt.sbprintf(&builder, "%-30s %-15s %s\n", "NAME", "VERSION", "DESCRIPTION")
		strings.write_string(&builder, strings.repeat("-", 80, context.temp_allocator))
		strings.write_string(&builder, "\n")

		for r in official_results {
			status := "[installed]" if r.installed else ""
			fmt.sbprintf(&builder, "%-30s %-15s %s %s\n",
				r.name,
				r.version,
				truncate(r.desc, 40),
				status,
			)
		}
		strings.write_string(&builder, "\n")
	}

	total := len(vup_results) + len(official_results)
	fmt.sbprintf(&builder, "Total: %d package(s) found\n", total)

	return strings.to_string(builder)
}

// Unified search across VUP and official repos
unified_search :: proc(idx: ^Index, query: string, vup_only: bool) {
	vup_results := search_vup(idx, query)

	official_results: [dynamic]Search_Result
	if !vup_only {
		official_results = search_official(query)
	}

	total := len(vup_results) + len(official_results)

	if total == 0 {
		fmt.printf("No packages found matching '%s'\n", query)
		return
	}

	// Format results
	output := format_search_results(vup_results[:], official_results[:], context.temp_allocator)

	// Use pager if more than threshold
	if total > PAGER_THRESHOLD {
		// Write to temp file and show in less
		path, ok := diff_write_temp_file(output, context.temp_allocator)
		if ok {
			defer os.remove(path)
			run_command({"less", "-R", path})
		} else {
			// Fallback to direct print
			fmt.print(output)
		}
	} else {
		fmt.print(output)
	}
}

// Legacy search function for backwards compatibility
xbps_search :: proc(idx: ^Index, query: string) {
	unified_search(idx, query, true)
}

// Truncate string with ellipsis
truncate :: proc(s: string, max_len: int) -> string {
	if len(s) <= max_len {
		return s
	}
	if max_len < 4 {
		return s[:max_len]
	}
	return strings.concatenate({s[:max_len-3], "..."}, context.temp_allocator)
}
