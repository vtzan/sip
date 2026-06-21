# OpenSIPS 3.6 Teams SBC image (also used for the rotation sidecar).
# Build context is the teams-sbc/ directory.
FROM opensips/opensips:3.6

USER root

# Tooling for bootstrap, DB access, m4 build, ACME and cert handling.
# NOTE: the base image must provide the OpenSIPS modules used by opensips.m4
# (db_mysql, tls_mgm, proto_tls, permissions, sqlops, rtpengine, dialog, uac,
#  httpd, mi_http, ...). On the packaged distro these live in opensips-*-modules
# packages; add them here if your base image is slimmed down.
RUN apt-get update && apt-get install -y --no-install-recommends \
        default-mysql-client python3 python3-pip m4 make openssl curl ca-certificates bash \
 && (pip3 install --no-cache-dir --break-system-packages pymysql cryptography \
     || pip3 install --no-cache-dir pymysql cryptography) \
 && rm -rf /var/lib/apt/lists/*

# Baked-in copy; docker-compose also bind-mounts the dir for live edits.
COPY . /etc/opensips/teams-sbc
RUN chmod +x /etc/opensips/teams-sbc/docker/*.sh \
             /etc/opensips/teams-sbc/scripts/*.sh \
             /etc/opensips/teams-sbc/tls-rotation/*.sh \
             /etc/opensips/teams-sbc/tls-rotation/*.py 2>/dev/null || true

ENTRYPOINT ["/etc/opensips/teams-sbc/docker/entrypoint.sh"]
