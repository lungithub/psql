#!/bin/sh
#
# I have a preconfigured GROUPS and SUDOERS file with the posgres
# user. I just copy those files to the container to enable sudo 
# for postgres.
#
# Perms for refernce
#
# ls -l /etc/group
# -rw-r--r-- 1 root root 373 Jan  9 01:53 /etc/group
#

BASEDIR=/hostdata/app/psql
USER=postgres

# check perms before and after copy
cp /etc/sudoers /etc/sudoers.$$
cp ${BASEDIR}/files/etc_sudoers /etc/sudoers
chmod 440 /etc/sudoers
echo
echo "Verify postgres in the SUDOERS file"
echo
ls -l /etc/sudoers
grep postgres /etc/sudoers || echo "postgres not in /etc/sudoers"
echo 

# add the user to the wheel sudo group
usermod -a -G wheel $USER