#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

PURPOSE: Check the Postgres 13 replication status.

This script is designed to check the replication status of a PostgreSQL 13 database setup. 
It runs a series of SQL commands to retrieve information about the replication status 
on both the primary and secondary database servers. The script also checks the number 
of files and the size of the WAL (Write-Ahead Logging) directory, which is crucial for 
understanding the replication lag and overall health of the replication setup. 

Date: Sun 2023Jan08 21:34:50 PST
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
COMMENT

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