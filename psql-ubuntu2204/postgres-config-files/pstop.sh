#!/bin/bash
#
# Stop postgresql
#

VERSION=13

/usr/pgsql-${VERSION}/bin/pg_ctl -D /db/pg13 -l logfile stop