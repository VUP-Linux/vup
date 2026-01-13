package template

import utils "../../utils"

import "core:fmt"
import "core:os"
import "core:sys/linux"

// Base URL for templates
TEMPLATE_URL_BASE :: "https://raw.githubusercontent.com/VUP-Linux/vup/main/vup/srcpkgs"

// Fetch the template for a package
fetch_template :: proc(
	category: string,
	pkg_name: string,
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	if !utils.is_valid_identifier(category) || !utils.is_valid_identifier(pkg_name) {
		utils.log_error("Invalid category or package name")
		return "", false
	}

	url := fmt.tprintf("%s/%s/%s/template", TEMPLATE_URL_BASE, category, pkg_name)

	tmpdir := utils.get_tmpdir()
	tmp_path := fmt.tprintf("%s/vuru_tmpl_%s_%d", tmpdir, pkg_name, linux.getpid())
	defer os.remove(tmp_path)

	// curl to fetch
	if utils.run_command({"curl", "-s", "-f", "-L", "-o", tmp_path, url}) != 0 {
		utils.log_error("Failed to fetch template from %s", url)
		return "", false
	}

	content, ok := utils.read_file(tmp_path, allocator)
	return content, ok
}
