FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl dpkg-dev apt-utils rpm binutils xz-utils cpio gnupg createrepo-c \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ENTRYPOINT ["bash", "/src/packaging/build.sh"]
