#!/usr/bin/env bash
# Isolated test key only. Never use this key for production publication.
set -euo pipefail
packages=${1:?Supply packages directory}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key 'GOX Disposable CI Key' rsa3072 sign 1d
export GOX_SIGNING_FINGERPRINT
a=$(gpg --batch --with-colons --list-secret-keys)
GOX_SIGNING_FINGERPRINT=$(printf '%s\n' "$a" | awk -F: '$1=="fpr" {print $10; exit}')
root=$(cd "$(dirname "$0")/.." && pwd)
bash "$root/packaging/repository.sh" "$packages" "$work/site"
gpgv --keyring "$work/site/gox-archive-keyring.gpg" "$work/site/apt/dists/stable/InRelease"
for arch in x86_64 aarch64; do
    gpgv --keyring "$work/site/gox-archive-keyring.gpg" \
        "$work/site/rpm/$arch/repodata/repomd.xml.asc" "$work/site/rpm/$arch/repodata/repomd.xml"
done
mkdir "$work/rpmdb"
rpm --dbpath "$work/rpmdb" --import "$work/site/gox-signing-key.asc"
for package in "$work/site"/rpm/*/Packages/*.rpm; do
    rpmkeys --dbpath "$work/rpmdb" --checksig "$package" | grep -F 'signatures OK'
done
# Optional disposable fixture for real APT/DNF client tests.
if [[ -n ${2:-} ]]; then
    [[ ! -e $2 ]]
    cp -a "$work/site" "$2"
fi
# Corrupt signed metadata and require verification to fail.
sed -i 's/Origin: GOX/Origin: altered/' "$work/site/apt/dists/stable/InRelease"
if gpgv --keyring "$work/site/gox-archive-keyring.gpg" "$work/site/apt/dists/stable/InRelease"; then
    echo 'Tampered APT metadata was accepted' >&2; exit 1
fi
printf '\nCORRUPTED\n' >> "$work/site/rpm/x86_64/repodata/repomd.xml"
if gpgv --keyring "$work/site/gox-archive-keyring.gpg" \
    "$work/site/rpm/x86_64/repodata/repomd.xml.asc" "$work/site/rpm/x86_64/repodata/repomd.xml"; then
    echo 'Tampered RPM metadata was accepted' >&2; exit 1
fi
echo 'Repository signatures, RPM signatures and metadata tamper checks passed.'
