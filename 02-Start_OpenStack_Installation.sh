#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
tmp="/root/"
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | This script will do:                                                                                                |"
echo " | 1. Management IP Existence Control in '/etc/hosts' File                                                             |"
echo " | 2. MariaDB Server Installation                                                                                      |"
echo " | 3. MariaDB Bind Address Configuration                                                                               |"
echo " | 4. RabbitMQ Installation                                                                                            |"
echo " | 5. RabbitMQ User Configuration                                                                                      |"
echo " | 6. Memcached Service Installation                                                                                   |"
echo " | 7. Memcached Configuration                                                                                          |"
echo " | 8. Etcd Service Installation                                                                                        |"
echo " | 9. Etcd User and Group Configuration                                                                                |"
echo " | 10. Etcd Configuration                                                                                              |"
echo " | 11. Etcd Service File Configuration                                                                                 |"
echo " | 12. Enable Etcd Service                                                                                             |"
echo " | 13. Running MySQL Secure Installation Procedure                                                                     |"
echo " +---------------------------------------------------------------------------------------------------------------------+"
echo


# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi


hostname=`hostname`
#check for hosts and management IP consistency
HOSTS_IP=`more /etc/hosts | grep ${hostname} | awk '{print $1}'`
MGMT_INTERFACE_IP=`ifconfig eth1 | grep "inet addr" | grep -v "127.0.0.1" | awk '{print $2}' | sed 's/addr://g'`
if [ "$HOSTS_IP" != "$MGMT_INTERFACE_IP" ]
then
	while true; do
		read -ep " > IP address of this server is not inserted correctly in /etc/hosts file. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo
					exit 1;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

# print status message
echo " > Installing MariaDB Server..."
while true; do
    read -p " > do you wish to install MariaDB-Server [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'mariadb-server', 'mytop' and 'python-pymysql' packages will be installed. OK?" OK
				apt -y install mariadb-server python-pymysql mytop
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

# print status message
echo " > Bind address configuration..."
Mysql_cnf_file="/etc/mysql/mariadb.conf.d/99-openstack.cnf"
touch $Mysql_cnf_file
echo "[mysqld]" >> $Mysql_cnf_file
echo "bind-address = "$MGMT_INTERFACE_IP >> $Mysql_cnf_file
echo "default-storage-engine = innodb" >> $Mysql_cnf_file
echo "innodb_file_per_table = on" >> $Mysql_cnf_file
echo "max_connections = 4096" >> $Mysql_cnf_file
echo "collation-server = utf8_general_ci" >> $Mysql_cnf_file
echo "character-set-server = utf8" >> $Mysql_cnf_file
echo " > Mysql Service will be restarted..."
service mysql restart
Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

# print status message
echo " > Installing RabbitMQ..."
while true; do
    read -p " > do you wish to install RabbitMQ-Server [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > rabbitmq-server package will be installed. OK?" OK
				apt -y install rabbitmq-server
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

RabbitMQ_Service_Status=`systemctl | grep rabbitmq | grep "active running" | wc -l`
if [ $RabbitMQ_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

# print status message
echo " > RabbitMQ User Configuration..."

read -sp "  > Please enter RabbitMQ User preferred password: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
fi

# Set RabbitMQ User Password
RabbitMQ_User_Password=$password
echo $RabbitMQ_User_Password >> /root/.RabbitMQ_User_Password
/usr/bin/chattr +i /root/.RabbitMQ_User_Password
rabbitmqctl add_user openstack $RabbitMQ_User_Password
rabbitmqctl set_permissions openstack ".*" ".*" ".*"


# print status message
echo " > Installing Memcached Service..."
while true; do
    read -p " > do you wish to install memcached [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'memcached' and 'python-memcached' packages will be installed. OK?" OK
				apt -y install memcached python-memcache
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Memcached_Service_Status=`systemctl | grep memcached | grep "active running" | wc -l`
if [ $Memcached_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

# print status message
echo " > Memcached Configuration..."
Memcached_Config_File="/etc/memcached.conf"
sed -i -r "s/-l 127.0.0.1/-l $MGMT_INTERFACE_IP/g" "$Memcached_Config_File"
Config_OK=`more ${Memcached_Config_File} | grep "${MGMT_INTERFACE_IP}" | wc -l`
if [ $Config_OK -eq 1 ]
then 
	echo "  > Configuration is OK..."
else
	while true; do
		read -p "  > > Configuration is not OK. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi

echo " > Memcached Service will be restarted..."
service memcached restart
Memcached_Service_Status=`systemctl | grep memcached | grep "active running" | wc -l`
if [ $Memcached_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

# print status message
echo " > Installing Etcd Service..."
while true; do
    read -p " > do you wish to install etcd [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'etcd' packages will be installed. OK?" OK
				echo " > Etcd User & Group Configuration..."
				groupadd --system etcd
				useradd --home-dir "/var/lib/etcd" --system --shell /bin/false -g etcd etcd
				mkdir -p /etc/etcd
				chown etcd:etcd /etc/etcd
				mkdir -p /var/lib/etcd
				chown etcd:etcd /var/lib/etcd
				ETCD_VER=v3.2.7
				rm -rf /tmp/etcd && mkdir -p /tmp/etcd
				curl -L https://github.com/coreos/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
				tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd --strip-components=1
				cp /tmp/etcd/etcd /usr/bin/etcd
				cp /tmp/etcd/etcdctl /usr/bin/etcdctl
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

# print status message
echo " > Etcd Configuration..."
mkdir -p /etc/etcd/
Etcd_Config_File="/etc/etcd/etcd.conf.yml"
touch $Etcd_Config_File

echo "name: "$hostname >> $Etcd_Config_File
echo "data-dir: /var/lib/etcd" >> $Etcd_Config_File
echo "initial-cluster-state: 'new'" >> $Etcd_Config_File
echo "initial-cluster-token: 'etcd-cluster-01'" >> $Etcd_Config_File
echo "initial-cluster: "$hostname"=http://"$MGMT_INTERFACE_IP":2380" >> $Etcd_Config_File
echo "initial-advertise-peer-urls: http://"$MGMT_INTERFACE_IP":2380" >> $Etcd_Config_File
echo "advertise-client-urls: http://"$MGMT_INTERFACE_IP":2379" >> $Etcd_Config_File
echo "listen-peer-urls: http://0.0.0.0:2380" >> $Etcd_Config_File
echo "listen-client-urls: http://"$MGMT_INTERFACE_IP":2379" >> $Etcd_Config_File
echo " > "$Etcd_Config_File" is created and configured."

Etcd_Service_File="/lib/systemd/system/etcd.service"
rm -f $Etcd_Service_File
echo '
[Unit]
Description=etcd - highly-available key value store
Documentation=https://github.com/coreos/etcd
Documentation=man:etcd
After=network.target
Wants=network-online.target

[Service]
Environment=DAEMON_ARGS=
Environment=ETCD_NAME=%H
Environment=ETCD_DATA_DIR=/var/lib/etcd/default
EnvironmentFile=-/etc/default/%p
Type=notify
User=etcd
PermissionsStartOnly=true
#ExecStart=/bin/sh -c "GOMAXPROCS=$(nproc) /usr/bin/etcd $DAEMON_ARGS"
ExecStart=/usr/bin/etcd --config-file /etc/etcd/etcd.conf.yml
Restart=on-failure
#RestartSec=10s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
Alias=etcd2.service' >> $Etcd_Service_File
echo " > "$Etcd_Service_File" is configured."

echo " > Etcd Service will be started..."
systemctl enable etcd
systemctl start etcd
Etcd_Service_Status=`systemctl | grep etcd | grep "active running" | wc -l`
if [ $Etcd_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
	while true; do
		read -p "  > Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					break;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi	

echo " > Script Ended"
read -p "  > FINISHED... 'mysql_secure_installation' script will be run. OK?" OK

mysql_secure_installation

fi
