#!/usr/bin/env bash
# Validate either a mounted signed snapshot or the anonymous public repository.
set -euo pipefail
base="${GOX_REPOSITORY_URL:-file:///repository}"
expected="${2:-}"
case "${1:?Supply deb or rpm}" in
  deb)
    if [[ "$base" == file:///repository ]]; then
      install -m 644 /repository/gox-archive-keyring.gpg /usr/share/keyrings/gox.gpg
    else
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
      curl --fail --retry 5 --retry-all-errors "$base/gox-archive-keyring.gpg" -o /usr/share/keyrings/gox.gpg
      actual=$(gpg --show-keys --with-colons /usr/share/keyrings/gox.gpg | awk -F: '$1=="fpr"{print $10;exit}')
      [[ "$actual" == "${GOX_SIGNING_FINGERPRINT:?Set the expected public key fingerprint}" ]]
    fi
    printf 'deb [signed-by=/usr/share/keyrings/gox.gpg] %s/apt stable main\n' "$base" > /etc/apt/sources.list.d/gox.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y gox-server
    ;;
  rpm)
    if [[ "$base" != file:///repository ]]; then
      dnf install -y ca-certificates curl-minimal gnupg2
      curl --fail --retry 5 --retry-all-errors "$base/gox-signing-key.asc" -o /tmp/gox-signing-key.asc
      actual=$(gpg --show-keys --with-colons /tmp/gox-signing-key.asc | awk -F: '$1=="fpr"{print $10;exit}')
      [[ "$actual" == "${GOX_SIGNING_FINGERPRINT:?Set the expected public key fingerprint}" ]]
    fi
    cat > /etc/yum.repos.d/gox.repo <<REPO
[gox]
name=GOX
baseurl=$base/rpm/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$base/gox-signing-key.asc
REPO
    dnf install -y gox-server
    ;;
  *) exit 1 ;;
esac
if [[ -n "$expected" ]]; then
  gox version | grep -F "GOX Server v$expected"
else
  gox version | grep -F 'GOX Server v'
fi
useradd -m -s /bin/bash tester
su - tester -c 'gox version'
echo 'Signed package-manager installation passed.'
