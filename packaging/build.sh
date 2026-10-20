#!/usr/bin/env bash
# Package the published binary unchanged. Never compile or strip GOX.
set -euo pipefail
version=${1:?Usage: build.sh VERSION ARCH [REVISION]}
arch=${2:?Supply amd64 or arm64}
revision=${3:-1}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ $revision =~ ^[1-9][0-9]*$ ]] || exit 1
case "$arch" in
    amd64) rpm_arch=x86_64; machine='Advanced Micro Devices X86-64' ;;
    arm64) rpm_arch=aarch64; machine=AArch64 ;;
    *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
output=${GOX_PACKAGE_OUTPUT:-$root/dist}
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bash "$root/packaging/download-release.sh" "$version" "$arch" "$work/release"
readelf -h "$work/release/gox" | grep -Fq "$machine"
# Use the highest GLIBC symbol version actually required by the binary.
glibc=$(readelf --version-info "$work/release/gox" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -Vu | tail -1)
[[ -n $glibc ]] || { echo 'Could not determine GLIBC requirement' >&2; exit 1; }
glibc=${glibc#GLIBC_}
stage=$work/stage
mkdir -p "$stage/usr/bin" "$stage/usr/lib/gox" "$stage/usr/share/doc/gox"
install -m 755 "$work/release/gox" "$stage/usr/lib/gox/gox"
install -m 755 "$root/packaging/gox.sh" "$stage/usr/bin/gox"
install -m 644 "$work/release/LICENSE" "$stage/usr/share/doc/gox/copyright"
mkdir -p "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: gox-server
Conflicts: gox
Version: $version-$revision
Architecture: $arch
Maintainer: GOX Maintainers
Section: devel
Priority: optional
Homepage: https://gox-lang.dev
Depends: libc6 (>= $glibc), ca-certificates, gcc, libc6-dev, binutils, git, curl, xz-utils
Description: Web framework and development tools for Go
 Official GOX release binary with package-managed updates.
 GOX provisions its Go and frontend toolchains when needed.
CONTROL
(cd "$stage" && find usr -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz --build "$stage" "$output/gox-server_${version}-${revision}_${arch}.deb"
rm -r "$stage/DEBIAN"
mkdir -p "$work/rpm"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cat > "$work/rpm/SPECS/gox.spec" <<SPEC
Name: gox-server
Conflicts: gox
Version: $version
Release: $revision
Summary: Web framework and development tools for Go
License: MIT
URL: https://gox-lang.dev
AutoReqProv: no
Requires: glibc >= $glibc
Requires: ca-certificates, gcc, glibc-devel, binutils, git, curl, xz
%ifarch aarch64
# Go selects gold when linking Linux ARM64 plugins. Fedora ships it separately.
Requires: binutils-gold
%endif
%description
Official GOX release binary with package-managed updates.
GOX provisions its Go and frontend toolchains when needed.
%install
mkdir -p %{buildroot}
cp -a $stage/usr %{buildroot}/
%files
%defattr(-,root,root,-)
/usr/bin/gox
%dir /usr/lib/gox
/usr/lib/gox/gox
%dir /usr/share/doc/gox
%license /usr/share/doc/gox/copyright
SPEC
# Distribution post-processing must not alter the release binary (Go plugins
# depend on its build metadata). Dependencies are explicitly declared above.
rpmbuild -bb --target "$rpm_arch" --define "_topdir $work/rpm" \
    --define '__os_install_post %{nil}' --define '_build_id_links none' \
    "$work/rpm/SPECS/gox.spec"
cp "$work/rpm/RPMS/$rpm_arch/gox-server-${version}-${revision}.${rpm_arch}.rpm" "$output/"
# Verify that packaging did not modify the release executable.
dpkg-deb -x "$output/gox-server_${version}-${revision}_${arch}.deb" "$work/deb-check"
mkdir "$work/rpm-check"
rpm2cpio "$output/gox-server-${version}-${revision}.${rpm_arch}.rpm" | \
    (cd "$work/rpm-check" && cpio --quiet -idm)
cmp "$work/release/gox" "$work/deb-check/usr/lib/gox/gox"
cmp "$work/release/gox" "$work/rpm-check/usr/lib/gox/gox"
(cd "$output" && sha256sum "gox-server_${version}-${revision}_${arch}.deb" \
    "gox-server-${version}-${revision}.${rpm_arch}.rpm" > "checksums-${arch}-${revision}.sha256")
printf 'Built GOX %s-%s for %s (GLIBC >= %s)\n' "$version" "$revision" "$arch" "$glibc"
