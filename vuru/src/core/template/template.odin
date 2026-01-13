package template

import utils "../../utils"

import "core:mem"
import "core:os"
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
	content, ok := utils.read_file(path, allocator)
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

	// Process line by line
	lines := content
	for line in strings.split_lines_iterator(&lines) {
		// Skip comments and empty lines
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}

		// Look for variable assignments: name=value or name="value"
		eq_idx := strings.index(trimmed, "=")
		if eq_idx <= 0 {
			continue
		}

		name := trimmed[:eq_idx]
		value_raw := trimmed[eq_idx + 1:]

		// Strip quotes if present
		value := strip_quotes(value_raw)

		switch name {
		case "pkgname":
			t.pkgname = strings.clone(value, allocator)
		case "version":
			t.version = strings.clone(value, allocator)
		case "revision":
			t.revision = parse_int(value)
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
			t.archs = split_and_clone(value, allocator)
		case "depends":
			t.depends = split_and_clone(value, allocator)
		case "makedepends":
			t.makedepends = split_and_clone(value, allocator)
		case "hostmakedepends":
			t.hostmakedeps = split_and_clone(value, allocator)
		case "checkdepends":
			t.checkdepends = split_and_clone(value, allocator)
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

// Get full version string (version_revision)
template_full_version :: proc(t: ^Template, allocator := context.allocator) -> string {
	if t.revision > 0 {
		return strings.concatenate(
			{t.version, "_", int_to_string(t.revision, context.temp_allocator)},
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

// --- Helper functions ---

strip_quotes :: proc(s: string) -> string {
	if len(s) < 2 {
		return s
	}

	if (s[0] == '"' && s[len(s) - 1] == '"') || (s[0] == '\'' && s[len(s) - 1] == '\'') {
		return s[1:len(s) - 1]
	}
	return s
}

split_and_clone :: proc(s: string, allocator: mem.Allocator) -> []string {
	if len(s) == 0 {
		return nil
	}

	parts := strings.fields(s, context.temp_allocator)
	result := make([]string, len(parts), allocator)

	for p, i in parts {
		result[i] = strings.clone(p, allocator)
	}

	return result
}

parse_int :: proc(s: string) -> int {
	result := 0
	for c in s {
		if c >= '0' && c <= '9' {
			result = result * 10 + int(c - '0')
		} else {
			break
		}
	}
	return result
}

int_to_string :: proc(n: int, allocator := context.allocator) -> string {
	if n == 0 {
		return strings.clone("0", allocator)
	}

	buf: [20]u8
	i := len(buf)
	v := n

	for v > 0 {
		i -= 1
		buf[i] = u8('0' + (v % 10))
		v /= 10
	}

	return strings.clone(string(buf[i:]), allocator)
}
