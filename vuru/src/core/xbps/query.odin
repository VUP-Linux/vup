package xbps

import "core:mem"
import "core:strings"

// Type alias for command runner functions


// Query operations using xbps-query

// Get the currently installed version of a package
// Returns empty string if not installed
get_installed_version :: proc(
	pkg_name: string,
	run_cmd: Command_Runner_Output,
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	output, ok := run_cmd({"xbps-query", pkg_name}, context.temp_allocator)
	if !ok {
		return "", false
	}

	output_iter := output
	for line in strings.split_lines_iterator(&output_iter) {
		if strings.has_prefix(line, "pkgver:") {
			value := strings.trim_space(line[7:])
			_, version, parse_ok := parse_pkgver(value)
			if parse_ok {
				return strings.clone(version, allocator), true
			}
		}
	}

	return "", false
}

// List all installed packages as (name, version) pairs
list_installed :: proc(
	run_cmd: Command_Runner_Output,
	allocator := context.allocator,
) -> (
	[][2]string,
	bool,
) {
	output, ok := run_cmd({"xbps-query", "-l"}, context.temp_allocator)
	if !ok {
		return nil, false
	}

	result := make([dynamic][2]string, allocator)
	output_iter := output

	for line in strings.split_lines_iterator(&output_iter) {
		parts := strings.fields(line, context.temp_allocator)
		if len(parts) < 2 {
			continue
		}

		name, version, parse_ok := parse_pkgver(parts[1])
		if parse_ok {
			append(
				&result,
				[2]string{strings.clone(name, allocator), strings.clone(version, allocator)},
			)
		}
	}

	return result[:], true
}
