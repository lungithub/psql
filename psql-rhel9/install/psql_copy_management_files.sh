#!/bin/bash

# copy files to manage the service
mkdir /var/lib/pgsql/bin

# go to the location of the files
BASEDIR=/hostdata/app/psql_config

cp ${BASEDIR}/files/pstart.sh /var/lib/pgsql/bin
ln -s /var/lib/pgsql/bin/pstart.sh /usr/local/bin/pstart

cp ${BASEDIR}/files/pstop.sh /var/lib/pgsql/bin
ln -s /var/lib/pgsql/bin/pstop.sh /usr/local/bin/pstop

cp ${BASEDIR}/files/pstatus.sh /var/lib/pgsql/bin
ln -s /var/lib/pgsql/bin/pstatus.sh /usr/local/bin/pstatus

cp ${BASEDIR}/files/psreload.sh /var/lib/pgsql/bin
ln -s /var/lib/pgsql/bin/psreload.sh /usr/local/bin/psreload

chown -R postgres:postgres /var/lib/pgsql/bin
chmod 700 /var/lib/pgsql/bin/*

echo
echo "Verify startup scripts."
echo
ls -l /var/lib/pgsql/bin/pst* || echo "Unable to copy psql management files."
echo 

# back to top root homedir
cd /root
