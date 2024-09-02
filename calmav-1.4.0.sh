service=clamav-l-daemon
echo '[Unit]
Description=Socket for Clam AntiVirus userspace daemon
Documentation=man:clamd(8) man:clamd.conf(5) https://docs.clamav.net/
# Check for database existence
ConditionPathExistsGlob=/var/lib/clamav/main.{c[vl]d,inc}
ConditionPathExistsGlob=/var/lib/clamav/daily.{c[vl]d,inc}

[Socket]
ListenStream=/run/clamav/clamd.ctl
#ListenStream=1024
SocketUser=clamav
SocketGroup=clamav
RemoveOnStop=True

[Install]
WantedBy=sockets.target' | sudo tee /etc/systemd/system/${service}.socket

echo '# /usr/lib/systemd/system/clamav-l-daemon.service
[Unit]
Description=Clam AntiVirus userspace daemon
Documentation=man:clamd(8) man:clamd.conf(5) https://docs.clamav.net/
Requires=clamav-l-daemon.socket
# Check for database existence
ConditionPathExistsGlob=/var/lib/clamav/main.{c[vl]d,inc}
ConditionPathExistsGlob=/var/lib/clamav/daily.{c[vl]d,inc}

[Service]
ExecStart=/usr/local/sbin/clamd --foreground=true
# Reload the database
ExecReload=/bin/kill -USR2 $MAINPID
TimeoutStartSec=420

[Install]
WantedBy=multi-user.target
Also=clamav-daemon.socket' | sudo tee /etc/systemd/system/${service}.service

sudo mkdir /etc/systemd/system/${service}.service.d
echo'# /etc/systemd/system/clamav-daemon.service.d/extend.conf
[Service]
ExecStartPre=-/bin/mkdir -p /run/clamav
ExecStartPre=/bin/chown clamav /run/clamav' | sudo tee /etc/systemd/system/${service}.service.d/extend.conf

sudo systemctl enable --now ${service}.service

# /usr/lib/systemd/system/.service
service=clamav-l-freshclam
echo '[Unit]
Description=ClamAV virus database updater
Documentation=man:freshclam(1) man:freshclam.conf(5) https://docs.clamav.net/
# If user wants it run from cron, do not start the daemon.
ConditionPathExists=!/etc/cron.d/clamav-freshclam
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/freshclam -d --foreground=true

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/${service}.service
sudo systemctl enable --now ${service}.service

service=clamav-l-onacc
echo '[Unit]
Description=ClamAV On Access Scanner
Requires=clamav-l-daemon.service
After=clamav-daemon.service

[Service]
ExecStartPre=/bin/bash -c "while [ ! -S /var/run/clamav/clamd.ctl ]; do sleep 1; done"
ExecStart=/usr/local/sbin/clamonacc -F --log=/var/log/clamav/access.log --fdpass
Restart=on-failure

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/${service}.service
sudo systemctl enable --now ${service}.service
