#!/bin/bash

# VARS

proxmoxHostname=`hostname` # get machine hostname
configBackupPathLocal="/tmp" # temp local backup file path
dateCurrent=`date +%Y-%m-%d_%H-%M-%S` # current date line
dayOfMonthCurrent=`date +%d` # current day of month
configBackupName=`hostname`_proxmoxConfig_${dateCurrent} # backup file name
configBackupFile="${configBackupPathLocal}/${configBackupName}.tar.gz" # full path to config backup file
backupServerIp="192.168.1.10" # must be available by SFTP (SSH)
backupServerUser="admin" # ssh login with rw access to backupServerBackupPath*
backupServerPass="P@ssWord" # pass for ssh login
backupServerBackupPathDaily="/mnt/raid2/bkup/config/proxmox/${proxmoxHostname}/daily" # path to daily backup at remote server
backupServerBackupPathMonthly="/mnt/raid2/bkup/config/proxmox/${proxmoxHostname}/monthly" # path to monthly backup at remote server

backupServerBackupFilesLeaveType="lastFiles" # remove old backups type. "lastDays" - keep files for the last N days; "lastFiles" - keep the last N files
backupServerBackupFilesLastN="7" # number of keeping backup files - last days OR last files (depending on option "backupFilesLeaveType")

tar=`which tar`
ssh=`which ssh`
sshpass=`which sshpass`
rsync=`which rsync`
mkdir=`which mkdir`

sshParams="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" # SSH client params when connecting to SSH server
rsyncSshParams="--verbose --progress -ahe" # RSYNC client params when connecting to SSH server

# arrayItemsToBackup - this items will be copied into backup archive
IFS=' ' read -r -a arrayItemsToBackup <<< \
"\
/etc \
/var/spool/cron \
/root \
";

# debug
for i in "${arrayItemsToBackup[@]}";
    do echo "$i";
done

# arch all items to backup file
${tar} -czf ${configBackupFile} --absolute-names ${arrayItemsToBackup[@]}

# if arch success
if [[ $? == 0 ]] ; then

    # DAILY backup

    # create dir at remote server if not exists
    ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
    if ! [ -d "${backupServerBackupPathDaily}" ]; then
        mkdir -p ${backupServerBackupPathDaily}
    fi
HERE

    # send arch to ssh server
    ${sshpass} -p "${backupServerPass}" ${rsync} ${rsyncSshParams} "${ssh} ${sshParams}" ${configBackupFile} ${backupServerUser}@${backupServerIp}:${backupServerBackupPathDaily}/
    dailyBackupStatus=$?

    # MONTHLY backup

    if [[ ${dayOfMonthCurrent} == "01" ]]; then

        # create dir at remote server if not exists
        ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
        if ! [ -d "${backupServerBackupPathMonthly}" ]; then
            mkdir -p ${backupServerBackupPathMonthly}
        fi
HERE

        # send arch to ssh server
        ${sshpass} -p "${backupServerPass}" ${rsync} ${rsyncSshParams} "${ssh} ${sshParams}" ${configBackupFile} ${backupServerUser}@${backupServerIp}:${backupServerBackupPathMonthly}/
        monthlyBackupStatus=$?
    fi
fi

# if send to ssh success
if [[ ${dailyBackupStatus} == 0 ]] ; then

    # check if backup file-arch exist
    if test -f ${configBackupFile}; then
        # remove backup file-arch
        rm -f ${configBackupFile};
    fi
fi


# the following actions depend on value of var "backupServerBackupFilesLeaveType"

# remove old DAILY backups - older than N days
if [[ ${backupServerBackupFilesLeaveType} == "lastDays" ]]; then
 ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
    find ${backupServerBackupPathDaily}/ -mtime +${backupServerBackupFilesLastN} -type f -exec rm -rf {} \;
HERE
fi

# remove old DAILY backups - more than N last files
if [[ ${backupServerBackupFilesLeaveType} == "lastFiles" ]]; then
 ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
    if [[ -d /mnt/raid2/bkup/servers/192.168.17.167/pgsql/daily ]] ;then
        cd ${backupServerBackupPathDaily};
        ls -lt | sed /^total/d | awk 'FNR>${backupServerBackupFilesLastN} {print \$9}' | xargs rm -rf {};
    fi
HERE
fi
