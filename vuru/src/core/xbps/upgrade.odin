package xbps

// Package upgrade using xbps-install

// Upgrade a specific package from a repository
upgrade_from_repo :: proc(
	repo_url: string,
	pkg_name: string,
	yes: bool,
	run_cmd: Command_Runner,
) -> int {
	args := build_args_with_yes(yes, "sudo", "xbps-install", "-R", repo_url, "-Su")


	append(&args, pkg_name)
	return run_cmd(args[:])
}

// Upgrade all packages from official repos
upgrade_all_official :: proc(yes: bool, run_cmd: Command_Runner) -> int {
	args := build_args_with_yes(yes, "sudo", "xbps-install", "-Su")


	return run_cmd(args[:])
}
