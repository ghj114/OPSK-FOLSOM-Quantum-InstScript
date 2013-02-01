#!/bin/bash

set -ex

source settings

echo mysql-server-5.5 mysql-server/root_password password ${MYSQL_ROOT_PASS} | debconf-set-selections
echo mysql-server-5.5 mysql-server/root_password_again password ${MYSQL_ROOT_PASS} | debconf-set-selections
apt-get install -y mysql-server python-mysqldb
sed -i -e 's/127.0.0.1/0.0.0.0/' /etc/mysql/my.cnf
service mysql restart

# mysql
echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASS}' WITH GRANT OPTION; FLUSH PRIVILEGES;" \
      | mysql -u root -p$MYSQL_ROOT_PASS

echo "mysql install over!"
sleep 1
