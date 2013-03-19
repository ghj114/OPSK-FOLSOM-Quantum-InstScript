#!/bin/bash

set -ex
#set -n
source settings

#apt-get update
#apt-get upgrade

apt-get install -y ntp
sed -i 's/server ntp.ubuntu.com/server ntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
service ntp restart

#nova-compute-kvm vlan bridge-utils nova-network 
apt-get install -y python-mysqldb mysql-client curl
apt-get install -y nova-api nova-scheduler nova-common nova-cert nova-console 
apt-get install -y novnc nova-novncproxy nova-consoleauth websockify
#apt-get install -y nova-volume

if [ $MULTI_HOST = 'False' ]; then apt-get install -y nova-network;/etc/init.d/networking restart; fi

mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS nova;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE nova;'
echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS
#mysql -h192.168.1.100 -uroot -proot -e 'DROP DATABASE IF EXISTS nova;'
#mysql -h192.168.1.100 -uroot -proot -e 'CREATE DATABASE nova;'
#echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY 'service'; FLUSH PRIVILEGES;" | mysql -h192.168.1.100 -uroot -proot

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" ./conf/nova/api-paste.ini.tmpl > ./conf/nova/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/nova/api-paste.ini
# nova.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_NOVA_PASS%,$MYSQL_SERVICE_PASS,g"  ./conf/nova/nova.conf.tmpl > ./conf/nova/nova.conf
sed -e "s,%CONTROLLER_IP%,$CONTROLLER_IP,g" -e "s,%CONTROLLER_IP_PUB%,$CONTROLLER_IP_PUB,g" -i ./conf/nova/nova.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g"  -i ./conf/nova/nova.conf
sed -e "s,%GLANCE_IP%,$GLANCE_IP,g"  -e "s,%COMPUTE_IP%,$COMPUTE_IP,g" -i ./conf/nova/nova.conf


#if [ $NETWORK_TYPE = 'VLAN' ];then
#    sed -e "s,%NETWORK_TYPE%,nova.network.manager.VlanManager,g" -i ./conf/nova/nova.conf
#elif [ $NETWORK_TYPE = 'FLATDHCP' ];then
#    sed -e "s,%NETWORK_TYPE%,nova.network.manager.FlatDHCPManager,g" -i ./conf/nova/nova.conf
#else
#    echo "ERROR:network type is not expecting"; exit -1;
#fi

cp ./conf/nova/nova.conf ./conf/nova/api-paste.ini /etc/nova/
rm -f ./conf/nova/nova.conf ./conf/nova/api-paste.ini
#chown nova:nova /etc/nova/nova.conf /etc/nova/api-paste.ini
chown -R nova. /etc/nova
chmod 644 /etc/nova/nova.conf

service nova-api restart
nova-manage db sync

for a in nova-api nova-scheduler nova-cert nova-consoleauth; do service "$a" restart; done 

mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS quantum;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE quantum;'
echo "GRANT ALL ON quantum.* TO 'quantum'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

apt-get install -y quantum-server

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g"  ./conf/quantum/api-paste.ini.tmpl > ./conf/quantum/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/api-paste.ini

# quantum.conf.tmpl
sed -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g" ./conf/quantum/quantum.conf.tmpl > ./conf/quantum/quantum.conf

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
cp ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf /etc/quantum/
cp ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini /etc/quantum/plugins/openvswitch
rm -f ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf
rm -f ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini 
#chown nova:nova /etc/nova/nova.conf /etc/nova/api-paste.ini
chown -R quantum. /etc/quantum
chmod 644 /etc/quantum/quantum.conf

service quantum-server restart

echo "nova-controller install over!"
sleep 1
