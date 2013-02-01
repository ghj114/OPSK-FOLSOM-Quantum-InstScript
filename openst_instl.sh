#!/bin/bash

set -e

#for var in  all mysql keystone glance controller compute dashboard; do var=false; done
#for var in  all mysql keystone glance controller compute dashboard; do echo $var; done

if [ $# -eq 0 ]; then echo "Usage: openSt_instl.sh mysql keystone ..."; exit -1; fi
while [ $# -gt 0 ]
do
	case $1 in
	-m | --mysql) mysql=true;; -k | --keystone) keystone=true;;
        -r | --rabbit) rabbitmq=true;; -g | --glance) glance=true;;
        -c ) controller=true;; -p | --compute) compute=true;; -d | --dashboard) dashboard=true;;
        -q | --quantum) quantum=true;;
        --controller) mysql=true;keystone=true;glance=true;cinder=true;rabbitmq=true;controller=true;dashboard=true;;
        -a | --all) mysql=true;keystone=true;glance=true;cinder=true;rabbitmq=true;controller=true;compute=true;quantum=true;dashboard=true;;
	    *) echo "unrecognized:$1"; echo "Usage: openSt_instl.sh mysql keystone ..."; exit -1;;
	esac
	shift
done

#echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/folsom main >> /etc/apt/sources.list.d/folsom.list
#apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 5EDB1B62EC4926EA
apt-get -y update
#apt-get -y upgrade 

# mysql
if [ "$mysql" = "true" ]; then ./lib/mysql.sh;fi
# rabbitmq
if [ "$rabbitmq" = "true" ]; then apt-get install -y rabbitmq-server; echo "rabbitmq install over!";sleep 1;fi
# keystone
if [ "$keystone" = "true" ]; then ./lib/keystone.sh;fi
# glance
if [ "$glance" = "true" ]; then ./lib/glance.sh;fi;
# cinder
if [ "$cinder" = "true" ]; then ./lib/cinder.sh;fi;
# controller
if [ "$controller" = "true" ]; then ./lib/nova-controller.sh;fi
# compute
if [ "$compute" = "true" ]; then ./lib/nova-compute.sh;fi
# dashboard
if [ "$dashboard" = "true" ]; then ./lib/dashboard.sh;fi
# network 
if [ "$quantum" = "true" ]; then ./lib/quantum.sh;fi


#all=false mysql=false rabbitmq=false ntp=false keystone=false glance=false controller=false compute=false  dashboard=false
#. settings
#echo "mysql-server-5.1 mysql-server/root_password password $MYSQL_ROOT_PASS" > /tmp/mysql.preseed
#echo "mysql-server-5.1 mysql-server/root_password_again password $MYSQL_ROOT_PASS" >> /tmp/mysql.preseed
#cat /tmp/mysql.preseed | debconf-set-selections
#rm /tmp/mysql.preseed

# ntp
#if [ "$all" = "true" ] || [ "$ntp" = "true" ]; then
#	sed -i 's/server ntp.ubuntu.com/server ntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
#	service ntp restart
#	echo "ntp install over!"	
#	sleep 2
#fi

