#!/bin/bash

set -ex
#set -n
source settings

#apt-get update
#apt-get upgrade

apt-get install -y  openvswitch-switch openvswitch-datapath-dkms

# create bridge interfaces
ovs-vsctl add-br br-int
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex ${PUBLIC_NIC}
ip link set up br-ex
#ovs-vsctl add-br br-eth1
#ovs-vsctl add-port br-eth1 ${DATA_NIC}

apt-get install -y mysql-client
apt-get install -y quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent vlan bridge-utils

# set configuration files for quantum
# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g"  ./conf/quantum/api-paste.ini.tmpl > ./conf/quantum/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/api-paste.ini

# l3_agent.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" ./conf/quantum/l3_agent.ini.tmpl > ./conf/quantum/l3_agent.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/l3_agent.ini
sed -e "s,%CONTROLLER_IP_PUB%,$CONTROLLER_IP_PUB,g" -i ./conf/quantum/l3_agent.ini

# quantum.conf.tmpl
sed -e "s,%RABBITMQ_IP,$RABBITMQ_IP,g" ./conf/quantum/quantum.conf.tmpl > ./conf/quantum/quantum.conf

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
cp ./conf/quantum/api-paste.ini ./conf/quantum/l3_agent.ini ./conf/quantum/quantum.conf /etc/quantum/
cp ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini /etc/quantum/plugins/openvswitch
rm -f ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf
rm -f ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini 
chown -R quantum. /etc/quantum
chmod 644 /etc/quantum/quantum.conf

# restart processes
restart_service quantum-plugin-openvswitch-agent
restart_service quantum-dhcp-agent
restart_service quantum-l3-agent

# create network via quantum
# --------------------------------------------------------------------------------------
function get_id () {
    echo `$@ | awk '/ id / { print $4 }'`
}
function get_field() {
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}

if [[ "$NETWORK_TYPE" = "gre" ]]; then
    # create internal network
    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net | grep ' id ' | get_field 2)
    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-admin | grep ' id ' | get_field 2)
    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
    # create external network
    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
elif [[ "$NETWORK_TYPE" = "vlan" ]]; then
   # create internal network
    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net --provider:network_type vlan --provider:physical_network physnet1 --provider:segmentation_id 1024| grep ' id ' | get_field 2)
    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-admin | grep ' id ' | get_field 2)
    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
    # create external network
    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
else
    echo "network type : gre, vlan"
    echo "no such parameter of network type"
    exit 1
fi

echo "network node install over!"
sleep 1
