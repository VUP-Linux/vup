package index

import "core:mem"

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

// Free all resources in a Package_Info
package_info_free :: proc(pkg: ^Package_Info, allocator: mem.Allocator) {
	if pkg == nil do return
	
	if len(pkg.version) > 0 do delete(pkg.version, allocator)
	if len(pkg.category) > 0 do delete(pkg.category, allocator)
	if len(pkg.short_desc) > 0 do delete(pkg.short_desc, allocator)
	
	// Free repo_urls map entries
	for arch, url in pkg.repo_urls {
		delete(arch, allocator)
		delete(url, allocator)
	}
	delete(pkg.repo_urls)
}

// Free index and all its allocations
index_free :: proc(idx: ^Index) {
	if idx == nil do return
	
	for name, &pkg in idx.packages {
		package_info_free(&pkg, idx.allocator)
		delete(name, idx.allocator)
	}
	delete(idx.packages)
}

// Create a new empty Index
index_make :: proc(allocator := context.allocator) -> Index {
	return Index {
		packages  = make(map[string]Package_Info, allocator = allocator),
		allocator = allocator,
	}
}

// Get package from index (returns a view, not a copy)
index_get_package :: proc(idx: ^Index, name: string) -> (Package_Info, bool) {
	pkg, ok := idx.packages[name]
	return pkg, ok
}

// Check if package exists in index
index_has_package :: proc(idx: ^Index, name: string) -> bool {
	return name in idx.packages
}

// Get number of packages in index
index_count :: proc(idx: ^Index) -> int {
	return len(idx.packages)
}
