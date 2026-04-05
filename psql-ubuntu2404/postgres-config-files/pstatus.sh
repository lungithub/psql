#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

PURPOSE: Status of PostgreSQL service

Uses systemctl instead of pg_ctl — works correctly with Ubuntu 22.04/24.04.
pg_ctl requires running as the postgres user and direct data dir access;
systemctl works from any user with sudo and is the correct approach for
systemd-managed services.

VERSION resolution: PG_VERSION env var > local default
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
COMMENT

VERSION="${PG_VERSION:-13}"

sudo systemctl status postgresql@${VERSION}-main.service --no-pager
