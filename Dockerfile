FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    git \
    dpkg-dev \
    apt-utils \
    ruby \
    ruby-dev \
    build-essential \
    rpm \
    createrepo-c \
  && gem install fpm \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
