#!/bin/bash
#
# Start postgresql
#
# /usr/lib/postgresql/13/bin/pg_ctl -D /db/mypg13 -l logfile {start|stop|status}
#

VERSION=13
DB_DIR=/db/mypg${VERSION}

/usr/lib/postgresql/${VERSION}/bin/pg_ctl -D ${DB_DIR} -l logfile stop