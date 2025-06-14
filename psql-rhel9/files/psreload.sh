#!/bin/bash
#
# Reload postgresql
#

VERSION=13

/usr/pgsql-${VERSION}/bin/pg_ctl -D /db/pg13 -l logfile reload