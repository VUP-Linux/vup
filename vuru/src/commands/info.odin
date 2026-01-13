package commands

import "core:fmt"
import "core:strings"

import index "../core/index"
import resolve "../core/resolve"
import template "../core/template"
import utils "../utils"

// Info command implementation
info_run :: proc(args: []string, config: ^Config) -> int {
	if len(args) == 0 {
		utils.log_error("Usage: vuru info <package>")
		return 1
	}

	// Load index
	idx, ok := index.index_load_or_fetch(config.index_url, false)
	if !ok {
		utils.log_error("Failed to load package index")
		return 1
	}
	defer index.index_free(&idx)

	for pkg_name in args {
		// Check VUP first
		if pkg, ok := index.index_get_package(&idx, pkg_name); ok {
			fmt.println()
			fmt.printf("Package: %s\n", pkg_name)
			fmt.printf("Version: %s\n", pkg.version)
			fmt.printf("Category: %s\n", pkg.category)
			fmt.printf("Description: %s\n", pkg.short_desc)
			fmt.printf("Source: VUP\n")

			// Show architectures
			fmt.print("Architectures: ")
			first := true
			for arch, _ in pkg.repo_urls {
				if !first {fmt.print(", ")}
				fmt.print(arch)
				first = false
			}
			fmt.println()

			// Try to fetch and show template info
			if tmpl, tmpl_ok := resolve.fetch_and_parse_template(
				pkg.category,
				pkg_name,
				context.temp_allocator,
			); tmpl_ok {
				defer template.template_free(&tmpl)
				if len(tmpl.depends) > 0 {
					fmt.printf(
						"Dependencies: %s\n",
						strings.join(tmpl.depends, " ", context.temp_allocator),
					)
				}
				if len(tmpl.makedepends) > 0 {
					fmt.printf(
						"Build deps: %s\n",
						strings.join(tmpl.makedepends, " ", context.temp_allocator),
					)
				}
			}

			fmt.println()
		} else {
			// Check official repos
			if utils.run_command({"xbps-query", "-R", pkg_name}) != 0 {
				utils.log_error("Package '%s' not found", pkg_name)
				return 1
			}
		}
	}

	return 0
}
