.PHONY: validate check local-validate

LOCAL_TEMPLATES ?= $(shell find vup/srcpkgs -name template -type f 2>/dev/null)

validate: check

check:
	@echo "==> Validating templates..."
	@python3 vup/scripts/validate_template.py $(LOCAL_TEMPLATES)

local-validate: check
	@echo ""
	@echo "==> Tip: To build a local Docker-based validation, run:"
	@echo "    docker run --rm --privileged -v \$$PWD:/vup \\"
	@echo "      ghcr.io/vup-linux/vup-builder:latest sh -c '"
	@echo "        cd /vup/vup/srcpkgs/<category>/<pkgname> && xbps-src pkg <pkgname>'"
