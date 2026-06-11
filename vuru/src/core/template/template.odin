package template

import utils "../../utils"

import "core:mem"
import "core:strings"

// Parsed template information from xbps-src template file
Template :: struct {
	// Core fields
	pkgname:       string,
	version:       string,
	revision:      int,
	short_desc:    string,
	maintainer:    string,
	license:       string,
	homepage:      string,

	// Dependencies
	depends:       []string, // Runtime dependencies
	makedepends:   []string, // Build-time dependencies
	hostmakedeps:  []string, // Host build dependencies (for cross-compile)
	checkdepends:  []string, // Test dependencies

	// Build info
	archs:         []string, // Supported architectures ("x86_64 aarch64" etc)
	build_style:   string, // gnu-configure, cmake, meson, etc.
	create_wrksrc: bool,

	// Restrictions
	restricted:    bool,
	nostrip:       bool,
	nopie:         bool,

	// Source
	distfiles:     []string,
	checksum:      []string,

	// Raw content for display/diff
	raw_content:   string,

	// Allocator used for this template
	allocator:     mem.Allocator,
}

// Free all memory associated with a template
template_free :: proc(t: ^Template) {
	if t.allocator.procedure == nil {
		return
	}

	delete(t.pkgname, t.allocator)
	delete(t.version, t.allocator)
	delete(t.short_desc, t.allocator)
	delete(t.maintainer, t.allocator)
	delete(t.license, t.allocator)
	delete(t.homepage, t.allocator)
	delete(t.build_style, t.allocator)
	delete(t.raw_content, t.allocator)

	for s in t.depends {delete(s, t.allocator)}
	delete(t.depends, t.allocator)

	for s in t.makedepends {delete(s, t.allocator)}
	delete(t.makedepends, t.allocator)

	for s in t.hostmakedeps {delete(s, t.allocator)}
	delete(t.hostmakedeps, t.allocator)

	for s in t.checkdepends {delete(s, t.allocator)}
	delete(t.checkdepends, t.allocator)

	for s in t.archs {delete(s, t.allocator)}
	delete(t.archs, t.allocator)

	for s in t.distfiles {delete(s, t.allocator)}
	delete(t.distfiles, t.allocator)

	for s in t.checksum {delete(s, t.allocator)}
	delete(t.checksum, t.allocator)
}

// Parse a template file from disk
template_parse_file :: proc(path: string, allocator := context.allocator) -> (Template, bool) {
	// Read with temp allocator - template_parse will clone what it needs
	content, ok := utils.read_file(path, context.temp_allocator)
	if !ok {
		return {}, false
	}

	return template_parse(content, allocator)
}

// Parse template content string
template_parse :: proc(content: string, allocator := context.allocator) -> (Template, bool) {
	t := Template {
		allocator   = allocator,
		raw_content = strings.clone(content, allocator),
	}

	// First pass: extract multi-line values and single-line values
	vars := parse_shell_variables(content, context.temp_allocator)
	
	// Process parsed variables
	for name, value in vars {
		switch name {
		case "pkgname":
			t.pkgname = strings.clone(value, allocator)
		case "version":
			t.version = strings.clone(value, allocator)
		case "revision":
			t.revision = utils.parse_int(value)
		case "short_desc":
			t.short_desc = strings.clone(value, allocator)
		case "maintainer":
			t.maintainer = strings.clone(value, allocator)
		case "license":
			t.license = strings.clone(value, allocator)
		case "homepage":
			t.homepage = strings.clone(value, allocator)
		case "build_style":
			t.build_style = strings.clone(value, allocator)
		case "archs":
			t.archs = utils.split_and_clone(value, allocator)
		case "depends":
			t.depends = utils.split_and_clone(value, allocator)
		case "makedepends":
			t.makedepends = utils.split_and_clone(value, allocator)
		case "hostmakedepends":
			t.hostmakedeps = utils.split_and_clone(value, allocator)
		case "checkdepends":
			t.checkdepends = utils.split_and_clone(value, allocator)
		case "restricted":
			t.restricted = value == "yes"
		case "nostrip":
			t.nostrip = value == "yes"
		case "nopie":
			t.nopie = value == "yes"
		case "create_wrksrc":
			t.create_wrksrc = value == "yes"
		}
	}

	// Validate required fields
	if len(t.pkgname) == 0 || len(t.version) == 0 {
		template_free(&t)
		return {}, false
	}

	return t, true
}

// Parse shell-style variable assignments, handling multi-line quoted values
@(private)
parse_shell_variables :: proc(content: string, allocator := context.allocator) -> map[string]string {
	vars := make(map[string]string, allocator = allocator)
	
	lines := strings.split_lines(content, context.temp_allocator)
	i := 0
	
	for i < len(lines) {
		line := strings.trim_space(lines[i])
		
		// Skip comments and empty lines
		if len(line) == 0 || line[0] == '#' {
			i += 1
			continue
		}
		
		// Look for variable assignment
		eq_idx := strings.index(line, "=")
		if eq_idx <= 0 {
			i += 1
			continue
		}
		
		name := line[:eq_idx]
		value_start := line[eq_idx + 1:]
		
		// Check if this is a multi-line quoted value
		if len(value_start) > 0 && value_start[0] == '"' {
			// Check if closing quote is on same line
			if len(value_start) > 1 && strings.index(value_start[1:], "\"") >= 0 {
				// Single line quoted value
				vars[strings.clone(name, allocator)] = strings.clone(utils.strip_quotes(value_start), allocator)
			} else {
				// Multi-line value - collect until closing quote
				builder := strings.builder_make(context.temp_allocator)
				
				// Add content after opening quote (skip the quote itself)
				if len(value_start) > 1 {
					strings.write_string(&builder, value_start[1:])
				}
				
				i += 1
				for i < len(lines) {
					next_line := lines[i]
					
					// Check if this line has the closing quote
					if quote_idx := strings.index(next_line, "\""); quote_idx >= 0 {
						// Add content before closing quote
						strings.write_string(&builder, " ")
						strings.write_string(&builder, strings.trim_space(next_line[:quote_idx]))
						break
					} else {
						// Add entire line (trimmed)
						trimmed := strings.trim_space(next_line)
						if len(trimmed) > 0 {
							strings.write_string(&builder, " ")
							strings.write_string(&builder, trimmed)
						}
					}
					i += 1
				}
				
				vars[strings.clone(name, allocator)] = strings.clone(strings.trim_space(strings.to_string(builder)), allocator)
			}
		} else if len(value_start) > 0 && value_start[0] == '\'' {
			// Single-quoted value (always single line in shell)
			vars[strings.clone(name, allocator)] = strings.clone(utils.strip_quotes(value_start), allocator)
		} else {
			// Unquoted value
			vars[strings.clone(name, allocator)] = strings.clone(value_start, allocator)
		}
		
		i += 1
	}
	
	return vars
}

// Get full version string (version_revision)
template_full_version :: proc(t: ^Template, allocator := context.allocator) -> string {
	if t.revision > 0 {
		return strings.concatenate(
			{t.version, "_", utils.int_to_string(t.revision, context.temp_allocator)},
			allocator,
		)
	}
	return strings.clone(t.version, allocator)
}

// Check if template supports given architecture
template_supports_arch :: proc(t: ^Template, arch: string) -> bool {
	if len(t.archs) == 0 {
		return true // No restriction = all archs
	}

	for a in t.archs {
		if a == arch || a == "noarch" {
			return true
		}
	}
	return false
}

// Get all dependencies (runtime + build)
template_all_deps :: proc(t: ^Template, allocator := context.allocator) -> []string {
	result := make([dynamic]string, allocator)

	for d in t.depends {
		append(&result, strings.clone(d, allocator))
	}
	for d in t.makedepends {
		append(&result, strings.clone(d, allocator))
	}
	for d in t.hostmakedeps {
		append(&result, strings.clone(d, allocator))
	}

	return result[:]
}
