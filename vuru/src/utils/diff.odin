package utils

import errors "../core/errors"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:sys/linux"

// Generate random string for temp file names
rand_string :: proc(length: int, allocator := context.allocator) -> string {
	chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

	buf := make([]u8, length, allocator)
	for i in 0 ..< length {
		buf[i] = chars[rand.int_max(len(chars))]
	}

	return string(buf)
}

// Write content to a temp file
diff_write_temp_file :: proc(content: string, allocator := context.allocator) -> (string, bool) {
	tmpdir := get_tmpdir()
	rand_suffix := rand_string(6, context.temp_allocator)

	path := fmt.aprintf(
		"%s/vuru_diff_%d_%s",
		tmpdir,
		linux.getpid(),
		rand_suffix,
		allocator = allocator,
	)

	if !write_file(path, content) {
		delete(path)
		return "", false
	}

	return path, true
}

// Generate a colored unified diff between old and new content
diff_generate :: proc(
	old_content: string,
	new_content: string,
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	new_path, new_ok := diff_write_temp_file(new_content, context.temp_allocator)
	if !new_ok {
		return "", false
	}
	defer os.remove(new_path)

	if len(old_content) > 0 {
		old_path, old_ok := diff_write_temp_file(old_content, context.temp_allocator)
		if !old_ok {
			return "", false
		}
		defer os.remove(old_path)

		// diff returns 1 if different, which is fine. run_command_output just captures output.
		// Note: diff -u --color=always old new
		output, _ := run_command_output({"diff", "-u", "--color=always", old_path, new_path})
		return output, true
	} else {
		// No old content, return new content
		return strings.clone(new_content, allocator), true
	}
}

// Show content in less pager
diff_show_pager :: proc(path: string) {
	run_command({"less", "-R", path})
}

// Review changes between current and previous template
review_changes :: proc(pkg_name: string, current: string, previous: string) -> bool {
	if len(current) == 0 {
		return false
	}

	if !is_valid_identifier(pkg_name) {
		errors.log_error("Invalid package name")
		return false
	}

	if len(previous) > 0 && current == previous {
		errors.log_info("Template for %s unchanged since last install.", pkg_name)
	} else {
		if len(previous) > 0 {
			// Generate colored diff and show in pager
			diff_output, diff_ok := diff_generate(previous, current, context.temp_allocator)
			if diff_ok && len(diff_output) > 0 {
				review_path, path_ok := diff_write_temp_file(diff_output, context.temp_allocator)
				if path_ok {
					defer os.remove(review_path)

					fmt.println()
					fmt.printf("Template for %s has changed:\n", pkg_name)
					diff_show_pager(review_path)
				}
			}
		} else {
			// New package - show full template in pager
			fmt.println()
			fmt.printf("New package %s. Review template:\n", pkg_name)
			review_path, path_ok := diff_write_temp_file(current, context.temp_allocator)
			if path_ok {
				defer os.remove(review_path)
				diff_show_pager(review_path)
			}
		}
	}

	fmt.print("Proceed with installation? [Y/n] ")

	buf: [100]u8
	n, _ := os.read(os.stdin, buf[:])

	if n <= 0 {
		return false
	}

	input := strings.trim_space(string(buf[:n]))
	input_lower := strings.to_lower(input, context.temp_allocator)

	return len(input) == 0 || input_lower == "y" || input_lower == "yes"
}
