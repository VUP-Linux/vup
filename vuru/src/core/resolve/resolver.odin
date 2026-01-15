package resolve

import "core:fmt"
import "core:strings"

import errors "../../core/errors"
import index "../../core/index"
import template "../../core/template"
import utils "../../utils"
import config "../config"

// Check if a package is installed (silently)
is_pkg_installed :: proc(name: string) -> bool {
	return utils.run_command_silent({"xbps-query", name}) == 0
}

// Check if package exists in official Void repos
is_in_official_repos :: proc(name: string) -> (version: string, ok: bool) {
	output, cmd_ok := utils.run_command_output({"xbps-query", "-R", name}, context.temp_allocator)
	if !cmd_ok {
		return "", false
	}

	// Parse pkgver from output
	for line in strings.split_lines_iterator(&output) {
		if strings.has_prefix(line, "pkgver:") {
			value := strings.trim_space(line[7:])
			// Format: name-version
			if idx := strings.last_index(value, "-"); idx > 0 {
				return strings.clone(value[idx + 1:], context.temp_allocator), true
			}
		}
	}

	return "", false
}

// Resolve a single package - returns a Resolved_Package with allocated strings
// Caller must free the package on success, or handle that nothing was allocated on failure
resolve_package :: proc(
	name: string,
	idx: ^index.Index,
	arch: string,
	depth: int,
	allocator := context.allocator,
) -> (
	Resolved_Package,
	bool,
) {
	// 1. Check if already installed
	if is_pkg_installed(name) {
		return Resolved_Package {
				name    = strings.clone(name, allocator),
				source  = .Official, // Treat as satisfied (empty version = already installed)
				version = "",
				depth   = depth,
			}, true
	}

	// 2. Check VUP index for binary
	if vup_pkg, ok := index.index_get_package(idx, name); ok {
		if url, url_ok := vup_pkg.repo_urls[arch]; url_ok {
			return Resolved_Package {
					name = strings.clone(name, allocator),
					source = .VUP,
					version = strings.clone(vup_pkg.version, allocator),
					repo_url = strings.clone(url, allocator),
					category = strings.clone(vup_pkg.category, allocator),
					depth = depth,
				},
				true
		}
	}

	// 3. Check official Void repos
	if version, ok := is_in_official_repos(name); ok {
		return Resolved_Package {
				name = strings.clone(name, allocator),
				source = .Official,
				version = strings.clone(version, allocator),
				depth = depth,
			},
			true
	}

	// 4. Not found anywhere - return false, no allocations made
	return {}, false
}

// Resolve dependencies for a target package
resolve_deps :: proc(
	target: string,
	idx: ^index.Index,
	include_makedeps: bool,
	allocator := context.allocator,
) -> (
	Resolution,
	bool,
) {
	res := resolution_make(allocator)

	arch, arch_ok := config.get_arch()
	if !arch_ok {
		append(&res.errors, errors.make_error(.Arch_Detection_Failed))
		return res, false
	}


	// Track visited packages to avoid cycles - keys are owned by this map
	visited := make(map[string]bool, allocator = allocator)


	// Queue of packages to process - using proper struct with int depth
	queue := make([dynamic]Queue_Item, allocator)


	// Add target to queue
	append(&queue, Queue_Item{name = strings.clone(target, allocator), depth = 0})

	for len(queue) > 0 {
		// Pop from front
		item := queue[0]
		ordered_remove(&queue, 0)

		// Check if already visited
		if item.name in visited {

			continue
		}

		// Mark as visited - clone for the map, we'll use item.name then free it
		visited[strings.clone(item.name, allocator)] = true

		// Resolve this package
		pkg, ok := resolve_package(item.name, idx, arch, item.depth, allocator)
		if !ok {
			// Not found - add to missing list (clone persists)
			cloned_name := strings.clone(item.name, allocator)
			append(&res.missing, cloned_name)

			// Add detailed error - use the cloned name that will persist
			if item.depth == 0 {
				append(&res.errors, errors.make_error(.Package_Not_Found, cloned_name))
			} else {
				append(&res.errors, errors.make_error(.Dependency_Not_Found, cloned_name))
			}


			continue
		}

		// Handle based on source
		switch pkg.source {
		case .Official:
			if len(pkg.version) == 0 {
				// Already installed - add to satisfied, free the pkg
				append(&res.satisfied, strings.clone(item.name, allocator))

			} else {
				// Needs to be installed from official repos
				append(&res.to_install, pkg)
			}

		case .VUP:
			append(&res.to_install, pkg)

			// Resolve VUP package dependencies from template
			if tmpl, tmpl_ok := fetch_and_parse_template(pkg.category, item.name, allocator);
			   tmpl_ok {
				// Queue runtime dependencies
				for dep in tmpl.depends {
					if dep not_in visited {
						append(
							&queue,
							Queue_Item {
								name = strings.clone(dep, allocator),
								depth = item.depth + 1,
							},
						)
					}
				}

				// Queue build dependencies if requested
				if include_makedeps {
					for dep in tmpl.makedepends {
						if dep not_in visited {
							append(
								&queue,
								Queue_Item {
									name = strings.clone(dep, allocator),
									depth = item.depth + 1,
								},
							)
						}
					}
				}

				// Free template after extracting deps

			}

		case .VUP_Build:
			append(&res.to_build, pkg)

		case .Unknown:
			append(&res.missing, strings.clone(item.name, allocator))

		}

		// Free the queue item's name - we've extracted what we need

	}

	return res, true
}

// Fetch and parse a VUP template
fetch_and_parse_template :: proc(
	category: string,
	pkg_name: string,
	allocator := context.allocator,
) -> (
	template.Template,
	bool,
) {
	content, ok := template.fetch_template(category, pkg_name, context.temp_allocator)
	if !ok {
		return {}, false
	}

	return template.template_parse(content, allocator)
}

// Print resolution summary
resolution_print :: proc(r: ^Resolution) {
	fmt.println()

	// Separate VUP and official packages
	vup_pkgs: [dynamic]string
	official_pkgs: [dynamic]string


	for pkg in r.to_install {
		if pkg.source == .VUP {
			append(&vup_pkgs, pkg.name)
		} else {
			append(&official_pkgs, pkg.name)
		}
	}

	if len(vup_pkgs) > 0 {
		fmt.printf("VUP packages (%d):\n", len(vup_pkgs))
		fmt.print(" ")
		for name, i in vup_pkgs {
			if i > 0 {
				fmt.print(" ")
			}
			fmt.print(name)
		}
		fmt.println()
		fmt.println()
	}

	if len(official_pkgs) > 0 {
		fmt.printf("Official deps (%d):\n", len(official_pkgs))
		fmt.print(" ")
		for name, i in official_pkgs {
			if i > 0 {
				fmt.print(" ")
			}
			fmt.print(name)
		}
		fmt.println()
	}

	if len(r.to_build) > 0 {
		fmt.printf("Build from source (%d):\n", len(r.to_build))
		fmt.print(" ")
		for pkg, i in r.to_build {
			if i > 0 {
				fmt.print(" ")
			}
			fmt.print(pkg.name)
		}
		fmt.println()
		fmt.println()
	}

	if len(r.satisfied) > 0 {
		fmt.printf("Already installed (%d):\n", len(r.satisfied))
		fmt.print(" ")
		for name, i in r.satisfied {
			if i > 0 {
				fmt.print(" ")
			}
			fmt.print(name)
		}
		fmt.println()
	}

	if len(r.missing) > 0 {
		fmt.printf("Missing (%d):\n", len(r.missing))
		fmt.print(" ")
		for name, i in r.missing {
			if i > 0 {
				fmt.print(" ")
			}
			fmt.print(name)
		}
		fmt.println()
	}
}
