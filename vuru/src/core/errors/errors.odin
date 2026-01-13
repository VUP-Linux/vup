package errors

import "core:fmt"
import "core:strings"

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
make_error :: proc(
	kind: Error_Kind,
	error_ctx: string = "",
	allocator := context.allocator,
) -> Error {
	return Error {
		kind = kind,
		message = get_message(kind),
		ctx = strings.clone(error_ctx, allocator),
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
			"'%s' was not found in VUP or official Void repos.\n" +
			"  • Check spelling: vuru search %s\n" +
			"  • Search all repos: vuru query %s\n" +
			"  • Request package: https://github.com/VUP-Linux/vup/issues",
			ctx,
			ctx,
			ctx,
		)

	case .Package_Not_In_Repos:
		return fmt.tprintf(
			"'%s' is not in official Void repos.\n" +
			"  • Check VUP: vuru search %s\n" +
			"  • Sync repos: sudo xbps-install -S",
			ctx,
			ctx,
		)

	case .Package_Arch_Unavailable:
		return fmt.tprintf(
			"'%s' has no binary for your architecture.\n" +
			"  • Try building from source: vuru -b %s\n" +
			"  • Check available archs in VUP index",
			ctx,
			ctx,
		)

	case .Package_Already_Installed:
		return fmt.tprintf(
			"'%s' is already installed.\n" +
			"  • Check version: xbps-query %s\n" +
			"  • Reinstall: sudo xbps-install -f %s",
			ctx,
			ctx,
			ctx,
		)

	case .Package_Not_Installed:
		return fmt.tprintf(
			"'%s' is not installed.\n" + "  • Install it: vuru install %s",
			ctx,
			ctx,
		)

	case .Dependency_Not_Found:
		return fmt.tprintf(
			"Dependency '%s' could not be resolved.\n" +
			"  • Check if it exists: vuru search %s\n" +
			"  • Try syncing: vuru -S",
			ctx,
			ctx,
		)

	case .Dependency_Cycle:
		return(
			"Circular dependencies detected. This is likely a packaging bug.\n" +
			"  • Report issue: https://github.com/VUP-Linux/vup/issues" \
		)

	case .Dependency_Conflict:
		return(
			"Conflicting package versions required.\n" +
			"  • Try updating first: vuru -u\n" +
			"  • Check for held packages: xbps-pkgdb -m" \
		)

	case .Index_Fetch_Failed:
		return(
			"Could not download package index.\n" +
			"  • Check internet connection\n" +
			"  • Try again: vuru -S" \
		)

	case .Index_Parse_Failed:
		return(
			"Package index is corrupted.\n" +
			"  • Force refresh: vuru -S\n" +
			"  • Clear cache: rm -rf ~/.cache/vup" \
		)

	case .VUP_Repo_Not_Found:
		return(
			"VUP repository not cloned.\n" +
			"  • Clone it: vuru clone\n" +
			"  • Default location: ~/.local/share/vup" \
		)

	case .Xbps_Src_Not_Found:
		return(
			"xbps-src not found in current directory.\n" +
			"  • Make sure you're in a void-packages directory\n" +
			"  • Clone void-packages: git clone https://github.com/void-linux/void-packages" \
		)

	case .Template_Not_Found:
		return fmt.tprintf(
			"Template '%s' not found.\n" +
			"  • Check the package exists in srcpkgs/\n" +
			"  • Ensure spelling is correct",
			ctx,
		)

	case .Arch_Not_Supported:
		return fmt.tprintf(
			"'%s' is not available.\n" +
			"  • Package may only support certain architectures\n" +
			"  • Check package template for 'archs' field",
			ctx,
		)

	case .Missing_Argument:
		return fmt.tprintf("Missing %s.\n" + "  • Check command usage: vuru help", ctx)

	case .Build_Failed:
		return fmt.tprintf(
			"Build of '%s' failed.\n" +
			"  • Check build log above\n" +
			"  • Install build deps: vuru -b %s\n" +
			"  • Report issue if persists",
			ctx,
			ctx,
		)

	case .Build_Deps_Missing:
		return(
			"Build dependencies are missing.\n" +
			"  • Install base-devel: sudo xbps-install base-devel\n" +
			"  • Check template for makedepends" \
		)

	case .Network_Unavailable:
		return(
			"No network connection.\n" +
			"  • Check your connection\n" +
			"  • Cached index may still work for local operations" \
		)

	case .Permission_Denied:
		return(
			"Operation requires root privileges.\n" +
			"  • Use sudo for system operations\n" +
			"  • Check file permissions" \
		)

	case .Home_Not_Set:
		return(
			"HOME environment variable is not set.\n" +
			"  • Set it: export HOME=/home/yourusername" \
		)

	case .Arch_Detection_Failed:
		return "Could not detect system architecture.\n" + "  • Check: uname -m"

	case .Flag_Requires_Command:
		return fmt.tprintf(
			"'%s' needs a command to work with.\n" + "  • Check usage: vuru help",
			ctx,
		)

	case .Missing_Command:
		return(
			"No command specified.\n" +
			"  • Usage: vuru <command> [options]\n" +
			"  • See: vuru help" \
		)

	case .Unknown_Command:
		return fmt.tprintf(
			"'%s' is not a valid command.\n" + "  • See available commands: vuru help",
			ctx,
		)

	case:
		return ""
	}
}
