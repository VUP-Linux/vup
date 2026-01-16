package utils

import "core:mem"
import "core:os"
import "core:strings"
import "core:sys/linux"

// Define execvp since it's missing from core:c/libc sometimes or not exported commonly
foreign import libc "system:c"

foreign libc {
	execvp :: proc(file: cstring, argv: [^]cstring) -> i32 ---
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

		// If execvp returns, it failed
		execvp(path, argv)
		os.exit(1)
	}

	// Parent process
	linux.close(fds[1]) // Close write end

	builder := strings.builder_make(allocator)
	buf: [1024]u8

	for {
		n, read_err := linux.read(fds[0], buf[:])
		if n <= 0 || read_err != nil {break}
		strings.write_bytes(&builder, buf[:n])
	}

	status: u32
	linux.waitpid(pid, &status, {}, nil)

	// Check exit status
	success := (status & 0x7f) == 0 && ((status & 0xff00) >> 8) == 0

	return strings.to_string(builder), success
}

// Run a command silently (capture output, return exit code)
run_command_silent :: proc(args: []string) -> int {
	if len(args) == 0 {return 127}

	fds: [2]linux.Fd
	if linux.pipe2(&fds, {}) != nil {
		return -1
	}
	defer linux.close(fds[0])

	pid, err := linux.fork()
	if err != nil {
		linux.close(fds[1])
		return -1
	}

	if pid == 0 {
		// Child - redirect both stdout and stderr to pipe
		linux.close(fds[0])
		linux.dup2(fds[1], linux.STDOUT_FILENO)
		linux.dup2(fds[1], linux.STDERR_FILENO)
		linux.close(fds[1])

		argv := make_argv(args, context.temp_allocator)
		path := strings.clone_to_cstring(args[0], context.temp_allocator)

		execvp(path, argv)
		os.exit(127)
	}

	// Parent - drain the pipe to avoid blocking
	linux.close(fds[1])
	buf: [1024]u8
	for {
		n, _ := linux.read(fds[0], buf[:])
		if n <= 0 {break}
	}

	status: u32
	linux.waitpid(pid, &status, {}, nil)

	if (status & 0x7f) == 0 {
		return int((status & 0xff00) >> 8)
	}

	return -1
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
	if (status & 0x7f) == 0 {
		return int((status & 0xff00) >> 8)
	}

	return -1 // Terminated by signal
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

// Helper functions extracted from template.odin to avoid cyclic deps and duplication

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
