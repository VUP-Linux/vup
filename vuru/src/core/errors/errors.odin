package errors

import "core:fmt"

// Error categories
Error_Kind :: enum {
	// Package errors
	Package_Not_Found,
	Package_Not_In_VUP,
	Package_Not_In_Repos,
	Package_Arch_Unavailable,
	Package_Already_Installed,
	Package_Not_Installed,
	Arch_Not_Supported,

	// Dependency errors
	Dependency_Not_Found,
	Dependency_Cycle,
	Dependency_Conflict,

	// Index errors
	Index_Fetch_Failed,
	Index_Parse_Failed,
	Index_Cache_Failed,

	// Build errors
	Build_Failed,
	Build_Deps_Missing,
	Template_Not_Found,
	VUP_Repo_Not_Found,
	Xbps_Src_Not_Found,

	// Network errors
	Network_Unavailable,
	Download_Failed,

	// System errors
	Arch_Detection_Failed,
	Permission_Denied,
	Command_Failed,

	// Config errors
	Home_Not_Set,
	Cache_Dir_Failed,

	// Argument/CLI errors
	Missing_Argument,
	Missing_Command,
	Unknown_Command,
	Flag_Requires_Command,
}

// Detailed error with context
Error :: struct {
	kind:    Error_Kind,
	message: string,
	ctx:     string, // Additional context (package name, URL, etc.)
	hint:    string, // Suggestion for fixing
}

// Create error with full details
// NOTE: Errors are short-lived (create, print, discard). All strings are views
// into static memory or temp allocator. Do not store Error structs long-term.
make_error :: proc(kind: Error_Kind, error_ctx: string = "") -> Error {
	return Error {
		kind = kind,
		message = get_message(kind),
		ctx = error_ctx,
		hint = get_hint(kind, error_ctx),
	}
}

// Get human-readable error message
get_message :: proc(kind: Error_Kind) -> string {
	switch kind {
	// Package errors
	case .Package_Not_Found:
		return "Package not found"
	case .Package_Not_In_VUP:
		return "Package not in VUP repository"
	case .Package_Not_In_Repos:
		return "Package not in official Void repositories"
	case .Package_Arch_Unavailable:
		return "Package not available for your architecture"
	case .Package_Already_Installed:
		return "Package is already installed"
	case .Package_Not_Installed:
		return "Package is not installed"
	case .Arch_Not_Supported:
		return "Architecture not supported for this package"

	// Dependency errors
	case .Dependency_Not_Found:
		return "Dependency not found"
	case .Dependency_Cycle:
		return "Circular dependency detected"
	case .Dependency_Conflict:
		return "Dependency conflict"

	// Index errors
	case .Index_Fetch_Failed:
		return "Failed to fetch package index"
	case .Index_Parse_Failed:
		return "Failed to parse package index"
	case .Index_Cache_Failed:
		return "Failed to cache package index"

	// Build errors
	case .Build_Failed:
		return "Build failed"
	case .Build_Deps_Missing:
		return "Build dependencies missing"
	case .Template_Not_Found:
		return "Package template not found"
	case .VUP_Repo_Not_Found:
		return "VUP repository not found"
	case .Xbps_Src_Not_Found:
		return "xbps-src not found"

	// Network errors
	case .Network_Unavailable:
		return "Network unavailable"
	case .Download_Failed:
		return "Download failed"

	// System errors
	case .Arch_Detection_Failed:
		return "Failed to detect system architecture"
	case .Permission_Denied:
		return "Permission denied"
	case .Command_Failed:
		return "Command execution failed"

	// Config errors
	case .Home_Not_Set:
		return "HOME environment variable not set"
	case .Cache_Dir_Failed:
		return "Failed to create cache directory"

	// CLI/Argument errors
	case .Missing_Argument:
		return "Missing required argument"
	case .Missing_Command:
		return "Missing command"
	case .Unknown_Command:
		return "Unknown command"
	case .Flag_Requires_Command:
		return "Flag requires a command"
	}

	return "Unknown error"
}

// Get helpful hint for resolving the error
get_hint :: proc(kind: Error_Kind, ctx: string = "") -> string {
	#partial switch kind {
	case .Package_Not_Found:
		return fmt.tprintf(
			"Check spelling or search all repos:\n" +
			"    • vuru search %s\n" +
			"    • vuru query %s\n" +
			"    • Request package: https://github.com/VUP-Linux/vup/issues",
			ctx,
			ctx,
		)

	case .Package_Not_In_Repos:
		return fmt.tprintf(
			"Check VUP or sync repositories:\n" +
			"    • vuru search %s\n" +
			"    • sudo xbps-install -S",
			ctx,
		)

	case .Package_Arch_Unavailable:
		return fmt.tprintf("Try building from source instead:\n" + "    • vuru -b %s", ctx)

	case .Package_Already_Installed:
		return fmt.tprintf(
			"To reinstall or force update:\n" + "    • sudo xbps-install -f %s",
			ctx,
		)

	case .Package_Not_Installed:
		return fmt.tprintf("Install it with:\n" + "    • vuru install %s", ctx)

	case .Dependency_Not_Found:
		return fmt.tprintf(
			"Try syncing or searching for the dependency:\n" +
			"    • vuru -S\n" +
			"    • vuru search %s",
			ctx,
		)

	case .Dependency_Cycle:
		return "Report this circular dependency issues at https://github.com/VUP-Linux/vup/issues"

	case .Dependency_Conflict:
		return "Try updating your system first: vuru -u"

	case .Index_Fetch_Failed:
		return "Check your internet connection or try again with 'vuru -S'"

	case .Index_Parse_Failed:
		return "Force refresh the index:\n" + "    • vuru -S\n" + "    • rm -rf ~/.cache/vup"

	case .VUP_Repo_Not_Found:
		return "Clone it manually or run 'vuru clone'"

	case .Xbps_Src_Not_Found:
		return(
			"Ensure you are in a valid void-packages directory or clone it:\n" +
			"    • git clone https://github.com/void-linux/void-packages" \
		)

	case .Template_Not_Found:
		return fmt.tprintf("Verify '%s/template' exists in srcpkgs/", ctx)

	case .Arch_Not_Supported:
		return "Check the 'archs' field in the package template."

	case .Missing_Argument:
		return fmt.tprintf("See usage: vuru %s --help", ctx) // Assuming ctx is the command name if avail, or generalized

	case .Build_Failed:
		return fmt.tprintf(
			"Check build logs above. To install missing build deps:\n" + "    • vuru -b %s",
			ctx,
		)

	case .Build_Deps_Missing:
		return "Install base-devel: sudo xbps-install base-devel"

	case .Network_Unavailable:
		return "Check your connection. Cached operations may still work."

	case .Permission_Denied:
		return "Run with 'sudo' or check file permissions."

	case .Home_Not_Set:
		return "Set HOME environment variable: export HOME=/home/youruser"

	case .Arch_Detection_Failed:
		return "Verify 'uname -m' works."

	case .Flag_Requires_Command:
		return "Check usage: vuru help"

	case .Missing_Command:
		return "See available commands: vuru help"

	case .Unknown_Command:
		return "See available commands: vuru help"

	case:
		return ""
	}
}
