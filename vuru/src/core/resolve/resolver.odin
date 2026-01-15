package resolve

import "core:fmt"
import "core:strings"

import errors "../../core/errors"
import index "../../core/index"
import template "../../core/template"
import utils "../../utils"

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

	arch, arch_ok := utils.get_arch()
	if !arch_ok {
		append(&res.errors, errors.make_error(.Arch_Detection_Failed))
		return res, false
	}
	defer delete(arch)

	// Track visited packages to avoid cycles - keys are owned by this map
	visited := make(map[string]bool, allocator = allocator)
	defer {
		for key in visited {
			delete(key, allocator)
		}
		delete(visited)
	}

	// Queue of packages to process - using proper struct with int depth
	queue := make([dynamic]Queue_Item, allocator)
	defer {
		// Only free items that weren't processed (queue should be empty normally)
		for item in queue {
			delete(item.name, allocator)
		}
		delete(queue)
	}

	// Add target to queue
	append(&queue, Queue_Item{name = strings.clone(target, allocator), depth = 0})

	for len(queue) > 0 {
		// Pop from front
		item := queue[0]
		ordered_remove(&queue, 0)

		// Check if already visited
		if item.name in visited {
			delete(item.name, allocator)
			continue
		}

		// Mark as visited - clone for the map, we'll use item.name then free it
		visited[strings.clone(item.name, allocator)] = true

		// Resolve this package
		pkg, ok := resolve_package(item.name, idx, arch, item.depth, allocator)
		if !ok {
			// Not found - add to missing list
			append(&res.missing, strings.clone(item.name, allocator))

			// Add detailed error
			if item.depth == 0 {
				append(&res.errors, errors.make_error(.Package_Not_Found, item.name))
			} else {
				append(&res.errors, errors.make_error(.Dependency_Not_Found, item.name))
			}

			delete(item.name, allocator)
			continue
		}

		// Handle based on source
		switch pkg.source {
		case .Official:
			if len(pkg.version) == 0 {
				// Already installed - add to satisfied, free the pkg
				append(&res.satisfied, strings.clone(item.name, allocator))
				resolved_package_free(&pkg, allocator)
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
				template.template_free(&tmpl)
			}

		case .VUP_Build:
			append(&res.to_build, pkg)

		case .Unknown:
			append(&res.missing, strings.clone(item.name, allocator))
			resolved_package_free(&pkg, allocator)
		}

		// Free the queue item's name - we've extracted what we need
		delete(item.name, allocator)
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

	if len(r.to_install) > 0 {
		fmt.printf("Packages to install (%d):\n", len(r.to_install))
		for pkg in r.to_install {
			source_str := "official" if pkg.source == .Official else "VUP"
			fmt.printf("  %s-%s [%s]\n", pkg.name, pkg.version, source_str)
		}
		fmt.println()
	}

	if len(r.to_build) > 0 {
		fmt.printf("Packages to build (%d):\n", len(r.to_build))
		for pkg in r.to_build {
			fmt.printf("  %s-%s [build]\n", pkg.name, pkg.version)
		}
		fmt.println()
	}

	if len(r.satisfied) > 0 {
		fmt.printf("Already installed (%d):\n", len(r.satisfied))
		for name in r.satisfied {
			fmt.printf("  %s\n", name)
		}
		fmt.println()
	}

	if len(r.missing) > 0 {
		fmt.printf("Missing/Unresolvable (%d):\n", len(r.missing))
		for name in r.missing {
			fmt.printf("  %s\n", name)
		}
		fmt.println()
	}
}
