FROM erlang:22.3.4.26

WORKDIR /opt/snatch-echo

# Mirror executor localbuilder base handling for old Debian repos.
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list

# Needed for git-based rebar deps (snatch, amqp_client) and native deps.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY rebar.config ./
COPY src ./src

RUN env -u ERL_COMPILER_OPTIONS rebar3 escriptize
