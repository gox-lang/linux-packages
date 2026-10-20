#!/bin/sh
if [ "${1:-}" = update ]; then
    echo 'This GOX installation is managed by your Linux package manager.' >&2
    echo 'Update GOX through APT or DNF, or install a newer official .deb/.rpm package.' >&2
    exit 1
fi
if [ -z "${GOX_HOME:-}" ]; then
    export GOX_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/gox"
fi
export GOX_LSP_AUTO_UPDATE=0
exec /usr/lib/gox/gox "$@"
