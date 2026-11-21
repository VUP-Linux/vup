#!/bin/sh
set -eu

cd "$1"
key=${2-}

# Let XBPS select versions using package metadata, including reverts.
rm -f ./*-repodata* ./*.sig ./*.sig2
xbps-rindex --add ./*.xbps
if [ ! -f "${XBPS_ARCH}-repodata" ]; then
    printf 'No repodata generated for %s\n' "$XBPS_ARCH" >&2
    exit 1
fi
xbps-rindex --remove-obsoletes .

if [ -n "$key" ]; then
    xbps-rindex --sign-pkg --privkey "$key" ./*.xbps
    xbps-rindex --sign --privkey "$key" --signedby "VUP Builder" .
fi
