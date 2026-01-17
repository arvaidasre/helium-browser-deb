FROM fedora:43
ENV DNF_FRONTEND=noninteractive
RUN dnf update -y \
  && dnf install -y --setopt=install_weak_deps=False \
    ca-certificates \
    curl \
    jq \
    git \
    dpkg-dev \
    ruby \
    ruby-devel \
    gcc \
    make \
    rpm-build \
    createrepo_c \
  && gem install --no-document fpm \
  && dnf clean all
WORKDIR /work
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
