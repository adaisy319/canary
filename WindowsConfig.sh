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

# Reload systemd services
systemctl daemon-reload

# Enable and start the new systemd service
systemctl enable opencanary.service
systemctl start opencanary.service

# Reboot the canary
reboot
