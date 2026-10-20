# GOX Linux packages

Packaging and validation for the official GOX APT and RPM distributions.
Downloads come exclusively from [GOX Server GitHub Releases](https://github.com/gox-lang/server/releases).
The shared downloader verifies SHA-256 before packaging. GOX is never rebuilt or
stripped; no executables or generated packages are committed to this repository.

The signed public repositories are not published yet. The intended addresses are
`https://packages.gox-lang.dev/apt` and `https://packages.gox-lang.dev/rpm`.

## Build packages

Requires Docker. From this repository:

```sh
docker build -t gox-linux-packager -f packaging/Dockerfile .
mkdir -p dist
for arch in amd64 arm64; do
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/src:ro" -v "$PWD/dist:/out" \
    -e GOX_PACKAGE_OUTPUT=/out \
    gox-linux-packager 0.1.3 "$arch" 1
done
```

The final argument is a package revision. Packaging fixes can increment it without
inventing a new upstream GOX release. Artifacts are created in `dist/`:

- `gox-server_0.1.3-1_amd64.deb` and `gox-server_0.1.3-1_arm64.deb`
- `gox-server-0.1.3-1.x86_64.rpm` and `gox-server-0.1.3-1.aarch64.rpm`
- Per-architecture SHA-256 manifests

## Installation layout

`/usr/bin/gox` is a small shell launcher. The unmodified release executable is
installed at `/usr/lib/gox/gox`, owned by root. The launcher prevents `gox update`
and LSP auto-update from replacing files owned by APT or DNF.

Packages declare the C compiler, development headers, certificates and other system
dependencies required for development. The minimum GLIBC version is derived from
the released executable. GOX downloads its own Go/frontend toolchains into the
user's cache when needed. Installation does not run GOX as root, download toolchains
in a maintainer script, modify user shell profiles, or touch project files.

## Validation

CI builds packages on native amd64 and arm64 runners. It installs them in clean
Debian 12, Ubuntu 24.04 and Fedora 43 containers, reinstalls, upgrades a packaging
revision, runs a project as an unprivileged user, verifies plugins and HTTP, and
uninstalls while preserving the project and toolchain cache.

For a local amd64 test, first build revisions 1 and 2, then run:

```sh
docker run --rm -v "$PWD/dist:/packages:ro" -v "$PWD/checks:/checks:ro" \
  ubuntu:24.04 bash /checks/install.sh deb 0.1.3 amd64
docker run --rm -v "$PWD/dist:/packages:ro" -v "$PWD/checks:/checks:ro" \
  fedora:43 bash /checks/install.sh rpm 0.1.3 amd64
```

These are unsigned development artifacts. Public distribution requires signed APT
metadata and signed RPM packages/metadata, a protected publication workflow and
anonymous end-to-end installation tests from the public URL. Test revisions must
not be published as production updates.

## Publication milestones

1. Pass packaging and runtime tests on all supported architectures/distributions.
2. Configure the GitHub repository and a protected signing environment.
3. Prepare signed APT/RPM indexes, retaining older versions and publishing packages
   before indexes that reference them. Store the signing key only in protected
   secrets, with an independent secure backup; never commit it.
4. Connect the package hostname, verify signatures and tamper rejection from clean
   clients, then document installation on the GOX website.

## Project

- [GOX website](https://gox-lang.dev)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

[MIT](LICENSE), Copyright (c) 2026 Javier Marquez.

## Signed snapshot preparation

[packaging/repository.sh](packaging/repository.sh) creates APT and RPM trees from
an explicitly supplied set of approved packages. It requires both architectures,
a new destination directory and `GOX_SIGNING_FINGERPRINT` pointing to a secret key
already available through GnuPG. It exports only the public key to the snapshot.
RPM packages and repository metadata are signed; APT authenticates package hashes
through its signed Release metadata. The generated snapshot contains packages and
indexes and can be hosted as static files on GitHub Pages.

[checks/signatures.sh](checks/signatures.sh) tests snapshot creation with a temporary,
throwaway key, checks signatures, and requires altered metadata to fail verification.
It does not create or configure a production signing key. CI never publishes the
test snapshot. CI also exercises signed APT/DNF installation. Production DNS and anonymous
HTTPS installation checks remain required before announcing availability.

## Publishing

The package is named **`gox-server`** to avoid Debian's unrelated `gox` package.
The installed command remains **`gox`**. The packages conflict explicitly with that
other package because both own the same command path.

Run **Publish Linux repositories** manually from `main`. It runs the full native
CI suite, downloads only its revision-1 artifacts, signs a complete snapshot,
tests APT and DNF installation, archives new packages in GitHub Releases and then
deploys the snapshot with GitHub Pages. Publication is serialized. Failed build,
signing or client checks prevent deployment.

The `package-signing` environment must allow only `main` and contain the encrypted
GitHub Actions secret `GOX_SIGNING_KEY` (an ASCII-armored signing subkey export).
The primary certification key and its revocation certificate stay offline; never
upload them to GitHub. Keep an independent secure backup before relying on the key.
The public key is [packaging/signing-key.asc](packaging/signing-key.asc), and its
primary fingerprint is pinned in
[packaging/signing-fingerprint.txt](packaging/signing-fingerprint.txt).

GitHub Pages must use **GitHub Actions** as its source, with the custom domain
`packages.gox-lang.dev`. Configure a DNS-only CNAME to `gox-lang.github.io`, and
enforce HTTPS once GitHub provisions the certificate.

[packaging/releases.txt](packaging/releases.txt) lists approved versions and package
revisions. Retain existing entries. Previously published packages are downloaded
from this repository's GitHub Releases and their checksums verified; they are not
rebuilt or overwritten. For a new release, update the native CI version/revisions
and the approved list together. Never publish revision 2 from the upgrade smoke
test accidentally. Signing-key rotation requires a separate reviewed migration.

Only announce installation after anonymous HTTPS installation has passed on the
public hostname. Until then the website should keep this method marked pending.
