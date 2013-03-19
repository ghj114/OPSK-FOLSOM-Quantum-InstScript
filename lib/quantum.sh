#!/bin/bash

set -ex
#set -n
source settings

#apt-get update
#apt-get upgrade

apt-get install openvswitch-switch openvswitch-datapath-dkms

# create bridge interfaces
ovs-vsctl add-br br-int
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex ${PUBLIC_NIC}
ip link set up br-ex
#ovs-vsctl add-br br-eth1
#ovs-vsctl add-port br-eth1 ${DATA_NIC}

apt-get install -y mysql-client
apt-get install -y python-keystone python-keystoneclient
apt-get install quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent vlan bridge-utils

mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS quantum;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE quantum;'
echo "GRANT ALL ON quantum.* TO 'quantum'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

# set configuration files for quantum
# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g"  ./conf/quantum/api-paste.ini.tmpl > ./conf/quantum/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/api-paste.ini

# l3_agent.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" ./conf/quantum/l3_agent.ini.tmpl > ./conf/quantum/l3_agent.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/l3_agent.ini
sed -e "s,%CONTROLLER_IP%,$CONTROLLER_IP,g" -i ./conf/quantum/l3_agent.ini

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
cp ./conf/quantum/api-paste.ini ./conf/quantum/l3_agent.ini ./conf/quantum/quantum.conf /etc/quantum/
cp ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini /etc/quantum/plugins/openvswitch
rm -f ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf
rm -f ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini 
chown -R quantum. /etc/quantum
chmod 644 /etc/quantum/quantum.conf

# restart processes
service quantum-plugin-openvswitch-agent restart
service quantum-dhcp-agent restart
service quantum-l3-agent restart

# create network via quantum
# --------------------------------------------------------------------------------------
SERVICE_TOKEN=${SERVICE_TOKEN:-ADMIN} #echo $SERVICE_TOKEN
SERVICE_ENDPOINT=${SERVICE_ENDPOINT:-http://localhost:35357/v2.0} #echo $SERVICE_ENDPOINT
export SERVICE_TOKEN=$SERVICE_TOKEN
export SERVICE_ENDPOINT=$SERVICE_ENDPOINT #export | grep SERVICE
export OS_TENANT_NAME=$SERVICE_TENANT_NAME
export OS_USERNAME=quantum
export OS_PASSWORD=$SERVICE_PASSWORD
export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"

function get_id () {
    echo `$@ | awk '/ id / { print $4 }'`
}

# Create the Tenant private network :
create_net() {
    local tenant_name="$1"
    local tenant_network_name="$2"
    local prov_router_name="$3"
    local fixed_range="$4"
    local network_gateway="$5"
    local tenant_id=$(keystone tenant-list | grep " $tenant_name " | awk '{print $2}')

    tenant_net_id=$(get_id quantum net-create --tenant_id $tenant_id $tenant_network_name --provider:network_type gre --provider:segmentation_id 1)
    tenant_subnet_id=$(get_id quantum subnet-create --tenant_id $tenant_id --ip_version 4 $tenant_net_id $fixed_range --gateway $network_gateway --dns_nameservers list=true 8.8.8.8)
    prov_router_id=$(get_id quantum router-create --tenant_id $tenant_id $prov_router_name)
    quantum router-interface-add $prov_router_id $tenant_subnet_id
}

# Create External Network :
create_ext_net() {
    local ext_net_name="$1"
    local ext_net_cidr="$2"
    local ext_net_gateway="$4"
    local pool_floating_start="$5"
    local pool_floating_end="$6"

    ext_net_id=$(get_id quantum net-create $ext_net_name -- --router:external=True --provider:network_type gre --provider:segmentation_id 2)
    quantum subnet-create --ip_version 4 --allocation-pool start=$pool_floating_start,end=$pool_floating_end \
    --gateway $ext_net_gateway $ext_net_id $ext_net_cidr -- --enable_dhcp=False
}

# Connect the Tenant Virtual Router to External Network :
connect_providerrouter_to_externalnetwork() {
    local prov_router_name="$1"
    local ext_net_name="$2"

    router_id=$(get_id quantum router-show $prov_router_name)
    ext_net_id=$(get_id quantum net-show $ext_net_name)
    quantum router-gateway-set $router_id $ext_net_id
}

### Private Network #######
TENANT_NAME="demo"             # The tenant this network is created for
TENANT_NETWORK_NAME="demo-net" # The Quantum-internal network name
FIXED_RANGE="10.5.5.0/24"	# The IP range for the private tenant network
NETWORK_GATEWAY="10.5.5.1"
### Public Network ###########################################
# Provider Router Information - what name should 
# this provider have in Quantum?
PROV_ROUTER_NAME="provider-router"

# Name of External Network (Don't change it!)
EXT_NET_NAME="ext_net"

# External Network addressing - our official 
# Internet IP address space
EXT_NET_CIDR="10.1.199.0/24"
EXT_NET_LEN=${EXT_NET_CIDR#*/}

# External bridge that we have configured 
# into l3_agent.ini (Don't change it!)
EXT_NET_BRIDGE=br-ex

# IP of external bridge (br-ex) - this node's 
# IP in our official Internet IP address space:
EXT_GW_IP="10.1.199.60"

# IP of the Public Network Gateway - The 
# default GW in our official Internet IP address space:
EXT_NET_GATEWAY="10.1.199.1"

# Floating IP range
POOL_FLOATING_START="10.1.199.145"	# First public IP to be used for VMs
POOL_FLOATING_END="10.1.199.150"	# Last public IP to be used for VMs 
#create_net $TENANT_NAME $TENANT_NETWORK_NAME $PROV_ROUTER_NAME $FIXED_RANGE $NETWORK_GATEWAY
#create_ext_net $EXT_NET_NAME $EXT_NET_CIDR $EXT_NET_BRIDGE $EXT_NET_GATEWAY $POOL_FLOATING_START $POOL_FLOATING_END
#connect_providerrouter_to_externalnetwork $PROV_ROUTER_NAME $EXT_NET_NAME

# Configure br-ex to reach public network :
#ip addr flush dev $EXT_NET_BRIDGE
#ip addr add $EXT_GW_IP/$EXT_NET_LEN dev $EXT_NET_BRIDGE
#ip link set $EXT_NET_BRIDGE up


#function get_field() {
#    while read data; do
#        if [ "$1" -lt 0 ]; then
#            field="(\$(NF$1))"
#        else
#            field="\$$(($1 + 1))"
#        fi
#        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
#    done
#}
#
#if [[ "$NETWORK_TYPE" = "gre" ]]; then
#    # create internal network
#    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
#    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net | grep ' id ' | get_field 2)
#    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
#    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
#    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-admin | grep ' id ' | get_field 2)
#    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
#    # create external network
#    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
#    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
#    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
#elif [[ "$NETWORK_TYPE" = "vlan" ]]; then
#   # create internal network
#    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
#    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net --provider:network_type vlan --provider:physical_network physnet1 --provider:segmentation_id 1024| grep ' id ' | get_field 2)
#    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
#    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
#    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-admin | grep ' id ' | get_field 2)
#    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
#    # create external network
#    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
#    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
#    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
#else
#    echo "network type : gre, vlan"
#    echo "no such parameter of network type"
#    exit 1
#fi

echo "network node install over!"
sleep 1
