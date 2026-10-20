#!/usr/bin/env bash
set -euo pipefail
format=${1:?Supply deb or rpm}
version=${2:-0.1.3}
arch=${3:-amd64}
case "$arch" in amd64) rpm_arch=x86_64;; arm64) rpm_arch=aarch64;; *) exit 1;; esac
case "$format" in
    deb)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y "/packages/gox-server_${version}-1_${arch}.deb"
        apt-get install -y --reinstall "/packages/gox-server_${version}-1_${arch}.deb"
        apt-get install -y "/packages/gox-server_${version}-2_${arch}.deb"
        [[ $(dpkg-query -W -f='${Version}' gox-server) == "$version-2" ]]
        ;;
    rpm)
        dnf install -y "/packages/gox-server-${version}-1.${rpm_arch}.rpm"
        dnf reinstall -y "/packages/gox-server-${version}-1.${rpm_arch}.rpm"
        dnf install -y "/packages/gox-server-${version}-2.${rpm_arch}.rpm"
        [[ $(rpm -q --qf '%{VERSION}-%{RELEASE}' gox-server) == "$version-2" ]]
        ;;
    *) exit 1 ;;
esac
[[ $(stat -c '%U:%G:%a' /usr/lib/gox/gox) == root:root:755 ]]
if [[ $arch == arm64 ]]; then
    # Exercise the linker selected by Go before downloading the Go toolchain.
    printf 'int gox_link_check(void) { return 0; }\n' | \
        gcc -x c -shared -fPIC -fuse-ld=gold -o /tmp/gox-link-check.so -
    rm /tmp/gox-link-check.so
fi
useradd -m -s /bin/bash tester
su - tester -c "bash /checks/project.sh $version"
# Upgrade a package revision, not a fabricated upstream release. The executable
# should remain the exact same published binary throughout this packaging test.
case "$format" in
    deb) apt-get remove -y gox-server; apt-get purge -y gox-server ;;
    rpm) dnf remove -y gox-server ;;
esac
[[ ! -e /usr/bin/gox && ! -e /usr/lib/gox/gox ]]
[[ -d /home/tester/smoke-project ]]
[[ -s /home/tester/page.html ]]
# A toolchain directory must survive uninstall, regardless of GOX's cache layout.
[[ -n $(find /home/tester -type f -path '*/bin/go' -print -quit) ]]
echo 'Installation, reinstall, package upgrade, plugins, HTTP and uninstall passed.'
