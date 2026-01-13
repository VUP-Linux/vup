package errors

import "core:fmt"
import "core:io"
import "core:os"

// ANSI color codes (centralized here for all of vuru)
COLOR_RESET :: "\033[0m"
COLOR_RED :: "\033[1;31m"
COLOR_GREEN :: "\033[1;32m"
COLOR_YELLOW :: "\033[1;33m"
COLOR_BLUE :: "\033[1;34m"
COLOR_CYAN :: "\033[1;36m"
COLOR_DIM :: "\033[2m"

// Aliases for semantic usage
COLOR_ERROR :: COLOR_RED
COLOR_WARNING :: COLOR_YELLOW
COLOR_INFO :: COLOR_BLUE

// Print error with full formatting
print_error :: proc(err: Error) {
	fmt.eprintf("%s[error]%s ", COLOR_RED, COLOR_RESET)

	if len(err.ctx) > 0 {
		fmt.eprintf("%s: %s\n", err.message, err.ctx)
	} else {
		fmt.eprintln(err.message)
	}

	if len(err.hint) > 0 {
		fmt.eprintf("\n%s%s%s\n", COLOR_DIM, err.hint, COLOR_RESET)
	}
}

// Print error with just message (no hint)
print_error_brief :: proc(err: Error) {
	fmt.eprintf("%s[error]%s ", COLOR_RED, COLOR_RESET)

	if len(err.ctx) > 0 {
		fmt.eprintf("%s: %s\n", err.message, err.ctx)
	} else {
		fmt.eprintln(err.message)
	}
}

// Print warning
print_warning :: proc(msg: string, args: ..any) {
	fmt.eprintf("%s[warn]%s ", COLOR_YELLOW, COLOR_RESET)
	fmt.eprintf(msg, ..args)
	fmt.eprintln()
}

// Print multiple errors (e.g., for dependency resolution)
print_error_list :: proc(title: string, errs: []Error) {
	fmt.eprintf("%s[error]%s %s\n", COLOR_RED, COLOR_RESET, title)

	for err in errs {
		fmt.eprintf("  • %s", err.message)
		if len(err.ctx) > 0 {
			fmt.eprintf(": %s", err.ctx)
		}
		fmt.eprintln()
	}

	// Show first hint if available
	for err in errs {
		if len(err.hint) > 0 {
			fmt.eprintf("\n%s%s%s\n", COLOR_DIM, err.hint, COLOR_RESET)
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
	fmt.eprintf("%s[error]%s ", COLOR_RED, COLOR_RESET)
	fmt.eprintf("%s requires '%s' command\n", flag, command)
	fmt.eprintf("%s  Example: %s%s\n", COLOR_DIM, example, COLOR_RESET)
}

// Simple error logging (replaces errors.log_error for consistency)
log_error :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[error]%s ", COLOR_RED, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Simple info logging
log_info :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[info]%s ", COLOR_CYAN, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Simple warning logging
log_warning :: proc(format: string, args: ..any) {
	fmt.eprintf("%s[warn]%s ", COLOR_YELLOW, COLOR_RESET)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// Print usage message (for command help)
print_usage :: proc(usage: string) {
	fmt.println(usage)
}
