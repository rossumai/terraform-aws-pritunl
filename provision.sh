#!/bin/bash -xe
# exec > >(tee /var/log/pritunl-install-data.log|logger -t user-data -s 2>/dev/console) 2>&1yes

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aws/bin:/root/bin
echo "Pritunl Installing"
yum update -y

echo "* hard nofile 64000" >> /etc/security/limits.conf
echo "* soft nofile 64000" >> /etc/security/limits.conf
echo "root hard nofile 64000" >> /etc/security/limits.conf
echo "root soft nofile 64000" >> /etc/security/limits.conf

tee /etc/yum.repos.d/mongodb-org-4.4.repo << EOF
[mongodb-org-4.4]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.4/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.4.asc
EOF

tee /etc/yum.repos.d/pritunl.repo << EOF
[pritunl]
name=Pritunl Repository
baseurl=https://repo.pritunl.com/stable/yum/oraclelinux/8/
gpgcheck=1
enabled=1
EOF


systemctl disable firewalld
systemctl stop firewalld

# TODO: check if selinux support really works
# sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
# sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
# setenforce 0

cd /tmp
cat > mongodb_cgroup_memory.te <<EOF
module mongodb_cgroup_memory 1.0;

require {
    type cgroup_t;
    type mongod_t;
    class dir search;
    class file { getattr open read };
}

#============= mongod_t ==============
allow mongod_t cgroup_t:dir search;
allow mongod_t cgroup_t:file { getattr open read };
EOF
checkmodule -M -m -o mongodb_cgroup_memory.mod mongodb_cgroup_memory.te
semodule_package -o mongodb_cgroup_memory.pp -m mongodb_cgroup_memory.mod
semodule -i mongodb_cgroup_memory.pp

cat > mongodb_proc_net.te <<EOF
module mongodb_proc_net 1.0;

require {
    type proc_net_t;
    type mongod_t;
    class file { open read };
}

#============= mongod_t ==============
allow mongod_t proc_net_t:file { open read };
EOF

checkmodule -M -m -o mongodb_proc_net.mod mongodb_proc_net.te
semodule_package -o mongodb_proc_net.pp -m mongodb_proc_net.mod
semodule -i mongodb_proc_net.pp

yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
rpm -i https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
gpg --armor --export 7568D9BB55FF9E5287D586017AE645C0CF8E292A > key.tmp; rpm --import key.tmp; rm -f key.tmp
yum -y install pritunl mongodb-org wireguard-tools
/usr/lib/pritunl/bin/python -m pip install 'mongo[srv]' dnspython

# systemctl start mongod pritunl

cat <<EOF >/etc/sysconfig/iptables
# sample configuration for iptables service
# you can edit this manually or use system-config-firewall
# please do not ask us to add additional ports/services to this default configuration
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
EOF

echo -e 'server time1.google.com iburst\nserver time2.google.com iburst\nserver time3.google.com iburst\nserver time4.google.com iburst' >> /etc/chrony.conf

systemctl enable mongod pritunl chronyd
# thing below basically uses all resources - eats memory and makes VPN UNSTABLE!
systemctl disable dnf-makecache.timer

cat <<EOF > /etc/logrotate.d/pritunl
/var/log/mongodb/*.log {
  daily
  missingok
  rotate 60
  compress
  delaycompress
  copytruncate
  notifempty
}
EOF

cat <<EOF > /etc/pritunl.conf
{
    "debug": false,
    "bind_addr": "0.0.0.0",
    "port": 443,
    "log_path": "/var/log/pritunl.log",
    "temp_path": "/tmp/pritunl_%r",
    "local_address_interface": "auto",
    "mongodb_uri": "mongodb://localhost:27017/pritunl"
}
EOF

reboot
