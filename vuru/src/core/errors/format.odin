package errors

import "core:fmt"
import "core:io"
import "core:os"

// ANSI color codes (centralized here for all of vuru)
COLOR_RESET :: "\033[0m"
COLOR_BOLD :: "\033[1m"
COLOR_RED :: "\033[31m"
COLOR_GREEN :: "\033[32m"
COLOR_YELLOW :: "\033[33m"
COLOR_BLUE :: "\033[34m"
COLOR_MAGENTA :: "\033[35m"
COLOR_CYAN :: "\033[36m"
COLOR_WHITE :: "\033[37m"

// Detailed codes
COLOR_ERROR_BG :: "\033[41;37;1m" // White on Red Background for heavy errors? Maybe too much.
// Let's stick to text colors but use BOLD for emphasis.
COLOR_ERROR :: "\033[1;31m" // Bold Red
COLOR_WARNING :: "\033[1;33m" // Bold Yellow
COLOR_SUCCESS :: "\033[1;32m" // Bold Green
COLOR_INFO :: "\033[1;36m" // Bold Cyan
COLOR_DIM :: "\033[2m"

// Print error with full formatting
print_error :: proc(err: Error) {
	fmt.eprintf("%s[ERROR]%s ", COLOR_ERROR, COLOR_RESET)

	if len(err.ctx) > 0 {
		// Message: Context (Context is bold/white for readability)
		fmt.eprintf("%s: %s%s%s\n", err.message, COLOR_BOLD, err.ctx, COLOR_RESET)
	} else {
		fmt.eprintln(err.message)
	}

	if len(err.hint) > 0 {
		// Hints indented with a subtle arrow
		fmt.eprintf("%s  -> %s%s\n", COLOR_DIM, err.hint, COLOR_RESET)
	}
}

// Print error with just message (no hint)
print_error_brief :: proc(err: Error) {
	fmt.eprintf("%s[ERROR]%s ", COLOR_ERROR, COLOR_RESET)

	if len(err.ctx) > 0 {
		fmt.eprintf("%s: %s%s%s\n", err.message, COLOR_BOLD, err.ctx, COLOR_RESET)
	} else {
		fmt.eprintln(err.message)
	}
}

// Global log_warning (consolidated)
log_warning :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[WARN]%s  ", COLOR_WARNING, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}
// Alias for backward compatibility if needed, but we prefer log_warning
print_warning :: log_warning

// Print multiple errors (e.g., for dependency resolution)
print_error_list :: proc(title: string, errs: []Error) {
	fmt.eprintf("%s[ERROR]%s %s\n", COLOR_ERROR, COLOR_RESET, title)

	for err in errs {
		fmt.eprintf("  • %s", err.message)
		if len(err.ctx) > 0 {
			fmt.eprintf(": %s%s%s", COLOR_BOLD, err.ctx, COLOR_RESET)
		}
		fmt.eprintln()
	}

	// Show first hint if available
	for err in errs {
		if len(err.hint) > 0 {
			fmt.eprintf("\n%s  -> %s%s\n", COLOR_DIM, err.hint, COLOR_RESET)
			break
		}
	}
}

// Format error as string (for logging)
format_error :: proc(err: Error, allocator := context.allocator) -> string {
	if len(err.ctx) > 0 {
		return fmt.aprintf("%s: %s", err.message, err.ctx, allocator = allocator)
	}
	return fmt.aprintf("%s", err.message, allocator = allocator)
}

// Print flag requires command error with example
print_flag_error :: proc(flag: string, command: string, example: string) {
	fmt.eprintf("%s[ERROR]%s ", COLOR_ERROR, COLOR_RESET)
	fmt.eprintf("%s requires '%s%s%s' command\n", flag, COLOR_BOLD, command, COLOR_RESET)
	fmt.eprintf("%s  Example: %s%s\n", COLOR_DIM, example, COLOR_RESET)
}

// Simple error logging
log_error :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[ERROR]%s ", COLOR_ERROR, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Simple info logging
log_info :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[INFO]%s  ", COLOR_INFO, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Success logging (New!)
log_success :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[OK]%s    ", COLOR_SUCCESS, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Print usage message (for command help)
print_usage :: proc(usage: string) {
	fmt.println(usage)
}
