#!/bin/bash

#set -e
source settings

#apt-get update
#apt-get upgrade

echo "time synchronization..."
ntpdate $CONTROLLER_IP  
hwclock -w
echo "59 8 * * * root /usr/sbin/ntpdate $CONTROLLER_IP;hwclock -w" >>/etc/crontab


apt-get install -y kvm libvirt-bin pm-utils

cat << EOF >> /etc/libvirt/qemu.conf
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
    "/dev/rtc", "/dev/hpet","/dev/net/tun",
]
EOF

sed -i '/#listen_tls/s/#listen_tls/listen_tls/; /#listen_tcp/s/#listen_tcp/listen_tcp/; /#auth_tcp/s/#auth_tcp/auth_tcp/; /auth_tcp/s/sasl/none/'  /etc/libvirt/libvirtd.conf
sed -i '/env libvirtd_opts/s/-d/-d -l/' /etc/init/libvirt-bin.conf
sed -i '/libvirtd_opts/s/-d/-d -l/' /etc/default/libvirt-bin

virsh net-destroy default
virsh net-undefine default
service libvirt-bin restart


apt-get install -y openvswitch-switch
service openvswitch-switch restart
ovs-vsctl add-br br-int

apt-get -y install quantum-plugin-openvswitch-agent

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g"  ./conf/quantum/api-paste.ini.tmpl > ./conf/quantum/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/api-paste.ini

# quantum.conf.tmpl
sed -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g" ./conf/quantum/quantum.conf.tmpl > ./conf/quantum/quantum.conf

# ovs_quantum_plugin.ini.gre.tmpl 
if [[ "$NETWORK_TYPE" = "gre" ]]; then
    sed -e "s,%QUANTUM_IP%,$QUANTUM_IP,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini.gre.tmpl > ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
    sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_QUANTUM_PASS%,$MYSQL_SERVICE_PASS,g" -i ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
elif [[ "$NETWORK_TYPE" = "vlan" ]]; then
    sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini.vlan.tmpl > ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
    sed -e "s,%MYSQL_QUANTUM_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
else
    echo "<network_type> must be 'gre' or 'vlan'."
    exit 1
fi
cp  ./conf/quantum/quantum.conf conf/quantum/api-paste.ini /etc/quantum/
cp ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini /etc/quantum/plugins/openvswitch
rm -f ./conf/quantum/quantum.conf conf/quantum/api-paste.ini
rm -f ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
chown -R quantum. /etc/quantum
chmod 644 /etc/quantum/quantum.conf

service quantum-plugin-openvswitch-agent restart


apt-get install -y python-mysqldb mysql-client curl
apt-get install -y nova-compute-kvm
#apt-get install -y nova-compute nova-vncproxy 
#apt-get install -y novnc

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" ./conf/nova/api-paste.ini.tmpl > ./conf/nova/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/nova/api-paste.ini
# nova.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_NOVA_PASS%,$MYSQL_SERVICE_PASS,g"  ./conf/nova/nova.conf.tmpl > ./conf/nova/nova.conf
sed -e "s,%CONTROLLER_IP%,$CONTROLLER_IP,g" -e "s,%CONTROLLER_IP_PUB%,$CONTROLLER_IP_PUB,g" -i ./conf/nova/nova.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g"  -i ./conf/nova/nova.conf
sed -e "s,%GLANCE_IP%,$GLANCE_IP,g"  -e "s,%COMPUTE_IP%,$COMPUTE_IP,g" -i ./conf/nova/nova.conf
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/nova/nova.conf

cp ./conf/nova/nova.conf ./conf/nova/api-paste.ini /etc/nova/
rm -f ./conf/nova/nova.conf ./conf/nova/api-paste.ini
chown -R nova. /etc/nova
chmod 644 /etc/nova/nova.conf

#for a in nova-compute novnc; do service "$a" restart; done 
service nova-compute restart

echo "================"
#for a in nova-compute novnc; do service "$a" status; done 
service nova-compute status

echo "nova-compute install over!"
sleep 1
