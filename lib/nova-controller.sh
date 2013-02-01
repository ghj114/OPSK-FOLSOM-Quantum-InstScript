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
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" ./conf/nova/api-paste.ini.tmpl > ./conf/nova/api-paste.ini

# nova.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_NOVA_PASS%,$MYSQL_SERVICE_PASS,g" -e "s,%CONTROLLER_IP%,$CONTROLLER_IP,g" -e "s,%CONTROLLER_IP_PUB%,$CONTROLLER_IP_PUB,g" ./conf/nova/nova.conf.tmpl > ./conf/nova/nova.conf
sed -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g" -e "s,%GLANCE_IP%,$GLANCE_IP,g" -e "s,%FIXED_RANGE%,$FIXED_RANGE,g" -e "s,%COMPUTE_IP%,$COMPUTE_IP,g" -i ./conf/nova/nova.conf
sed -e "s,%PUBLIC_INTERFACE%,$PUBLIC_INTERFACE,g" -e "s,%DEF_FLOATING_P%,$DEF_FLOATING_P,g" -e "s,%MULTI_HOST%,$MULTI_HOST,g" -i ./conf/nova/nova.conf

if [ $MULTI_HOST = 'False' ]; then
    sed -e "s,%NETWORK_HOST%,$CONTROLLER_IP,g" -i ./conf/nova/nova.conf
else
    sed -e "s,%NETWORK_HOST%,$MYPRI_IP,g" -i ./conf/nova/nova.conf
fi 

if [ $NETWORK_TYPE = 'VLAN' ];then
    sed -e "s,%NETWORK_TYPE%,nova.network.manager.VlanManager,g" -i ./conf/nova/nova.conf
elif [ $NETWORK_TYPE = 'FLATDHCP' ];then
    sed -e "s,%NETWORK_TYPE%,nova.network.manager.FlatDHCPManager,g" -i ./conf/nova/nova.conf
else
    echo "ERROR:network type is not expecting"; exit -1;
fi

cp ./conf/nova/nova.conf ./conf/nova/api-paste.ini /etc/nova/
rm -f ./conf/nova/nova.conf ./conf/nova/api-paste.ini

#chown nova:nova /etc/nova/nova.conf /etc/nova/api-paste.ini
chown -R nova. /etc/nova
chmod 644 /etc/nova/nova.conf

service nova-api restart
nova-manage db sync

for a in nova-api nova-scheduler nova-cert nova-consoleauth; do service "$a" restart; done 
if [ $MULTI_HOST = 'False' ]; then service nova-network restart;fi

#nova-manage network create private $FIXED_RANGE  --num_networks $FIXED_RANGE_NETWORK_COUNT --network_size $FIXED_RANGE_NETWORK_SIZE  --multi_host T --bridge=br100 --bridge_interface eth1 
#nova-manage network create --label vlan1 --fixed_range_v4 10.0.1.0/24 --num_networks 1 --network_size 256 --vlan 1

#create network
#echo ${VLAN_ARRAYS[@]}; echo ${#VLAN_ARRAYS[@]}; echo ${#VLANID_ARRAYS[@]}
if [ $NETWORK_TYPE = "VLAN" ] 
then
    if [ ${#VLAN_ARRAYS[@]} != ${#VLANID_ARRAYS[@]} ]; then echo "ERROR:The arrays of VLAN and VLANID!"; exit -1; fi
    #for i in "${VLAN_ARRAY[@]}"; do echo $i | cut -d . -f 3; done
    for (( i=0,j=0; i<${#VLAN_ARRAYS[@]} && j<${#VLANID_ARRAYS[@]} ;i++,j++ )); do
        #lable='vlan'${VLANID_ARRAYS[$i]};  vlanid=${VLANID_ARRAYS[$j]}; echo $lable $vlanid
	nova-manage network create --label='vlan'${VLANID_ARRAYS[$i]} --fixed_range_v4=${VLAN_ARRAYS[$i]} \
                                   --num_networks=$FIXED_RANGE_NETWORK_COUNT --network_size=$FIXED_RANGE_NETWORK_SIZE --vlan=${VLANID_ARRAYS[$i]} \
                                   --bridge_interface=$BRIDGE_INTERFACE
    done 
elif [ $NETWORK_TYPE = "FLATDHCP" ] 
then
    nova-manage network create --label=private --fixed_range_v4=$FIXED_RANGE  --num_networks=$FIXED_RANGE_NETWORK_COUNT --dns1=8.8.8.8 --dns2=8.8.4.4 \
                               --network_size=$FIXED_RANGE_NETWORK_SIZE  --multi_host=$MULTI_HOST --bridge=br100 --bridge_interface=$BRIDGE_INTERFACE
else
    echo "ERROR:network type is not expecting"; exit -1;
fi

nova-manage floating create --ip_range=$FLOATING_RANGE --pool=$DEF_FLOATING_P --interface=$PUBLIC_INTERFACE

echo "=============" 
for a in nova-api nova-scheduler nova-cert nova-consoleauth; do service "$a" status; done 
if [ $MULTI_HOST = 'False' ]; then service nova-network status;fi

echo "nova-controller install over!"
sleep 1
