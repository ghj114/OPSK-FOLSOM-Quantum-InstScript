#!/bin/bash

set -ex
source settings

#apt-get update
#apt-get upgrade
apt-get install -y python-mysqldb mysql-client curl
apt-get install -y python-prettytable
apt-get install -y python-keystone python-keystoneclient
apt-get install -y glance glance-api glance-common glance-registry python-glance python-glanceclient
rm -f /var/lib/glance/glance.sqlite

# Glance Setup
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS glance;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE glance CHARACTER SET utf8;'
echo "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h $MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

# glance-api.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_GLANCE_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/glance/glance-api.conf.tmpl > ./conf/glance/glance-api.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/glance/glance-api.conf

# glance-registry.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_GLANCE_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/glance/glance-registry.conf.tmpl > ./conf/glance/glance-registry.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/glance/glance-registry.conf

cp ./conf/glance/glance-api.conf ./conf/glance/glance-registry.conf /etc/glance/
rm -f ./conf/glance/glance-api.conf ./conf/glance/glance-registry.conf 

chown glance:glance /etc/glance/glance-api.conf
chown glance:glance /etc/glance/glance-registry.conf

service glance-api restart
service glance-registry restart

#glance-manage version_control 0
glance-manage db_sync

#service glance-api restart
#service glance-registry restart

#./glance-upload-ttylinux.sh
#./glance-upload-oneiric.sh
#./glance-upload-loader.sh
#./glance-upload-lucid-loader.sh

echo "glance install over!"
sleep 1

