package xbps

// Package removal using xbps-remove

// Remove a package and its dependencies
remove_package :: proc(pkg_name: string, yes: bool, run_cmd: Command_Runner) -> int {
	args := build_args_with_yes(yes, "sudo", "xbps-remove", "-R")


	append(&args, pkg_name)
	return run_cmd(args[:])
}

// Remove orphaned packages
remove_orphans :: proc(yes: bool, run_cmd: Command_Runner) -> int {
	args := build_args_with_yes(yes, "sudo", "xbps-remove", "-o")


	return run_cmd(args[:])
}

// Clean package cache
clean_cache :: proc(run_cmd: Command_Runner) -> int {
	return run_cmd({"sudo", "xbps-remove", "-O"})
}
