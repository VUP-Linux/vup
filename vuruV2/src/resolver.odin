package main

import "core:fmt"
import "core:mem"
import "core:strings"

// Package source - where a package comes from
Package_Source :: enum {
	Unknown,
	Official,  // Official Void Linux repos
	VUP,       // VUP binary repo
	VUP_Build, // VUP source (needs building)
}

// Resolved package info
Resolved_Package :: struct {
	name:        string,
	version:     string,
	source:      Package_Source,
	repo_url:    string,    // For binary install
	category:    string,    // For VUP packages
	template:    ^Template, // For VUP_Build
	depth:       int,       // Dependency depth (0 = target, 1+ = deps)
}

// Resolution result
Resolution :: struct {
	// Packages to install from binary repos (in dependency order)
	to_install:  [dynamic]Resolved_Package,

	// Packages to build from source (in dependency order)
	to_build:    [dynamic]Resolved_Package,

	// Already satisfied
	satisfied:   [dynamic]string,

	// Unresolvable
	missing:     [dynamic]string,

	allocator:   mem.Allocator,
}

resolution_free :: proc(r: ^Resolution) {
	for pkg in r.to_install {
		delete(pkg.name, r.allocator)
		delete(pkg.version, r.allocator)
		delete(pkg.repo_url, r.allocator)
		delete(pkg.category, r.allocator)
	}
	delete(r.to_install)

	for pkg in r.to_build {
		delete(pkg.name, r.allocator)
		delete(pkg.version, r.allocator)
		delete(pkg.category, r.allocator)
		if pkg.template != nil {
			template_free(pkg.template)
			free(pkg.template, r.allocator)
		}
	}
	delete(r.to_build)

	for s in r.satisfied {delete(s, r.allocator)}
	delete(r.satisfied)

	for s in r.missing {delete(s, r.allocator)}
	delete(r.missing)
}

// Check if a package is installed (silently)
is_pkg_installed :: proc(name: string) -> bool {
	return run_command_silent({"xbps-query", name}) == 0
}

// Check if package exists in official Void repos
is_in_official_repos :: proc(name: string) -> (version: string, ok: bool) {
	output, cmd_ok := run_command_output({"xbps-query", "-R", name}, context.temp_allocator)
	if !cmd_ok {
		return "", false
	}

	// Parse pkgver from output
	for line in strings.split_lines_iterator(&output) {
		if strings.has_prefix(line, "pkgver:") {
			value := strings.trim_space(line[7:])
			// Format: name-version
			if idx := strings.last_index(value, "-"); idx > 0 {
				return strings.clone(value[idx+1:], context.temp_allocator), true
			}
		}
	}

	return "", false
}

// Resolve a single package
resolve_package :: proc(
	name: string,
	idx: ^Index,
	arch: string,
	depth: int,
	allocator := context.allocator,
) -> (Resolved_Package, bool) {

	pkg := Resolved_Package{
		name = strings.clone(name, allocator),
		depth = depth,
	}

	// 1. Check if already installed
	if is_pkg_installed(name) {
		pkg.source = .Official // Treat as satisfied
		pkg.version = ""
		return pkg, true
	}

	// 2. Check VUP index for binary
	if vup_pkg, ok := index_get_package(idx, name); ok {
		if url, url_ok := vup_pkg.repo_urls[arch]; url_ok {
			pkg.source = .VUP
			pkg.version = strings.clone(vup_pkg.version, allocator)
			pkg.repo_url = strings.clone(url, allocator)
			pkg.category = strings.clone(vup_pkg.category, allocator)
			return pkg, true
		}
	}

	// 3. Check official Void repos
	if version, ok := is_in_official_repos(name); ok {
		pkg.source = .Official
		pkg.version = strings.clone(version, allocator)
		return pkg, true
	}

	// 4. Not found anywhere
	delete(pkg.name, allocator)
	return {}, false
}

// Resolve dependencies for a target package
resolve_deps :: proc(
	target: string,
	idx: ^Index,
	include_makedeps: bool,
	allocator := context.allocator,
) -> (Resolution, bool) {

	res := Resolution{
		to_install = make([dynamic]Resolved_Package, allocator),
		to_build = make([dynamic]Resolved_Package, allocator),
		satisfied = make([dynamic]string, allocator),
		missing = make([dynamic]string, allocator),
		allocator = allocator,
	}

	arch, arch_ok := get_arch()
	if !arch_ok {
		log_error("Failed to detect architecture")
		return res, false
	}
	defer delete(arch)

	// Track visited packages to avoid cycles
	visited := make(map[string]bool, allocator = context.temp_allocator)

	// Queue of packages to process: (name, depth)
	queue := make([dynamic][2]string, context.temp_allocator)
	append(&queue, [2]string{target, "0"})

	for len(queue) > 0 {
		item := queue[0]
		ordered_remove(&queue, 0)

		name := item[0]
		depth := parse_int(item[1])

		if name in visited {
			continue
		}
		visited[name] = true

		// Resolve this package
		pkg, ok := resolve_package(name, idx, arch, depth, allocator)
		if !ok {
			append(&res.missing, strings.clone(name, allocator))
			continue
		}

		// Handle based on source
		switch pkg.source {
		case .Official:
			if len(pkg.version) == 0 {
				// Already installed
				append(&res.satisfied, strings.clone(name, allocator))
				delete(pkg.name, allocator)
			} else {
				append(&res.to_install, pkg)
			}

		case .VUP:
			append(&res.to_install, pkg)

			// Resolve VUP package dependencies from template
			if template, tmpl_ok := fetch_and_parse_template(pkg.category, name, allocator); tmpl_ok {
				defer template_free(&template)

				for dep in template.depends {
					if dep not_in visited {
						append(&queue, [2]string{dep, int_to_string(depth + 1, context.temp_allocator)})
					}
				}

				if include_makedeps {
					for dep in template.makedepends {
						if dep not_in visited {
							append(&queue, [2]string{dep, int_to_string(depth + 1, context.temp_allocator)})
						}
					}
				}
			}

		case .VUP_Build:
			append(&res.to_build, pkg)

		case .Unknown:
			append(&res.missing, strings.clone(name, allocator))
			delete(pkg.name, allocator)
		}
	}

	return res, true
}

// Fetch and parse a VUP template
fetch_and_parse_template :: proc(
	category: string,
	pkg_name: string,
	allocator := context.allocator,
) -> (Template, bool) {
	content, ok := fetch_template(category, pkg_name, context.temp_allocator)
	if !ok {
		return {}, false
	}

	return template_parse(content, allocator)
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
