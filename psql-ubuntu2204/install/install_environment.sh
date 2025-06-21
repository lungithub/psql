#!/bin/bash
#
# Date: Sat 2023Jan14 13:17:51 PST
#
BASEDIR=/hostdata/app/psql_config

# install centos packages
${BASEDIR}/install_centos_packages.sh

# copy the etc_sudoers and etc_group for sudo perms
${BASEDIR}/copy_sudo.sh
