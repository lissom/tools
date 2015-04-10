#!/bin/bash

#
# RUN THESE VARIABLES FOR THE COMMANDS TO WORK
# 

USERCMD=$1
#default values
DISKSTART=0
DISKEND=3
MONGOSTART=0
MONGOEND=0
WT_CACHESIZE=100
DATABASE=test
COLLECTION=test
MONGOD_EXECUTABLE=mongod
MONGOS_EXECUTABLE=mongos
MONGO_PORT_PREFIX=370
MONGOSHOST=10.70.70.10
MONGOSPORT=27017
AGENTHOST=10.70.70.10
#should match RA, which I usually set to 16
MDADM_CHUNK=16
#used for modulo so 1 indexed
NUMANODECOUNT=4
#CGPREFIX settings:
#RHEL=
#UBUNTU=/sys/fs
CGPREFIX=
CGEXEC=cgexec
CGROUP_MONGOD_RAM=4G
if [ ! -z $2 ]; then MONGOEND=$2; fi
if [ ! -z $3 ]; then DISKEND=$3; fi
if [ ! -z $4 ]; then NUMANODECOUNT=$4; fi
PROGRAMS="nano screen xfsprogs mdadm numactl htop"

if [ -e /etc/os-release ]; then
	grep -q "debian" /etc/os-release
	if [ $? -eq 0 ]; then OSVERSION="debian"; fi
	grep -q "rhel" /etc/os-release
	if [ $? -eq 0 ]; then OSVERSION="rhel"; fi
fi
if [ -e /etc/centos-release ]; then 
  OSVERSION="rhel"; 
  grep -q " 6\." /etc/centos-release
  if [ $? -eq 0 ]; then OS_RELEASE_MAJOR=6; fi
  grep -q " 7\." /etc/centos-release
  if [ $? -eq 0 ]; then OS_RELEASE_MAJOR=7; fi
fi

set -u

#declare -a HOSTS=("172.31.20.42" "172.31.20.40" "172.31.20.41")
#declare -a WEEKLYJOBS=("agg1.js" "agg2.js" "agg4.js" "agg5.js")

#
# END VARIALBES
#

installrhel() {
sudo yum -y update
wget http://packages.sw.be/rpmforge-release/rpmforge-release-0.5.2-2.el6.rf.x86_64.rpm
rpm -ihv rpmforge-release*.rf.x86_64.rpm
sudo yum install -y ${PROGRAMS}
}

installdebian() {
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ${PROGRAMS}
}

installos() {
case $OSVERSION in
  debian) installdebian;
	return 0;
  ;;
  rhel) installrhel;
	return 0;
  ;;
esac
echo No OS detected
return 1;
}

installmongo() {
case $OSVERSION in
  debian) mongoinstalldebian26;
	return 0;
  ;;
  rhel) mongoinstallrhel30;
	return 0;
  ;;
esac
echo No OS detected
return 1;
}

munininstallrhel() {
if [ "$OSVERSION" = "rhel" && OS_RELEASE_MAJOR -eq 6 ]; then
  rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
fi
#install munin-node
yum -y install munin-node
ln -s /usr/share/munin/plugins/iostat /etc/munin/plugins/iostat
ln -s /usr/share/munin/plugins/iostat_ios /etc/munin/plugins/iostat_ios
sed -i '/^allow/d' /etc/munin/munin-node.conf
#this needs to be set to the munin node monitor
cat << EOF >> /etc/munin/munin-node.conf
allow 127.0.0.1
allow $AGENTHOST
EOF
#cat <<EOF>> /etc/munin/plugin-conf.d/munin-node 
#[iostat]
#    env.SHOW_NUMBERED 1
#EOF

service munin-node restart
chkconfig munin-node on
ps aux | grep munin
}

mongoinstallrhel30() {
sudo \rm /etc/yum.repos.d/mongodb.repo
yum list installed | grep mongo | awk '{ print $1 }' | xargs yum remove -y {};
echo "[mongodb-org-3.0]
name=MongoDB Repository
baseurl=http://repo.mongodb.org/yum/redhat/${OS_RELEASE_MAJOR}/mongodb-org/3.0/x86_64/
gpgcheck=0
enabled=1" | sudo tee -a /etc/yum.repos.d/mongodb.repo
sudo yum install -y mongodb-org
sudo chkconfig mongod off
munininstallrhel
}

mongoinstallrhel26() {
sudo \rm /etc/yum.repos.d/mongodb.repo
yum list installed | grep mongo | awk '{ print $1 }' | xargs yum remove -y {};
echo "[mongodb-enterprise-2.6]
name=MongoDB Enterprise 2.6 Repository
baseurl=https://repo.mongodb.com/yum/redhat/6Server/mongodb-enterprise/2.6/x86_64/
gpgcheck=0
enabled=1" | sudo tee -a /etc/yum.repos.d/mongodb.repo
sudo yum install -y mongodb-enterprise
sudo chkconfig mongod off
munininstallrhel
}

mongoinstallrhel24() {
sudo \rm /etc/yum.repos.d/mongodb.repo
yum list installed | grep mongo | awk '{ print $1 }' | xargs yum remove -y {};
echo "[mongodb 2.4]
name=MongoDB Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/
gpgcheck=0
enabled=1" | sudo tee -a /etc/yum.repos.d/mongodb.repo
yum install -y mongo-10gen mongo-10gen --exclude mongodb-org,mongodb-org-server
sudo chkconfig mongod off
munininstallrhel
}

mongoinstalldebian26() {
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
echo 'deb http://downloads-distro.mongodb.org/repo/debian-sysvinit dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
sudo apt-get update
sudo apt-get install -y mongodb-org
service mongod stop
update-rc.d mongod disable
}

mongoinstallubuntu30() {
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
sudo apt-get update
sudo apt-get install -y mongodb-org
service mongod stop
update-rc.d mongod disable
}

mongoinstallubuntu26() {
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
echo "deb http://repo.mongodb.org/apt/ubuntu "$(lsb_release -sc)"/mongodb-org/3.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
service mongod stop
update-rc.d mongod disable
}

disksetup() {
for mydir in $(seq $DISKSTART $DISKEND); do
  mkdir -p /data/$mydir
done
mount -a
for mydir in $(seq $DISKSTART $DISKEND); do
  for xxdir in $(seq $MONGOSTART $MONGOEND); do
    mkdir -p /data/$mydir/$xxdir/db
  done
done
}

amazon_fstabsetup() {
if [ ! -f /etc/fstab.ori ]; then cp /etc/fstab /etc/fstab.ori; fi

for device in `grep cloudconfig /etc/fstab | awk '{print $1}'`; do umount -l ${device}; done
sed -i '/cloudconfig/d' /etc/fstab

cat << EOF >> /etc/fstab
LABEL=disk0    /data/0    auto    noatime    0  2
LABEL=disk1    /data/1    auto    noatime    0  2
LABEL=disk2    /data/2    auto    noatime    0  2
LABEL=disk3    /data/3    auto    noatime    0  2
EOF

cat /etc/fstab
pause 2
mount 
pause 2
}

initdisknoraid() {
#format disks
for f in b c d e; do
  count=0
  DISK=/dev/xvd$f
  if [ -a ${DISK} ]; then
     mkfs.xfs -Ldisk$count ${DISK}
     count=$((count+1))
  fi
done
}

initdiskraid0() {
sudo mdadm --create /dev/md0 --chunk=${MDADM_CHUNK} --level=0 --raid-devices=2 /dev/xvdb /dev/xvdc
sudo mdadm --create /dev/md1 --chunk=${MDADM_CHUNK} --level=0 --raid-devices=2 /dev/xvdd /dev/xvde
sudo mdadm --create /dev/md2 --chunk=${MDADM_CHUNK} --level=0 --raid-devices=2 /dev/xvdf /dev/xvdg
sudo mdadm --create /dev/md3 --chunk=${MDADM_CHUNK} --level=0 --raid-devices=2 /dev/xvdh /dev/xvdi


#format disks
for f in 0 1 2 3; do
  DISK=/dev/md$f
  if [ -b ${DISK} ]; then
    mkfs.xfs -L disk$f ${DISK}
  fi
done
}

mongosetup() {
cat << EOF >> /data/mongodb.pem
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDL8gU/uWEfYaYm
S9bYwEjk+6Icb67o/tIcwLNm/CjeGIIpCprXMq67LM5wB2deLZt4MDokl/0aV8l2
m0c/xVx6JFhLz+cSsQ+czTpZTeiLZKLkzBjuZ1z/n7DunYAtAZ4tvFSRz5zvr199
Ik+ZK1FvfuDhhfkGNhLb0fbRtKjrcj6rojmm9Yb+WElk9kFpMk6xky/KuToIC0LT
I91EnXkQsk5hRx5PFk6zQCaSSsxtgaA/A0daqsLXn9iylyYbUFeCmBYB5DfiJqwY
B6S9u0EZUjNFz/JsAgKvHw2rRCKKICTUl9uytxsaL0aLgfj3vfx8dWoka+3kQX46
i3CMBFZJAgMBAAECggEBAMmsd2JPh+pHXszJ/Bf09WByMRmbm0ROECpcqEtzmVoe
tD+ve/TH6p+vLCj+OUqZIP9V+XkMTz5IhzFhVbCLEuq5nBLD8UW7j6vICiYbc5S8
HJTR+ultjzo8iPM9Dm3zBp9Fd/+EZTVjn7KXRk0519rAhdKd7+YjfLyhQUiYNN41
IworIjLwQhIxn8D8/dUv5rQCnWYLr2nKqRobEgQzGg3j6BkS4x3vjonF7tzalYHG
8APaNIIWp0lw1Zx9DMOvtTgDfduumuA6G7mREKPl+Ks1lC8GmrsgLs8XnT1s6Edh
hefQvIJKhPjeBMBx4gHv0fc0ip2fxJzFHBoypwkrU3ECgYEA9amq7obQb2C10Mls
jR5dr4lMKofPr9c+R0RF+jxHOF70u+Nqvfp6+2QFrvGBtpuYIRZF+b4Gqc2YYGpx
0HhPH7zU4AjqpeXAWZsUmYCHgFPWQtlJdX4PHJLzviSrUpylX49ND9BYeFmXeOTM
FUwryhyoAta2Os7s1r14tfj60d0CgYEA1Ib22oFefxLLaDtK4pV5cqKU+91+p1th
KJ5q/7/XsgyLMAZ7cRqMUht5ntSiSPg1GqvLSA6HP4J8Xh1OryIfvMbKbadcs7ii
XYSvSBF1k6XOfBel/+gym5i0he15oGrmHq2ODxnAUKVlXWaYrgoHWhbfNzSTvykv
eLufFwqHbV0CgYBuvaBPTDiTrK3pQ5OKfeDPq33JQlWuN8JcT/uXlSqpz6xVMmxA
3bQotOsW9Ml7buKCL881iKLqUsLY28MYrdNFRFNV9s8IH+y4t/7uP5FVmPViRx8l
NsFLKTd1RIRyhijKTgf4E/x9rC1rEwCorSCkSIy4Ut/s3LDJELpklatDhQKBgQC/
rCFCG97/uBGfJap6A9kOXDcFmFO72BweKBHUKk78E3gMjiwSa6EWBBWB+7+JE+HA
9iNWD1RHIQXNU509Mgdxl8/FaWWf6Or2cM4sryJdUPKS1DkwPVg3IFffWbeRyBdW
n6w5Tj41/ZUX0YntnLnYtDwIa/C8PQbFWmE2xJYzOQKBgENrFdfYhBzWYO4wmPFo
lkTOOnFLB33K2qaM5HgzfpCBabzd2P+uG70YQpGfwHNCynrEbyX/nRSORCNvf/OF
qb/lzUex4fXI34cR6/cZJuuwslgfUUQsgrj3K4+tdu9g+KF9UclbndCR5SNiZQNb
9pGrnbkGF+unugiW7uEUIPuP
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
MIIDVzCCAj+gAwIBAgIJAMT176tO2sIcMA0GCSqGSIb3DQEBCwUAMEIxCzAJBgNV
BAYTAlhYMRUwEwYDVQQHDAxEZWZhdWx0IENpdHkxHDAaBgNVBAoME0RlZmF1bHQg
Q29tcGFueSBMdGQwHhcNMTQwODAzMDEyNzI4WhcNMjQwNzMxMDEyNzI4WjBCMQsw
CQYDVQQGEwJYWDEVMBMGA1UEBwwMRGVmYXVsdCBDaXR5MRwwGgYDVQQKDBNEZWZh
dWx0IENvbXBhbnkgTHRkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
y/IFP7lhH2GmJkvW2MBI5PuiHG+u6P7SHMCzZvwo3hiCKQqa1zKuuyzOcAdnXi2b
eDA6JJf9GlfJdptHP8VceiRYS8/nErEPnM06WU3oi2Si5MwY7mdc/5+w7p2ALQGe
LbxUkc+c769ffSJPmStRb37g4YX5BjYS29H20bSo63I+q6I5pvWG/lhJZPZBaTJO
sZMvyrk6CAtC0yPdRJ15ELJOYUceTxZOs0AmkkrMbYGgPwNHWqrC15/YspcmG1BX
gpgWAeQ34iasGAekvbtBGVIzRc/ybAICrx8Nq0QiiiAk1JfbsrcbGi9Gi4H49738
fHVqJGvt5EF+OotwjARWSQIDAQABo1AwTjAdBgNVHQ4EFgQUDFzQWVVWhypWlqFW
A06I1FwiLnUwHwYDVR0jBBgwFoAUDFzQWVVWhypWlqFWA06I1FwiLnUwDAYDVR0T
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAjVvTbVLx4ADU1vXd3VVzlihrkuqX
urNMeU5jDZAixIXo0mWlePmW+ydFcWtEMh8kbrZvHKVVoFbsZmQg4Kbssda5M8eD
mZBuhXA3GSnadJyL9uKQ7LOOJgbKnhUbrCZ299lecC98OmQqnO72+HiX9LG1RyDu
lQ2A3WThDvGVu20Lib1b3egQjuQa1Fw/YljITx8m1m+Fq9vhMTrCPoNbTF5VBVZ4
Cj68xegPPOb/MllCAvK1ODOehDSjejuKXOmeg+w4PEHNasEXpTF6y/fST60kNXyU
kJ/fII7AaJfHwlAaoAc8IvDHqyMzpGX6pg3FfYD52ttPoewtBlWQbkAXcQ==
-----END CERTIFICATE-----
EOF

cat << EOF > /data/mongod.conf
storageEngine=wiredTiger
wiredTigerCacheSizeGB=$WT_CACHESIZE
wiredTigerDirectoryForIndexes=true
logpath=/data/DISK/MONGO/mongod.log
logappend=true
fork=true
port=370DISKMONGO
dbpath=/data/DISK/MONGO/db
pidfilepath=/data/DISK/MONGO/mongod.pid
#bind_ip=
# nojournal=true
#cpu=true
#auth=true
#verbose=true
#objcheck=true
#quota=true
# Set oplogging level where n is
#   0=off (default)
#   1=W
#   2=R
#   3=both
#   7=W+some reads
#diaglog=0
#nohints=true
nohttpinterface=true
replSet=rsDISKMONGO
#noscripting=true
# Turns off table scans.  Any query that would do a table scan fails.
#notablescan=true
#sslMode=requireSSL
#sslPEMKeyFile=/data/mongodb.pem
EOF

cat << EOF > /data/mongos.conf
logpath=/data/DISK/MONGO/mongos.log
logappend=true
fork=true
port=27017
configdb=10.70.70.10:37099
pidfilepath=/data/DISK/MONGO/mongos.pid
noAutoSplit=true
#bind_ip=
#auth=true
nohttpinterface=true
#sslMode=requireSSL
#sslPEMKeyFile=/data/mongodb.pem
EOF
}

mongoconfigs() {
MONGOPATH=/data/9/0
mkdir -p $MONGOPATH
\cp -f /data/mongos.conf $MONGOPATH
sed -i 's/DISK/'9'/' $MONGOPATH/mongos.conf
sed -i 's/MONGO/'0'/' $MONGOPATH/mongos.conf

MONGOPATH=/data/9/9
mkdir -p $MONGOPATH/db
\cp -f /data/mongod.conf $MONGOPATH
sed -i 's/DISK/'9'/' $MONGOPATH/mongod.conf
sed -i 's/MONGO/'9'/' $MONGOPATH/mongod.conf
sed -i 's/^replSet/#replSet/' $MONGOPATH/mongod.conf

for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    MONGOPATH=/data/$d/$m
    \cp -f /data/mongod.conf $MONGOPATH/mongod.conf
    sed -i 's/DISK/'$d'/' $MONGOPATH/mongod.conf
    sed -i 's/MONGO/'$m'/' $MONGOPATH/mongod.conf
  done
done

#just in case, currently all ran as root
chown -R mongod:mongod /data
}

#Contains machine specific settings, this function will need to be modified by different setups
mongoaddshards() {
#
# WARNING THIS CANNOT BE RUN IN PARALLEL
#
HOST=`hostname`
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
	MEMBER=10.70.70.1$d:$MONGO_PORT_PREFIX$d$m
	echo "rs.initiate({_id:\"rs$d$m\", members:[{_id:0,host:\"$MEMBER\"}]})" | mongo --host $HOST --port $MONGO_PORT_PREFIX$d$m
    echo "sh.addShard(\"rs$d$m/10.70.70.1$d:$MONGO_PORT_PREFIX$d$m\")" | mongo --host $MONGOSHOST --port $MONGOSPORT
  done
done
}

mongobarestart() {
for d in /data/*/*; do
  [ -f $d/mongod.conf ] && ${MONGOD_EXECUTABLE} -f $d/mongod.conf
done
#just in case pkill mongo was used
[ -f /etc/init.d/mongodb-mms-monitoring-agent ] && /etc/init.d/mongodb-mms-monitoring-agent start
sleep 1
# must be seperate so config servers come up first
for d in /data/*/*; do
  [ -f $d/mongos.conf ] && ${MONGOS_EXECUTABLE} -f $d/mongos.conf
done
}

mongostart() {
for d in /data/*/*; do
  [ -f $d/mongod.conf ] && numactl --interleave=all ${MONGOD_EXECUTABLE} -f $d/mongod.conf
done
#just in case pkill mongo was used
[ -f /etc/init.d/mongodb-mms-monitoring-agent ] && /etc/init.d/mongodb-mms-monitoring-agent start
sleep 1
 must be seperate so config servers come up first
for d in /data/*/*; do
  [ -f $d/mongos.conf ] && ${MONGOS_EXECUTABLE} -f $d/mongos.conf
done
}


mongocgroupstart() {
count=0
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    node=$((count%NUMANODECOUNT))
    if [ -f /data/$d/$m/mongod.conf ]; then
	cgcreate -a mongod:mongod -t mongod:mongod -g memory:mongo$d$m
	echo ${CGROUP_MONGOD_RAM} > ${CGPREFIX}/cgroup/memory/mongo$d$m/memory.limit_in_bytes
	cgexec -g memory:mongo$d$m numactl --cpunodebind=$node --localalloc ${MONGOD_EXECUTABLE} -f /data/$d/$m/mongod.conf
    fi
    count=$((count+1))
  done
done
#start any config servers, should error out on already started servers
for d in /data/9/*; do
  [ -f $d/mongod.conf ] && numactl --interleave=all ${MONGOD_EXECUTABLE} -f $d/mongod.conf
done
#just in case pkill mongo was used
[ -f /etc/init.d/mongodb-mms-monitoring-agent ] && /etc/init.d/mongodb-mms-monitoring-agent start
sleep 1
# must be seperate so config servers come up first
for d in /data/*/*; do
  [ -f $d/mongos.conf ] && ${MONGOS_EXECUTABLE} -f $d/mongos.conf
done
}

mongostartnuma() {
count=0
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    node=$((count%NUMANODECOUNT))
    [ -f /data/$d/$m/mongod.conf ] && numactl --cpunodebind=$node --localalloc ${MONGOD_EXECUTABLE} -f /data/$d/$m/mongod.conf
    count=$((count+1))
  done
done
#start any config servers, should error out on already started servers
for d in /data/9/*; do
  [ -f $d/mongod.conf ] && numactl --interleave=all ${MONGOD_EXECUTABLE} -f $d/mongod.conf
done
#just in case pkill mongo was used
[ -f /etc/init.d/mongodb-mms-monitoring-agent ] && /etc/init.d/mongodb-mms-monitoring-agent start
sleep 1
# must be seperate so config servers come up first
for d in /data/*/*; do
  [ -f $d/mongos.conf ] && ${MONGOS_EXECUTABLE} -f $d/mongos.conf
done
}


stuff() {
cat << EOF >> ~/file
var dbname="intagg"
var nsname="intagg.rollup"
sh.setBalancerState(false)
sh.enableSharding(dbname)
use admin
db.runCommand({"shardCollection":nsname, key:{org:"hashed"}, numInitialChunks: 96})
#the below agg should be empty assuming 2 chunks per shard on the presplit, DO NOT FILTER NAMESPACES (all of these should be the same count at ALL times..)
use config
db.chunks.aggregate({$group: {_id: { ns: "$ns", shard: "$shard" }, count: {$sum : 1}}}, {$match: {count: {$ne: 2}}})
#$ne should be equal to count of ns
db.chunks.aggregate({$group: {_id: { max: "$max" }, count: {$sum : 1}}}, {$match: {count: {$ne: 2}}})
EOF
}


clean() {
#
# REMOVE ALL DATA
#
pkill mongo
for d in /data/*/*/; do 
  if [ -d $d ]; then 
    rm -rf $d/db/*
  fi
done
}

dump() {
#
# Export all to json
#
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    mongodump -d $DATABASE -c $COLLECTION --port $MONGO_PORT_PREFIX$d$m -o - > /data/$d/$m/dump.bson &
  done
done
}

exportjson() {
#
# Export all to json
#
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
     mongoexport -d $DATABASE -c $COLLECTION --port $MONGO_PORT_PREFIX$d$m -o /data/$d/$m/export.json &
  done
done
}

tarjson() {
#
# tar all files
#
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    tar cjf /data/$d/$m/export.json.tar.bz2 /data/$d/$m/export.json &
    sleep 1
  done
done
}

toloader() {
#
# Move files to loader machine
#
MACHINE=`cat ~/id`
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    scp /data/$d/$m/dump/$DATABASE/$COLLECTION.bson l1:/data/dump/dump$MACHINE$d$m.bson &
    sleep 1
  done
done
}

toloaderjson() {
#
# Move files to loader machine
#
MACHINE=`cat ~/id`
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    scp /data/$d/$m/export.json l1:/data/json/machine$MACHINE$d$m.json &
    sleep 1
  done
done
}

runrollup() {
#
# Run script on endpoint individually
#
scp l1:payload/weeklyrollup.js ~/payload/
for d in $(seq $DISKSTART $DISKEND); do
  for m in $(seq $MONGOSTART $MONGOEND); do
    rm -f /data/$d/$m/time.txt
    { time cat ~/payload/weeklyrollup.js | mongo --port $MONGO_PORT_PREFIX$d$m; } 2> /data/$d/$m/time.txt &
    sleep 1
  done
done
}

agg1() {
#
# Run a stage1 aggregation
#
for host in "${HOSTS[@]}"; do
  for d in $(seq $DISKSTART $DISKEND); do
    for m in $(seq $MONGOSTART $MONGOEND); do
    ~/test1 -a ~/payload/aggpreagg.js -u $host:27017 -r hub.transactions -w intagg.rollup &
    done
  done
done
}

aggnext() {
#
# Run the composit aggregations
# Assumes mongoS on the runner
#
for job in "${WEEKLYJOBS[@]}"; do
~/test1 -a ~/payload/$job -u localhost:27017 -r intagg.rollup -w skip &
done
}

installmonitor() {
#To check munin node:
#yum -y install telnet
#telnet localhost 4949

#install the MMS Agent
curl -OL https://mms.mongodb.com/download/agent/monitoring/mongodb-mms-monitoring-agent-2.4.0.101-1.x86_64.rpm
sudo rpm -U mongodb-mms-monitoring-agent-2.4.0.101-1.x86_64.rpm
sed -i 's/^mmsApiKey=.*/mmsApiKey=1ed91a1f84ec126d4aa8dbbd010e4281/' /etc/mongodb-mms/monitoring-agent.config
/etc/init.d/mongodb-mms-monitoring-agent start
#sudo nano /etc/mongodb-mms/monitoring-agent.config
}


case $USERCMD in
	start) mongostart
	;;

	startbare) mongobarestart
	;;

	startnuma) mongostartnuma
	;;

	stop) pkill mongod; pkill mongos
	;;

	dodump) dump
	;;

	doexport)exportjson
	;;

	dotar)tarjson
	;;

	doloader)toloader
	;;

	doloaderjson)toloaderjson
	;;

	onstart)
		#initdiskraid0
		disksetup
		mongosetup
		mongoconfigs
	;;

	install)
		installmongo
		installos
		#amazon_fstabsetup
	;;

	addshards) mongoaddshards
	;;

	doclean) clean
	;;
	
	"")echo No user command given
	;;

	*)echo \"$USERCMD\" is not a recognized command
	;;
esac
