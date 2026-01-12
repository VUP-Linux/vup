package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/linux"

// Define execvp since it's missing from core:c/libc sometimes or not exported commonly
foreign import libc "system:c"
foreign libc {
	execvp :: proc(file: cstring, argv: [^]cstring) -> c.int ---
}

// ANSI color codes
COLOR_RESET :: "\033[0m"
COLOR_INFO :: "\033[1;34m"
COLOR_ERROR :: "\033[1;31m"

// Log an informational message to stdout
log_info :: proc(msg: string, args: ..any) {
	fmt.printf("%s[info]%s ", COLOR_INFO, COLOR_RESET)
	fmt.printf(msg, ..args)
	fmt.println()
}

// Log an error message to stderr
log_error :: proc(msg: string, args: ..any) {
	fmt.eprintf("%s[error]%s ", COLOR_ERROR, COLOR_RESET)
	fmt.eprintf(msg, ..args)
	fmt.eprintln()
}

// Read entire file contents
read_file :: proc(path: string, allocator := context.allocator) -> (string, bool) {
	data, ok := os.read_entire_file(path, allocator)
	if !ok {
		return "", false
	}
	return string(data), true
}

// Write string content to a file
write_file :: proc(path: string, content: string) -> bool {
	return os.write_entire_file(path, transmute([]u8)content)
}

// Get the current system architecture name
get_arch :: proc() -> (string, bool) {
	uts: linux.UTS_Name
	if linux.uname(&uts) != nil {
		return "", false
	}

	machine_name := string(cstring(&uts.machine[0]))
	machine := strings.trim_space(machine_name)

	arch: string
	switch machine {
	case "x86_64":
		arch = "x86_64"
	case "aarch64":
		arch = "aarch64"
	case "armv7l":
		arch = "armv7l"
	case "i686", "i386":
		arch = "i686"
	case:
		arch = "x86_64"
		if machine != "" do arch = machine
	}

	return strings.clone(arch), true
}

// Make a C-compatible argv array from slice of strings
make_argv :: proc(args: []string, allocator := context.allocator) -> [^]cstring {
	argv := make([dynamic]cstring, allocator)
	for arg in args {
		append(&argv, strings.clone_to_cstring(arg, allocator))
	}
	append(&argv, nil)
	return raw_data(argv)
}

// Run a command and return its output
run_command_output :: proc(args: []string, allocator := context.allocator) -> (string, bool) {
	if len(args) == 0 {return "", false}

	fds: [2]linux.Fd
	// pipe2 with empty flags ({}) is equivalent to pipe
	if linux.pipe2(&fds, {}) != nil {
		return "", false
	}
	defer linux.close(fds[0])

	pid, err := linux.fork()
	if err != nil {
		linux.close(fds[1])
		return "", false
	}

	if pid == 0 {
		// Child process
		linux.close(fds[0]) // Close read end
		linux.dup2(fds[1], linux.STDOUT_FILENO)
		linux.close(fds[1])

		argv := make_argv(args, context.temp_allocator)
		path := strings.clone_to_cstring(args[0], context.temp_allocator)

		// Use execvp
		execvp(path, argv)

		// If execvp returns, it failed
		os.exit(1)
	}

	// Parent process
	linux.close(fds[1]) // Close write end

	builder := strings.builder_make(allocator)
	buf: [1024]u8

	for {
		// read returns (int, error)
		// Linux read syscall returns plain int result (size or -errno) wrapped by Odin core:sys/linux?
		// Actually core:sys/linux read returns (int, Errno)
		n, read_err := linux.read(fds[0], buf[:])
		if n <= 0 || read_err != nil {break}
		strings.write_bytes(&builder, buf[:n])
	}

	status: u32
	// waitpid(pid, status, options, rusage)
	linux.waitpid(pid, &status, {}, nil)

	return strings.to_string(builder), true
}

// Run a command and return exit code
run_command :: proc(args: []string) -> int {
	if len(args) == 0 {return 127}

	pid, err := linux.fork()
	if err != nil {
		return -1
	}

	if pid == 0 {
		// Child
		argv := make_argv(args, context.temp_allocator)
		path := strings.clone_to_cstring(args[0], context.temp_allocator)

		execvp(path, argv)
		os.exit(127)
	}

	// Parent
	status: u32
	linux.waitpid(pid, &status, {}, nil)

	// Decode status
	// WEXITSTATUS(status) = (status & 0xff00) >> 8
	// In linux, status is int (i32), but here we use u32 to match signature.
	// If WIFEXITED(status) -> status & 0x7f == 0
	if (status & 0x7f) == 0 {
		return int((status & 0xff00) >> 8)
	}

	return -1 // Terminated by signal
}

// Get cache directory path
get_cache_dir :: proc(allocator := context.allocator) -> (string, bool) {
	xdg_cache := os.get_env("XDG_CACHE_HOME", context.temp_allocator)
	if len(xdg_cache) > 0 && xdg_cache[0] == '/' {
		return strings.concatenate({xdg_cache, "/vup"}, allocator), true
	}

	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 || home[0] != '/' {
		return "", false
	}

	return strings.concatenate({home, "/.cache/vup"}, allocator), true
}

// Get temporary directory path
get_tmpdir :: proc() -> string {
	tmpdir := os.get_env("TMPDIR", context.temp_allocator)
	if len(tmpdir) > 0 && tmpdir[0] == '/' {
		return tmpdir
	}
	return "/tmp"
}

// Validate identifier (package name, category)
is_valid_identifier :: proc(s: string) -> bool {
	if len(s) == 0 || s[0] == '.' {
		return false
	}

	for c in s {
		valid :=
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') ||
			c == '-' ||
			c == '_' ||
			c == '.'
		if !valid {
			return false
		}
	}

	// Prevent directory traversal
	if strings.contains(s, "..") {
		return false
	}

	return true
}

// Create directory and all parents
mkdir_p :: proc(path: string) -> bool {
	if os.exists(path) {
		return os.is_dir(path)
	}

	err := os.make_directory(path)
	if err == os.ERROR_NONE {
		return true
	}

	// Try to create parent first
	parent := parent_dir(path)
	if len(parent) > 0 && parent != path {
		if !mkdir_p(parent) {
			return false
		}
		return os.make_directory(path) == os.ERROR_NONE
	}

	return false
}

// Get parent directory
parent_dir :: proc(path: string) -> string {
	for i := len(path) - 1; i >= 0; i -= 1 {
		if path[i] == '/' {
			if i == 0 {return "/"}
			return path[:i]
		}
	}
	return ""
}

// Join paths
path_join :: proc(parts: ..string, allocator := context.allocator) -> string {
	return strings.join(parts[:], "/", allocator)
}
