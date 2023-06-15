#!/bin/bash
#
# Install Postgres
#
# initialize the  DB directory
# su - postgres -c "'/usr/pgsql-${VERSION}/bin/initdb -D /db/pg${VERSION}'"
# su - postgres -c "'/usr/pgsql-13/bin/initdb -D /db/pg13'"
#
# Date: Sat 2023Jan14 13:17:51 PST
#

# change the version number to install it
VERSION=13

#(primary/secondary) Install the repo
yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Required for compose on aarch64
dnf -y module disable postgresql --nogpgcheck

#(primary/secondary) Install psql13 
# yum -y install postgresql${VERSION} postgresql${VERSION}-server --nogpgcheck 
dnf -y install postgresql${VERSION}  postgresql${VERSION}-server  --nogpgcheck

#(primary/secondary) create data dir 
mkdir -p /db/pg${VERSION} 
chown -R postgres:postgres /db/pg${VERSION}
ls -ld /db/pg${VERSION}

#Rename the data dir and create the linking
cd /var/lib/pgsql/${VERSION} 
mv data data_ORIG 
ln -s /db/pg${VERSION} /var/lib/pgsql/${VERSION}/data || echo "Could not create soft link to psql data directory"
echo
echo "Verify psql data directory."
echo
ls -l /var/lib/pgsql/${VERSION}/data || echo "Unable to create psql data directory."
echo 

# create the location for log files
mkdir /var/log/postgres;
chown postgres:postgres /var/log/postgres;
chmod 700 /var/log/postgres;
echo
echo "Verify postgres log files location."
echo
ls -ld /var/log/postgres || echo "Unable to create psql data directory."
echo 

# create the location for LOCK files - needed to start PSQL
# this solves a problem seen in a docker container environment
mkdir /var/run/postgresql;
chown postgres:postgres /var/run/postgresql;
chmod 755 /var/run/postgresql;
echo
echo "Verify postgres LOCK files location."
echo
ls -ld /var/run/postgresql || echo "Unable to create psql LOCK directory."
echo

# copy files to manage the service
/hostdata/data/env_config/psql_config/copy_psql_management_files.sh

# configure the postgres shell environment
su - postgres -c "/hostdata/data/env_config/env_shell/copy_env_shell_files.sh"
