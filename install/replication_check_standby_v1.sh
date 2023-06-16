#!/bin/bash
#
# Check the Postgres 13 replication status.
#
# Date: Sun 2023Jan08 21:34:50 PST
#
echo
echo "Replication status on SECONDARY DB server."
echo
psql -x -c "select * from pg_stat_wal_receiver;"
echo
echo "Check the WAL directory"
echo
echo "number of files ...: `ls /db/pg13/pg_wal | wc -l;`"
echo "directory size ....: `du -sh /db/pg13/pg_wal`"
echo