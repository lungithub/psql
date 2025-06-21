#!/bin/bash
#
# Status postgresql
#

VERSION=13

/usr/pgsql-${VERSION}/bin/pg_ctl -D /db/pg13 -l logfile status