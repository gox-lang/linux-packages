#!/usr/bin/env bash
# Validate package-manager trust against a mounted signed snapshot.
set -euo pipefail
case "${1:?Supply deb or rpm}" in
  deb)
    install -m 644 /repository/gox-archive-keyring.gpg /usr/share/keyrings/gox.gpg
    printf 'deb [signed-by=/usr/share/keyrings/gox.gpg] file:/repository/apt stable main\n' > /etc/apt/sources.list.d/gox.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y gox-server
    ;;
  rpm)
    cat > /etc/yum.repos.d/gox.repo <<'REPO'
[gox]
name=GOX
baseurl=file:///repository/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///repository/gox-signing-key.asc
REPO
    dnf install -y gox-server
    ;;
  *) exit 1 ;;
esac
gox version | grep -F 'GOX Server v'
useradd -m -s /bin/bash tester
su - tester -c 'gox version'
echo 'Signed package-manager installation passed.'
