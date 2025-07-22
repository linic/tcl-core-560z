#!/bin/sh

##################################################################
# Basic example using the `ftpget` command included in busybox.
# The FTP server in this example is at 192.168.0.51. Change this
# to your FTP server IP address.
# A password file is assumed to exist. Edit to your liking.
##################################################################

if [ ! /home/tc/configuration/ftp-password ]; then
  echo "Please create the /home/tc/configuration/ftp-password "\
    "file and add the password to download files from the FTP server."
  exit 2
fi

if [ ! /home/tc/configuration/ftp-server-address ]; then
  echo "Please create the /home/tc/configuration/ftp-server-address "\
    "file and add the IP address of your FTP server."
  exit 2
fi

export password=$(cat /home/tc/configuration/ftp-password)
export ftp_server_address=$(cat /home/tc/configuration/ftp-server-address)
ftpget -u ftpsecure -p $password $ftp_server_address $1

