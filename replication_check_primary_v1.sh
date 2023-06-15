#!/bin/bash
#
# Check the Postgres 13 replication status.
#
# Date: Sun 2023Jan08 21:34:50 PST
#
echo
echo "Replication status on PRIMARY DB server."
echo
psql -x -c "select * from pg_stat_replication;"
echo
psql -x -c "select * from pg_stat_activity;"
echo
echo "Check replication SLOTS"
psql -c "SELECT redo_lsn, slot_name,restart_lsn, round((redo_lsn-restart_lsn) / 1024 / 1024 / 1024, 2) AS GB_behind FROM pg_control_checkpoint(), pg_replication_slots;"
echo
echo "Check the WAL directory"
echo
echo "number of files ...: `ls /db/pg13/pg_wal | wc -l`"
echo "directory size ....: `du -sh /db/pg13/pg_wal`"
echo