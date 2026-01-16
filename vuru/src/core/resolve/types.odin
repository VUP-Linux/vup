package resolve

import "core:mem"
import "core:strings"

import errors "../../core/errors"
import template "../../core/template"

// Package source - where a package comes from
Package_Source :: enum {
	Unknown,
	Official, // Official Void Linux repos
	VUP, // VUP binary repo
	VUP_Build, // VUP source (needs building)
}

// Resolved package info
Resolved_Package :: struct {
	name:     string,
	version:  string,
	source:   Package_Source,
	repo_url: string, // For binary install
	category: string, // For VUP packages
	template: ^template.Template, // For VUP_Build
	depth:    int, // Dependency depth (0 = target, 1+ = deps)
}

// Resolution result
Resolution :: struct {
	// The target package being resolved
	target:     string,

	// Packages to install from binary repos (in dependency order)
	to_install: [dynamic]Resolved_Package,

	// Packages to build from source (in dependency order)
	to_build:   [dynamic]Resolved_Package,

	// Already satisfied
	satisfied:  [dynamic]string,

	// Unresolvable - names only (legacy)
	missing:    [dynamic]string,

	// Detailed errors for each failure
	errors:     [dynamic]errors.Error,
	allocator:  mem.Allocator,
}

// Internal queue item for BFS traversal
Queue_Item :: struct {
	name:  string,
	depth: int,
}

// Free all resources in a Resolved_Package
resolved_package_free :: proc(pkg: ^Resolved_Package, allocator: mem.Allocator) {
	if len(pkg.name) > 0 do delete(pkg.name, allocator)
	if len(pkg.version) > 0 do delete(pkg.version, allocator)
	if len(pkg.repo_url) > 0 do delete(pkg.repo_url, allocator)
	if len(pkg.category) > 0 do delete(pkg.category, allocator)
	if pkg.template != nil {
		template.template_free(pkg.template)
		free(pkg.template, allocator)
		pkg.template = nil
	}
}

// Free all resources in a Resolution
resolution_free :: proc(r: ^Resolution) {
	if r == nil do return

	// Free to_install packages
	for &pkg in r.to_install {
		resolved_package_free(&pkg, r.allocator)
	}
	delete(r.to_install)

	// Free to_build packages
	for &pkg in r.to_build {
		resolved_package_free(&pkg, r.allocator)
	}
	delete(r.to_build)

	// Free satisfied strings
	for s in r.satisfied {
		delete(s, r.allocator)
	}
	delete(r.satisfied)

	// Free missing strings
	for s in r.missing {
		delete(s, r.allocator)
	}
	delete(r.missing)

	// Free target
	if len(r.target) > 0 {
		delete(r.target, r.allocator)
	}

	// Errors are temp-based views, ctx is not owned - just free the array
	delete(r.errors)
}

// Create a new empty Resolution
resolution_make :: proc(target: string = "", allocator := context.allocator) -> Resolution {
	return Resolution {
		target = strings.clone(target, allocator) if len(target) > 0 else "",
		to_install = make([dynamic]Resolved_Package, allocator),
		to_build = make([dynamic]Resolved_Package, allocator),
		satisfied = make([dynamic]string, allocator),
		missing = make([dynamic]string, allocator),
		errors = make([dynamic]errors.Error, allocator),
		allocator = allocator,
	}
}
