#!/bin/bash

#set -e
source settings

#apt-get update
#apt-get upgrade

echo "time synchronization..."
ntpdate $CONTROLLER_IP  
hwclock -w
echo "59 8 * * * root /usr/sbin/ntpdate $CONTROLLER_IP;hwclock -w" >>/etc/crontab

apt-get install -y python-mysqldb mysql-client curl
apt-get install -y nova-compute 
#apt-get install -y nova-compute nova-vncproxy 
#apt-get install -y novnc

if [ $MULTI_HOST = 'True' ]; then apt-get install -y nova-network;/etc/init.d/networking restart;fi

/etc/init.d/networking restart

virsh net-destroy default
virsh net-undefine default
service libvirt-bin restart

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
chown -R nova. /etc/nova
chmod 644 /etc/nova/nova.conf

#for a in nova-compute novnc; do service "$a" restart; done 
service nova-compute restart
if [ $MULTI_HOST = 'True' ]; then service nova-network restart;fi

echo "================"
#for a in nova-compute novnc; do service "$a" status; done 
service nova-compute status
if [ $MULTI_HOST = 'True' ]; then service nova-network status;fi

echo "nova-compute install over!"
sleep 1
