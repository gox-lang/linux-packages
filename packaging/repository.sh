#!/usr/bin/env bash
# Build a complete signed repository snapshot in a NEW directory.
set -euo pipefail
packages=${1:?Supply a directory containing approved packages}
output=${2:?Supply a new output directory}
fingerprint=${GOX_SIGNING_FINGERPRINT:?Set the full signing-key fingerprint}
[[ $fingerprint =~ ^[A-Fa-f0-9]{40}$ ]] || exit 1
[[ ! -e $output ]] || { echo 'Output already exists; use a new snapshot directory' >&2; exit 1; }
gpg --batch --list-secret-keys "$fingerprint" >/dev/null
mkdir -p "$output"
output=$(cd "$output" && pwd)
# The caller supplies only approved versions, including older versions to retain.
shopt -s nullglob
debs=("$packages"/*.deb)
rpms=("$packages"/*.rpm)
((${#debs[@]} && ${#rpms[@]})) || { echo 'Both DEB and RPM packages are required' >&2; exit 1; }
mkdir -p "$output/apt/pool/main"
for package in "${debs[@]}"; do
    [[ $(dpkg-deb -f "$package" Package) == gox-server ]]
    case $(dpkg-deb -f "$package" Architecture) in amd64|arm64) ;; *) exit 1;; esac
    cp "$package" "$output/apt/pool/main/"
done
for package in "${rpms[@]}"; do
    [[ $(rpm -qp --qf '%{NAME}' "$package") == gox-server ]]
    arch=$(rpm -qp --qf '%{ARCH}' "$package")
    case "$arch" in x86_64|aarch64) ;; *) exit 1;; esac
    mkdir -p "$output/rpm/$arch/Packages"
    target="$output/rpm/$arch/Packages/$(basename "$package")"
    cp "$package" "$target"
    rpmsign --define "_gpg_name $fingerprint" --define '__gpg /usr/bin/gpg' --addsign "$target"
done
cd "$output/apt"
for arch in amd64 arm64; do
    mkdir -p "dists/stable/main/binary-$arch"
    dpkg-scanpackages --multiversion --arch "$arch" pool > "dists/stable/main/binary-$arch/Packages"
    [[ -s "dists/stable/main/binary-$arch/Packages" ]]
    gzip -n -k "dists/stable/main/binary-$arch/Packages"
done
(cd dists/stable && apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=GOX \
    -o APT::FTPArchive::Release::Label=GOX \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o 'APT::FTPArchive::Release::Architectures=amd64 arm64' \
    -o APT::FTPArchive::Release::Components=main release . > Release)
gpg --batch --yes --local-user "$fingerprint" --digest-algo SHA256 \
    --clearsign -o dists/stable/InRelease dists/stable/Release
gpg --batch --yes --local-user "$fingerprint" --digest-algo SHA256 \
    --armor --detach-sign -o dists/stable/Release.gpg dists/stable/Release
for arch in x86_64 aarch64; do
    [[ -d "$output/rpm/$arch/Packages" ]]
    createrepo_c --checksum sha256 "$output/rpm/$arch"
    gpg --batch --yes --local-user "$fingerprint" --digest-algo SHA256 \
        --armor --detach-sign "$output/rpm/$arch/repodata/repomd.xml"
done
gpg --batch --export "$fingerprint" > "$output/gox-archive-keyring.gpg"
gpg --batch --armor --export "$fingerprint" > "$output/gox-signing-key.asc"
printf 'packages.gox-lang.dev\n' > "$output/CNAME"
printf 'Signed repository snapshot created at %s\n' "$output"
