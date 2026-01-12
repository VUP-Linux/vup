package xbps

// Version comparison using xbps-uhelper

// Compare two versions using xbps-uhelper cmpver
// Returns true if v1 > v2
version_greater_than :: proc(
	v1: string,
	v2: string,
	run_cmd: proc([]string) -> int,
) -> bool {
	if len(v1) == 0 || len(v2) == 0 {
		return false
	}

	// xbps-uhelper cmpver returns:
	//   0 if v1 == v2
	//   1 if v1 > v2
	//  -1 if v1 < v2
	return run_cmd({"xbps-uhelper", "cmpver", v1, v2}) == 1
}

// Compare two versions
// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
version_compare :: proc(
	v1: string,
	v2: string,
	run_cmd: proc([]string) -> int,
) -> int {
	if len(v1) == 0 || len(v2) == 0 {
		return 0
	}

	return run_cmd({"xbps-uhelper", "cmpver", v1, v2})
}
