#!/bin/bash
#
# Script for DevStack installation on a Ubuntu LTS (14.04) system.
#
#   2016, alex(at)wintermute.ai
#

OPTDIR="/opt/stack"
STACKUSER="stack"
STACKHOME="/home/${STACKUSER}"
STACKDIR="${STACKHOME}/devstack"
SWPACKAGES="git augeas-tools openssl"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EXTACCESS=""

while getopts e FLAG; do
    case $FLAG in
        e)  EXTACCESS=1 ;;
    esac
done
shift $((OPTIND-1))

mkdir -p ${OPTDIR}
apt-get -y remove apparmor
apt-get -y install ${SWPACKAGES}
useradd -d ${STACKHOME} -s /bin/bash -m ${STACKUSER}

augtool -s <<EOC
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/user "${STACKUSER}"
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/host_group/host "ALL"
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/host_group/command  "ALL"
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/host_group/command/runas_user "ALL"
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/host_group/command/runas_group "ALL"
set /files/etc/sudoers/spec[user = "${STACKUSER}"]/host_group/command/tag  "NOPASSWD"
EOC

git clone https://git.openstack.org/openstack-dev/devstack ${STACKDIR}

password=`openssl rand -hex 8`
echo '[[local|localrc]]' > ${STACKDIR}/local.conf
echo ADMIN_PASSWORD=${password} >> ${STACKDIR}/local.conf
echo DATABASE_PASSWORD=${password} >> ${STACKDIR}/local.conf
echo RABBIT_PASSWORD=${password} >> ${STACKDIR}/local.conf
echo SERVICE_PASSWORD=${password} >> ${STACKDIR}/local.conf
chown -R ${STACKUSER}:${STACKUSER} ${STACKHOME} ${OPTDIR}

su -l ${STACKUSER} ${STACKDIR}/stack.sh > /var/log/devstack_install.log 2>&1

if [ -f "/etc/profile.d/wmaic.sh" ];then
    source /etc/profile.d/wmaic.sh
fi

if [ -n "${WMAIC_PUBLIC_IP4}" -a -n "${EXTACCESS}" ];then
    export OS_TENANT_NAME=admin
    export OS_USERNAME=admin
    export IDENTITY_API_VERSION=3
    export ADMIN_PASSWORD=${password}
    source ${STACKDIR}/openrc
    while read -r endpoint;do 
        IFS=' ' read -r -a eprecord <<< "$endpoint"
        if [ "${eprecord[5]}" == "public" ];then
            externalURL=`echo "${eprecord[6]}" | sed -r 's/(\b[0-9]{1,3}\.){3}[0-9]{1,3}\b'/${WMAIC_PUBLIC_IP4}/`
            openstack endpoint set --url ${externalURL} ${eprecord[0]}
        fi        
    done < <(openstack endpoint list -f value)
fi

if [ -n "${WMAIC_PUBLIC_HOSTNAME}" ];then
    echo "Public Horizon URL: http://${WMAIC_PUBLIC_HOSTNAME}/dashboard" >> /var/log/devstack_install.log
fi

tail -20 /var/log/devstack_install.log
echo;echo "*** devstack install finished, please check log file: /var/log/devstack_install.log";echo
