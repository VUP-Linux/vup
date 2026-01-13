package xbps

// Package installation using xbps-install

// Install a package from a specific repository
install_from_repo :: proc(
	repo_url: string,
	pkg_name: string,
	yes: bool,
	run_cmd: proc(_: []string) -> int,
) -> int {
	args := build_args_with_yes(yes, "sudo", "xbps-install", "-R", repo_url, "-S")
	defer delete(args)

	append(&args, pkg_name)
	return run_cmd(args[:])
}

// Sync package index only
sync_repos :: proc(run_cmd: proc(_: []string) -> int) -> int {
	return run_cmd({"sudo", "xbps-install", "-S"})
}
