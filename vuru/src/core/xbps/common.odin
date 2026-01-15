package xbps

import "core:strings"

// Common utilities for XBPS operations

import "core:mem"

// Type alias for command runner functions
Command_Runner :: proc(args: []string) -> int
Command_Runner_Output :: proc(args: []string, allocator: mem.Allocator) -> (string, bool)


// Build a command argument list from variadic strings
// Returns a slice that the caller should delete when done
build_args :: proc(args: ..string, allocator := context.allocator) -> []string {
	result := make([dynamic]string, allocator)
	for arg in args {
		append(&result, arg)
	}
	return result[:]
}

// Build args with optional -y flag
build_args_with_yes :: proc(
	yes: bool,
	args: ..string,
	allocator := context.allocator,
) -> [dynamic]string {
	result := make([dynamic]string, allocator)
	for arg in args {
		append(&result, arg)
	}
	if yes {
		append(&result, "-y")
	}
	return result
}

// Parse "pkgname-version" format into (name, version)
parse_pkgver :: proc(pkgver: string) -> (name: string, version: string, ok: bool) {
	if len(pkgver) == 0 {
		return "", "", false
	}

	idx := strings.last_index(pkgver, "-")
	if idx <= 0 || idx >= len(pkgver) - 1 {
		return "", "", false
	}

	return pkgver[:idx], pkgver[idx + 1:], true
}
