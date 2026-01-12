package main

import "core:fmt"
import "core:strings"

// Search the index for packages matching a query
xbps_search :: proc(idx: ^Index, query: string) {
	query_lower := strings.to_lower(query, context.temp_allocator)

	// Count matches first
	count := 0
	for name, pkg in idx.packages {
		name_lower := strings.to_lower(name, context.temp_allocator)
		desc_lower := strings.to_lower(pkg.short_desc, context.temp_allocator)

		if strings.contains(name_lower, query_lower) || strings.contains(desc_lower, query_lower) {
			count += 1
		}
	}

	if count == 0 {
		fmt.printf("No packages found matching '%s'\n", query)
		return
	}

	fmt.println()
	fmt.printf("%-24s %-15s %-20s\n", "PACKAGE", "VERSION", "CATEGORY")
	fmt.println("-------------------------------------------------------------")

	for name, pkg in idx.packages {
		name_lower := strings.to_lower(name, context.temp_allocator)
		desc_lower := strings.to_lower(pkg.short_desc, context.temp_allocator)

		if strings.contains(name_lower, query_lower) || strings.contains(desc_lower, query_lower) {
			ver_str := pkg.version if len(pkg.version) > 0 else "?"
			cat_str := pkg.category if len(pkg.category) > 0 else "?"

			fmt.printf("%-24s %-15s %-20s\n", name, ver_str, cat_str)
		}
	}

	fmt.println()
	fmt.printf("%d package(s) found\n", count)
}
