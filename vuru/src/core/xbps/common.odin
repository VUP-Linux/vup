package xbps

import "core:strings"

// Common utilities for XBPS operations

import "core:mem"
import "../../utils"

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

// Parse "pkgname-version" format into (name, version) using xbps-uhelper
// This correctly handles package names with dashes (e.g., visual-studio-code-insiders-1.102.0.20250116_1)
parse_pkgver :: proc(pkgver: string) -> (name: string, version: string, ok: bool) {
	if len(pkgver) == 0 {
		return "", "", false
	}

	// Use xbps-uhelper getpkgname to correctly parse the package name
	name_output, name_ok := utils.run_command_output(
		{"xbps-uhelper", "getpkgname", pkgver},
		context.temp_allocator,
	)
	if !name_ok {
		// Fall back to simple parsing if xbps-uhelper fails
		return parse_pkgver_simple(pkgver)
	}

	parsed_name := strings.trim_space(name_output)
	if len(parsed_name) == 0 {
		return parse_pkgver_simple(pkgver)
	}

	// Use xbps-uhelper getpkgversion to correctly parse the version
	ver_output, ver_ok := utils.run_command_output(
		{"xbps-uhelper", "getpkgversion", pkgver},
		context.temp_allocator,
	)
	if !ver_ok {
		return parse_pkgver_simple(pkgver)
	}

	parsed_version := strings.trim_space(ver_output)
	if len(parsed_version) == 0 {
		return parse_pkgver_simple(pkgver)
	}

	return parsed_name, parsed_version, true
}

// Parse "pkgname-version" format into (name, version) using simple string splitting
// NOTE: This is a fallback and does NOT work correctly for packages with dashes in their names!
// Prefer parse_pkgver which uses xbps-uhelper for correct parsing.
parse_pkgver_simple :: proc(pkgver: string) -> (name: string, version: string, ok: bool) {
	if len(pkgver) == 0 {
		return "", "", false
	}

	idx := strings.last_index(pkgver, "-")
	if idx <= 0 || idx >= len(pkgver) - 1 {
		return "", "", false
	}

	return pkgver[:idx], pkgver[idx + 1:], true
}
