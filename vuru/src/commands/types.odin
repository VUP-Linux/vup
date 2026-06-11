package commands

import "core:mem"

// Global configuration passed to commands
Config :: struct {
	// Global settings
	index_url:          string,
	vup_dir:            string,
	arch:               string,
	rootdir:            string, // -r, --rootdir

	// Runtime flags
	yes:                bool, // -y, --yes
	dry_run:            bool, // -n, --dry-run
	force_build:        bool, // -b, --build
	vup_only:           bool, // --vup-only
	description_search: bool, // -d, --desc
	verbose:            bool, // -v, --verbose

	// XBPS-aligned flags
	sync:               bool, // -S, sync repos
	update_system:      bool, // -u, update packages
	recursive:          bool, // -R, recursive remove/deps
	orphans:            bool, // -o, remove orphans
	clean_cache:        bool, // -O, clean cache
	list_pkgs:          bool, // -l, list installed
	show_files:         bool, // -f, show files
	show_deps:          bool, // -x, show deps
	ownedby:            bool, // query: find file owner

	// Allocator for owned strings
	allocator:          mem.Allocator,
}

// Command interface (struct of procedures/metadata)
Command :: struct {
	name:        string,
	description: string,
	usage:       string,
	alias:       string,
	run:         proc(args: []string, config: ^Config) -> int,
}
