package config

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

Install_Mode :: enum { Package, Local }

// Simple key=value configuration with # comments and a boolean build preference.
// Reject unsupported syntax and keys instead of silently ignoring mistakes.
parse_preferences :: proc(content: string) -> (Install_Mode, bool) {
	mode: Install_Mode
	seen := false
	text := content
	for raw_line in strings.split_lines_iterator(&text) {
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] == '#' do continue
		sep := strings.index_byte(line, '=')
		if sep < 0 || strings.trim_space(line[:sep]) != "build_local" || seen do return .Package, false
		value := strings.trim_space(line[sep+1:])
		comment := strings.index_byte(value, '#')
		if comment >= 0 do value = strings.trim_space(value[:comment])
		switch value {
		case "true": mode = .Local
		case "false": mode = .Package
		case: return .Package, false
		}
		seen = true
	}
	return mode, true
}

preferences_dir :: proc() -> string {
	xdg := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
	if len(xdg) > 0 && xdg[0] == '/' do return fmt.tprintf("%s/vuru", xdg)
	home := os.get_env("HOME", context.temp_allocator)
	if len(home) > 0 && home[0] == '/' do return fmt.tprintf("%s/.config/vuru", home)
	return ""
}

// Noninteractive, --yes and dry-run invocations never create preferences.
load_preferences :: proc(prompt: bool) -> (Install_Mode, bool) {
	dir := preferences_dir()
	if dir == "" do return .Package, true
	path := fmt.tprintf("%s/config.conf", dir)
	data, err := os.read_entire_file(path, context.allocator)
	if err == nil {
		defer delete(data)
		mode, ok := parse_preferences(string(data))
		if !ok do fmt.eprintf("Invalid %s: expected build_local = true or false\n", path)
		return mode, ok
	}
	if err != os.General_Error.Not_Exist {
		fmt.eprintf("Cannot read %s: %v\n", path, err)
		return .Package, false
	}
	if !prompt || !bool(posix.isatty(0)) || !bool(posix.isatty(1)) do return .Package, true

	fmt.println("Welcome to Vuru! Choose how to install VUP packages.")
	fmt.println("Local mode downloads templates and compiles with xbps-src; it needs build tools, disk space and time.")
	mode: Install_Mode
	for {
		fmt.print("Build locally by default? [y/N] ")
		buf: [128]u8
		n, read_err := os.read(os.stdin, buf[:])
		if read_err != nil || n <= 0 do return .Package, true
		answer := strings.to_lower(strings.trim_space(string(buf[:n])), context.temp_allocator)
		if answer == "y" || answer == "yes" { mode = .Local; break }
		if answer == "" || answer == "n" || answer == "no" { break }
		fmt.println("Please enter yes or no.")
	}
	if !os.is_dir(dir) && os.make_directory_all(dir) != nil {
		fmt.eprintf("Cannot create %s\n", dir)
		return .Package, false
	}
	content := mode == .Local ? "build_local = true\n" : "build_local = false\n"
	if os.write_entire_file(path, transmute([]u8)content) != nil {
		fmt.eprintf("Cannot write %s\n", path)
		return .Package, false
	}
	fmt.printf("Saved %s. Override with install --build or install --prebuilt.\n", path)
	return mode, true
}
