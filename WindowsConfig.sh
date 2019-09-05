#!/bin/sh

# Get the device name to use for the canary
read -p 'What hostname do you want to use? [A-Z,a-z,0-9]: ' hs

# Check whether the hostname input is empty
if test -z "$hs"
then
      # If the hostname is empty, do nothing. Set the hostname variable to use
      echo "Not changing hostname"
      hs=$(hostname)
else
# Validate the hostname providehttps://github.com/adaisy319/canary/blob/master/OC-installer.shd matches the required pattern
while [[ ! "$hs" =~ ^[a-z,A-Z,0-9]{1,}$ ]]; do
    read -p "Wrong hostname format. Re-enter using only A-Z, or a-z: " hs
done

# Reset the hostname
echo "$hs" > /etc/hostname
cat >/etc/hosts <<EOL
127.0.0.1   localhost
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
127.0.1.1   $hs
EOL
hostnamectl set-hostname "$hs"
fi

# Get the IP address for the syslog server
read -p 'What is the IP address for your syslog server? ' syslogip

# Get the port to use for the syslog server
read -p 'What port is your syslog server listening on? ' syslogport

# Update the OS
yum install update 

# Install dependencies
yum install -y  gcc gcc-c++ make  openssl-devel libffi-devel python-devel python-pip python-virtualenv

# Create a python virtualenv
virtualenv env/

# Activate the virtualenv
. env/bin/activate

# Install OpenCanary dependencies
yes | pip install rdpy
yes | pip install scapy pcapy

# Install OpenCanary
yes | pip install OpenCanary 

#Install SMB
yum install samba samba-client samba-common

#set up firewall
firewall-cmd --permanent --zone=public --add-service=samba 
firewall-cmd --reload 

# Generate a new config file
cat >opencanary.conf <<EOL
{   
    "device.node_id": "opencanary-1",
    "ftp.banner": "FTP server ready",
    "ftp.enabled": false,
    "ftp.port":21,
    "http.banner": "Microsoft IIS 7.5",
    "http.enabled": true,
    "http.port": 80,
    "http.skin": "nasLogin",
    "http.skin.list": [
        {   
            "desc": "Plain HTML Login",
            "name": "basicLogin"
        },
        {   
            "desc": "Microsoft NAS Login",
            "name": "nasLogin"
        }
    ],
    "logger": {
        "class" : "PyLogger",
        "kwargs" : {
            "formatters": {
                "plain": {
                    "format": "%(message)s"
                }
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout"
                },
                "file": {
                    "class": "logging.FileHandler",
                    "filename": "/var/tmp/opencanary.log"
                },
                "syslog-unix": {
                    "class": "logging.handlers.SysLogHandler",
                    "address": ["localhost", 514],
                    "socktype": "ext://socket.SOCK_DGRAM"
                },
                "json-tcp": {
                    "class": "opencanary.logger.SocketJSONHandler",
                    "host": "127.0.0.1",
                    "port": 1514
                }
            }
        }
    },
    "portscan.synrate": "5",
    "smb.auditfile": "/var/log/samba-audit.log",
    "smb.configfile": "/etc/samba/smb.conf",
    "smb.domain": "local.nii.com",
    "smb.enabled": true,
    "smb.filelist": [
        {
            "name": "2016-Tender-Summary.pdf",
            "type": "PDF"
        },
        {
            "name": "passwords.docx",
            "type": "DOCX"
        }
    ],
    "smb.mode": "workgroup",
    "smb.netbiosname": "Microsoft FileServer",
    "smb.serverstring": "Windows 2003 File Server",
    "smb.sharecomment": "Human Resource Documents Backup",
    "smb.sharename": "NII Documents",
    "smb.sharepath": "/home/inr/share",
    "smb.workgroup": "nii.local",
    "rdp.enabled": true,
    "tftp.enabled": true,
    "mssql.enabled": true,
}
EOL 


# Replace the default created opencanary conf file
cp -f opencanary.conf /root/.opencanary.conf

wd=$PWD
user=`whoami` 

#SMB config file
cat >/etc/samba/smb.conf <<EOL  
[global]
   workgroup = nii.local
        server string = Windows 2003 File Server
   dns proxy = no
;   interfaces = 127.0.0.0/8 eth0
;   bind interfaces only = yes
   log file = /var/log/samba/log.all
   max log size = 1000
EOL 

cat>/etc/rsyslog.conf <<EOL 
$FileCreateMode 0644

local7.*

/var/log/samba-audit.log
 
EOL 

# for opencanary purposes
 log level = 0
 vfs object = full_audit
 full_audit:prefix = %U|%I|%i|%m|%S|%L|%R|%a|%T|%D
 full_audit:success = pread
 full_audit:failure = none
 full_audit:facility = local7
 full_audit:priority = notice
 max log size = 100

   syslog = 0
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   passdb backend = tdbsam
   obey pam restrictions = yes
   unix password sync = no
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
;   logon path = \\%N\profiles\%U
;   logon drive = H:
;   logon script = logon.cmd
; add user script = /usr/sbin/adduser --quiet --disabled-password --gecos "" %u
; add machine script  = /usr/sbin/useradd -g machines -c "%u machine account" -d /var/lib/samba -s /bin/false %u
; add group script = /usr/sbin/addgroup --force-badname %g
;   include = /home/samba/etc/smb.conf.%m
;   idmap uid = 10000-20000
;   idmap gid = 10000-20000
;   template shell = /bin/bash
;   usershare max shares = 100
   usershare allow guests = yes
;[homes]
;   comment = Home Directories
;   browseable = no
;   read only = yes
;   create mask = 0700
;   directory mask = 0700
;   valid users = %S
;[netlogon]
;   comment = Network Logon Service
;   path = /home/samba/netlogon
;   guest ok = yes
;   read only = yes

;[profiles]
;   comment = Users profiles
;   path = /home/samba/profiles
;   guest ok = no
;   browseable = no 
;   create mask = 0600
;   directory mask = 0700

[printers]
   comment = All Printers
   browseable = no
   path = /var/spool/samba 
   printable = yes
   guest ok = no
   read only = yes
   create mask = 0700
[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes   
   read only = yes
   guest ok = no
;   write list = root, @lpadmin

# for opencanary purposes
[Documents]
   comment = Human Resource Documents Backup
   path = /home/inr/share
   guest ok = yes
   read only = yes
   browseable = yes
# Create a systemd service file
cat >/etc/systemd/system/opencanary.service <<EOL
[Unit]
Description=OpenCanary honeypot
After=syslog.target
After=network.target
[Service]
User=$user
Restart=always
Environment=VIRTUAL_ENV=/home/pi/env/
Environment=PATH=\$VIRTUAL_ENV/bin:/usr/bin:\$PATH
WorkingDirectory=$wd/env/bin
ExecStart=$wd/env/bin/opencanaryd --dev
[Install]
WantedBy=multi-user.target
EOL 

# Replace the default created SMB config file
cp -f /etc/samba/smb.conf /root/etc/samba/smb.conf

wd=$PWD
user=`whoami` 

# Reload systemd services
systemctl daemon-reload

# Enable and start the new systemd service
systemctl enable opencanary.service
systemctl start opencanary.service

# Reboot the canary
reboot
