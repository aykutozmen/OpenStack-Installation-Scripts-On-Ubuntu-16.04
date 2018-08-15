#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
cd /home/
default_username=$default_hostname
working_directory=`echo $PWD`
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | Before starting step 12 be sure that Controller node can connect to compute node via SSH and compute node's info    |"
echo " | is added to known hosts file.                                                                                       |"
echo " | This script will do:                                                                                                |"
echo " | 1.  Management IP Existence Control in '/etc/hosts' File                                                            |"
echo " | 2.  Create Mysql DB Nova Databases & Users                                                                          |"
echo " | 3.  Create 'nova' User                                                                                              |"
echo " | 4.  Create 'nova' Service Entity                                                                                    |"
echo " | 5.  Create Compute Service API Endpoints                                                                            |"
echo " | 6.  Create 'placement' User                                                                                         |"
echo " | 7.  Create 'placement' Service Entity                                                                               |"
echo " | 8.  Create Placement Service API Endpoints                                                                          |"
echo " | 9.  Install Nova Services                                                                                           |"
echo " | 10. Nova Configuration                                                                                              |"
echo " | 11. Populate Nova Service Databases                                                                                 |"
echo " | 12. Connect & Configure A Compute Node                                                                              |"
echo " |        a. IP & Hostname Control Of Compute Node                                                                     |"
echo " |        b. Input Password Of Compute Node For SSH Connection                                                         |"
echo " |        c. Install 'nova-compute' Package On Compute Node                                                            |"
echo " |        d. Configure 'nova-compute' Service On Compute Node                                                          |"
echo " | 13. Add Compute Node(s) To The Cell Database                                                                        |"
echo " | 14. Show Server Status Summary                                                                                      |"
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
	read -ep " > IP address of this server is not inserted correctly in /etc/hosts file. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				
				break;;
		[Nn]* )
				echo
				exit 1;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
else 
	echo " > IP address of this server is inserted correctly in /etc/hosts file."
fi


# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane
	
# print status message
echo " > Creating Mysql DB Nova Databases & Users..."
read -sp "  > Please enter NOVA_DBPASS preferred password: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	NOVA_DBPASS=$password
fi



Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Mysql Service Status is 'active running'"

SQL_Output=`mysql -u root <<EOF_SQL
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
FLUSH PRIVILEGES;
exit
EOF_SQL`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from mysql.user where User='nova';
exit
EOF_SQL`
Nova_User_Count=`echo $SQL_Output | awk '{print $2}'`
	if [ $Nova_User_Count == 2 ]
	then
		echo "  > 'nova' users created successfully with password '$NOVA_DBPASS'"
	else
		echo "  > 'nova' users not found in mysql database"
		echo "Script Aborted"
		exit 1		
	fi

else
	echo "  > Mysql service status is not 'active running'. please restart the script and try again"
	echo "Script Aborted"
	exit 1
fi	
	
cd /home/${default_username}
if [ -e /home/${default_username}/admin-openrc ]
then
	. admin-openrc
else
	read -p "  > /home/${default_username}/admin-openrc could not be found. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac	
fi	
working_directory="/root/"
# print status message
echo " > Creating OpenStack 'nova' User..."
openstack user create --domain default --password-prompt nova >> ${working_directory}/nova_user
NovaUserEnabled=`more ${working_directory}/nova_user | head -5 | tail -1 | awk '{print $4}'`
NovaUserID=`more ${working_directory}/nova_user | head -6 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$NovaUserID';
exit
EOF_SQL`
SQL_nova_User_Id=`echo $SQL_Output | awk '{print $2}'`


if [ $SQL_nova_User_Id == 1 ] && [ $NovaUserEnabled == "True" ]
then
	echo "  > 'nova' user is created successfully."
	read -p " > NOTE: 'nova' User's Password you entered (NOVA_PASS) will be asked again in the next steps. Please note it. OK?" OK
else
	read -p "  > 'nova' could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/nova_user

openstack role add --project service --user nova admin

# print status message
echo " > Creating 'nova' service entity..."
openstack service create --name nova --description "OpenStack Compute" compute >> ${working_directory}/nova_service
Nova_Service_Enabled=`more ${working_directory}/nova_service | head -5 | tail -1 | awk '{print $4}'`
if [ $Nova_Service_Enabled == "True" ]
then
	echo "  > 'nova' service entity is created successfully."
else
	read -p "  > 'nova' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/nova_service



# print status message
echo " > Creating Compute Service API Endpoints..."
openstack endpoint create --region RegionOne compute public http://${default_hostname}:8774/v2.1 >> ${working_directory}/public_api

Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`


SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url='http://${default_hostname}:8774/v2.1';
exit
EOF_SQL`
SQL_nova_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_nova_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
then
	echo "  > Public endpoint API is created successfully."
else
	read -p "  > Public endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/public_api


openstack endpoint create --region RegionOne compute internal http://${default_hostname}:8774/v2.1 >> ${working_directory}/internal_api

Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url='http://${default_hostname}:8774/v2.1';
exit
EOF_SQL`
SQL_nova_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_nova_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
then
	echo "  > Internal endpoint API is created successfully."
else
	read -p "  > Internal endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/internal_api

openstack endpoint create --region RegionOne compute admin http://${default_hostname}:8774/v2.1 >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url='http://${default_hostname}:8774/v2.1';
exit
EOF_SQL`
SQL_nova_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_nova_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
then
	echo "  > Admin endpoint API is created successfully."
else
	read -p "  > Admin endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/admin_api

# print status message
echo " > Creating OpenStack 'placement' User..."
openstack user create --domain default --password-prompt placement >> ${working_directory}/placement_user
PlacementUserEnabled=`more ${working_directory}/placement_user | head -5 | tail -1 | awk '{print $4}'`
PlacementUserID=`more ${working_directory}/placement_user | head -6 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$PlacementUserID';
exit
EOF_SQL`
SQL_placement_User_Id=`echo $SQL_Output | awk '{print $2}'`


if [ $SQL_placement_User_Id == 1 ] && [ $PlacementUserEnabled == "True" ]
then
	echo "  > 'placement' user is created successfully."
	read -p " > NOTE: 'placement' User's Password you entered (PLACEMENT_PASS) will be asked again in the next steps. Please note it. OK?" OK
else
	read -p "  > 'placement' could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/placement_user

openstack role add --project service --user placement admin

# print status message
echo " > Creating 'placement' service entity..."
openstack service create --name placement --description "Placement API" placement >> ${working_directory}/placement_service
Placement_Service_Enabled=`more ${working_directory}/placement_service | head -5 | tail -1 | awk '{print $4}'`
if [ $Placement_Service_Enabled == "True" ]
then
	echo "  > 'placement' service entity is created successfully."
else
	read -p "  > 'placement' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/placement_service

# print status message
echo " > Creating Placement Service API Endpoints..."
openstack endpoint create --region RegionOne placement public http://${default_hostname}:8778 >> ${working_directory}/public_api

Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url='http://${default_hostname}:8778';
exit
EOF_SQL`
SQL_placement_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_placement_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
then
	echo "  > Public endpoint API is created successfully."
else
	read -p "  > Public endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/public_api

openstack endpoint create --region RegionOne placement internal http://${default_hostname}:8778 >> ${working_directory}/internal_api

Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url='http://${default_hostname}:8778';
exit
EOF_SQL`
SQL_placement_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_placement_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
then
	echo "  > Internal endpoint API is created successfully."
else
	read -p "  > Internal endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/internal_api

openstack endpoint create --region RegionOne placement admin http://${default_hostname}:8778 >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url='http://${default_hostname}:8778';
exit
EOF_SQL`
SQL_placement_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_placement_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
then
	echo "  > Admin endpoint API is created successfully."
else
	read -p "  > Admin endpoint API could not be created successfully. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f ${working_directory}/admin_api

# print status message
echo " > Installing Nova Services..."
while true; do
    read -p " > do you wish to install nova services [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'nova-api' 'nova-conductor' 'nova-consoleauth' 'nova-novncproxy' 'nova-scheduler' 'nova-placement-api' packages will be installed. OK?" OK
				apt -y install nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler nova-placement-api
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Nova_Api_Service_Status=`systemctl | grep "nova-api" | grep "active running" | wc -l`
if [ $Nova_Api_Service_Status -ge 1 ]
then
	echo "  > 'nova-api' Service Status is 'active running'"
else
	read -p "  > 'nova-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	
Nova_Conductor_Service_Status=`systemctl | grep "nova-conductor" | grep "active running" | wc -l`
if [ $Nova_Conductor_Service_Status -ge 1 ]
then
	echo "  > 'nova-conductor' Service Status is 'active running'"
else
	read -p "  > 'nova-conductor' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	

Nova_Consoleauth_Service_Status=`systemctl | grep "nova-api" | grep "active running" | wc -l`
if [ $Nova_Consoleauth_Service_Status -ge 1 ]
then
	echo "  > 'nova-consoleauth' Service Status is 'active running'"
else
	read -p "  > 'nova-consoleauth' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	
Nova_novncproxy_Service_Status=`systemctl | grep "nova-novncproxy" | grep "active running" | wc -l`
if [ $Nova_novncproxy_Service_Status -ge 1 ]
then
	echo "  > 'nova-novncproxy' Service Status is 'active running'"
else
	read -p "  > 'nova-novncproxy' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	
Nova_scheduler_Service_Status=`systemctl | grep "nova-scheduler" | grep "active running" | wc -l`
if [ $Nova_scheduler_Service_Status -ge 1 ]
then
	echo "  > 'nova-scheduler' Service Status is 'active running'"
else
	read -p "  > 'nova-scheduler' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	

Nova_Config_File="/etc/nova/nova.conf" #CONTROLLER
sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/nova\/nova_api.sqlite/connection = mysql+pymysql:\/\/nova:${NOVA_DBPASS}@${default_hostname}\/nova_api/g" "$Nova_Config_File"
sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/nova\/nova.sqlite/connection = mysql+pymysql:\/\/nova:${NOVA_DBPASS}@${default_hostname}\/nova/g" "$Nova_Config_File"
RabbitMQ_Password=`more /root/.RabbitMQ_User_Password`
sed -i -r "s/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@controller/g" "$Nova_Config_File"
sed -i -r "s/^\[api]/\[api]\nauth_strategy = keystone/g" "$Nova_Config_File"

read -sp "  > Please enter nova user's preferred password (NOVA_PASS) that you entered before: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	NOVA_PASS=$password
	echo $NOVA_PASS >> /root/.NOVA_PASS
	chattr +i /root/.NOVA_PASS
fi

sed -i -r "s/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_url = http:\/\/${default_hostname}:5000\/v3\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = service\nusername = nova\npassword = ${NOVA_PASS}\n/g" "$Nova_Config_File"

MGMT_INTERFACE_IP=`ifconfig eth1 | grep "inet addr" | grep -v "127.0.0.1" | awk '{print $2}' | sed 's/addr://g'`
sed -i -r "s/^\[DEFAULT]/\[DEFAULT]\nmy_ip = ${MGMT_INTERFACE_IP}\nuse_neutron = True\nfirewall_driver = nova.virt.firewall.NoopFirewallDriver\n/g" "$Nova_Config_File"
sed -i -r "s/^\[vnc]/[vnc]\nenabled = True\nserver_listen = \$my_ip\nserver_proxyclient_address = \$my_ip\n/g" "$Nova_Config_File"
sed -i -r "s/^\[glance]/\[glance]\napi_servers = http:\/\/${default_hostname}:9292\n/g" "$Nova_Config_File"
sed -i -r "s/^\[oslo_concurrency]/\[oslo_concurrency]\nlock_path = \/var\/lib\/nova\/tmp\n/g" "$Nova_Config_File"
sed -i -r "s/^log_dir = \/var\/log\/nova/#log_dir = \/var\/log\/nova/g" "$Nova_Config_File"

read -sp "  > Please enter placement user's preferred password (PLACEMENT_PASS) that you entered before: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	PLACEMENT_PASS=$password
fi
sed -i -r "s/^os_region_name = openstack/os_region_name = RegionOne\nproject_domain_name = Default\nproject_name = service\nauth_type = password\nuser_domain_name = Default\nauth_url = http:\/\/${default_hostname}:5000\/v3\nusername = placement\npassword = ${PLACEMENT_PASS}\n/g" "$Nova_Config_File"


working_directory=`echo $PWD`
# print status message
echo " > Populate 'nova-api' Service Database..."
while true; do
    read -p " > do you wish to populate 'nova_api' database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "nova-manage api_db sync" nova
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use nova_api;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count -eq 32 ]
				then
					echo "  > 'nova_api' database tables were created successfully."
				else
					read -p "  > 'nova_api' database tables not found or missing. Do you want to continue? [y/n]: " yn
					case $yn in
						[Yy]* ) 
								break;;
						[Nn]* )
								echo "Script Aborted"
								exit 1
								break;;
						* ) 	echo " please answer [y]es or [n]o.";;
					esac
				fi
				
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done	
rm -f $working_directory/tmp_file

# print status message
echo " > Register 'cell0' Database and Create cell1 cell..."
while true; do
    read -p "  > do you wish to register 'cell0' database and create cell1 cell [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
				su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done	
#rm -f $working_directory/tmp_file


# print status message
echo " > Populate 'nova' Service Database..."
while true; do
    read -p " > do you wish to populate 'nova' database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "nova-manage db sync" nova
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use nova;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count_nova=`more $working_directory/tmp_file | tail -1`
				rm -f $working_directory/tmp_file
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use nova_cell0;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count_nova_cell0=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count_nova -eq 110 ] && [ $Table_Count_nova_cell0 -eq 110 ]
				then
					echo "  > 'nova' and 'nova_cell0' database tables were created successfully."
				else
					read -p "  > 'nova' and 'nova_cell0' database tables not found or missing. Do you want to continue? [y/n]: " yn
					case $yn in
						[Yy]* ) 
								break;;
						[Nn]* )
								echo "Script Aborted"
								exit 1
								break;;
						* ) 	echo " please answer [y]es or [n]o.";;
					esac
				fi
				
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done	
rm -f $working_directory/tmp_file

nova-manage cell_v2 list_cells
SQL_Output_Cell0=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use nova_api;
select count(*) from cell_mappings where uuid='00000000-0000-0000-0000-000000000000' and name='cell0' and transport_url like 'none%';
exit
EOF_SQL`
Row_Count_Cell0=`more $working_directory/tmp_file | tail -1`
rm -f $working_directory/tmp_file
SQL_Output_Cell1=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use nova_api;
select count(*) from cell_mappings where uuid<>'00000000-0000-0000-0000-000000000000' and name='cell1' and transport_url like 'rabbit://%';
exit
EOF_SQL`
Row_Count_Cell1=`more $working_directory/tmp_file | tail -1`
rm -f $working_directory/tmp_file
if [ $Row_Count_Cell0 -eq 1 ] && [ $Row_Count_Cell1 -eq 1 ]
then
	echo "  > Cell mappings (cell0 & cell1) were created successfully."
else
	read -p "  > Cell mappings (cell0 & cell1) not found or missing. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi

# print status message
echo " > 'nova-api' Service will be restarted..."
service nova-api restart
Nova_Api_Service_Status=`systemctl | grep "nova-api" | grep "active running" | wc -l`
if [ $Nova_Api_Service_Status -ge 1 ]
then
	echo "  > 'nova-api' Service Status is 'active running'"
else
	read -p "  > 'nova-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi		
	
# print status message
echo " > 'nova-consoleauth' Service will be restarted..."
service nova-consoleauth restart
Nova_Consoleauth_Service_Status=`systemctl | grep "nova-consoleauth" | grep "active running" | wc -l`
if [ $Nova_Consoleauth_Service_Status -ge 1 ]
then
	echo "  > 'nova-consoleauth' Service Status is 'active running'"
else
	read -p "  > 'nova-consoleauth' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi		

# print status message
echo " > 'nova-scheduler' Service will be restarted..."
service nova-scheduler restart
Nova_Scheduler_Service_Status=`systemctl | grep "nova-scheduler" | grep "active running" | wc -l`
if [ $Nova_Scheduler_Service_Status -ge 1 ]
then
	echo "  > 'nova-scheduler' Service Status is 'active running'"
else
	read -p "  > 'nova-scheduler' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi		
	
# print status message
echo " > 'nova-conductor' Service will be restarted..."
service nova-conductor restart
Nova_Conductor_Service_Status=`systemctl | grep "nova-conductor" | grep "active running" | wc -l`
if [ $Nova_Conductor_Service_Status -ge 1 ]
then
	echo "  > 'nova-conductor' Service Status is 'active running'"
else
	read -p "  > 'nova-conductor' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	

# print status message
echo " > 'nova-novncproxy' Service will be restarted..."
service nova-novncproxy restart
Nova_Novncproxy_Service_Status=`systemctl | grep "nova-novncproxy" | grep "active running" | wc -l`
if [ $Nova_Novncproxy_Service_Status -ge 1 ]
then
	echo "  > 'nova-novncproxy' Service Status is 'active running'"
else
	read -p "  > 'nova-novncproxy' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi	

############################## CONFIGURATION OF COMPUTE NODES:

Configured_Nodes_Count=0

IP_Input() {
	read -p "  > Please enter IP address of the compute node that will be configured:" Node_IP
	if expr "$Node_IP" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
		for i in 1 2 3 4; do
			if [ $(echo "$Node_IP" | cut -d. -f$i) -gt 255 ]; then
				echo "fail ($Node_IP)"
				return 2
			fi
		done
		return 0
	else
		return 2
	fi
}

Password_Input() {
	read -sp "  > Please enter root password to get connection of the compute node that will be configured:" Node_Password
	printf "\n"
	read -sp "  > Please confirm root password:" Node_Password1
	printf "\n"
	if [[ "$Node_Password" != "$Node_Password1" ]]; then
		echo " your passwords do not match; please try again"
		return 2
	else
		return 0
	fi	
}

while true; do
	read -p " > Do you want to configure a compute node? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				IP_Input
				if [ $? -eq 0 ]
				then
					Password_Input
					if [ $? == "2" ]
					then
						echo " Passwords don't match. Exiting..."
					else
						Remote_Node_Hostname=`more /etc/hosts | grep "${Node_IP}" | awk '{print $2}'`
						Remote_Node_IP=`more /etc/hosts | grep "$Remote_Node_Hostname" | awk '{print $1}'`
						if [ "$Remote_Node_IP" == "$Node_IP" ]
						then
							echo "  > The IP you entered was inserted in /etc/hosts file with hostname '${Remote_Node_Hostname}'"
						else
							read -p "  > The IP you entered couldn't found in /etc/hosts file. Do you want to insert a record on this node? [y/n] " yn
							case $yn in
								[Yy]* ) 
										read -p "  > Please enter the hostname of compute node: " Remote_Node_Hostname
										
										echo $Node_IP" "$Remote_Node_Hostname >> /etc/hosts
										
										Success=`more /etc/hosts | grep "$Node_IP $Remote_Node_Hostname" | wc -l`
										if [ $Success -ge 1 ]
										then
											echo " Record inserted."
										else
											echo " Record not found. Check /etc/hosts file manually."
										fi
										;;
								[Nn]* )
										echo "Script Aborted"
										;;
								* ) 	echo " please answer [y]es or [n]o.";;
							esac	
						fi
						
						# print status message
						echo " > Installing Nova Service On Compute Node..."
						while true; do
							read -p " > do you wish to install 'nova-compute' service on compute node [y/n]: " yn
							case $yn in
								[Yy]* ) 
										read -p "  > 'nova-compute' package will be installed on compute node [ IP: ${Remote_Node_IP} ] OK?" OK
										User_Created=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'cat /etc/passwd | grep $Remote_Node_Hostname | wc -l'`
										if [ $User_Created -ne 1 ]
										then
											#User 'controller' will be deleted:
											Controller_Exists=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'cat /etc/passwd | grep "controller" | wc -l'`
											if [ $Controller_Exists -eq 1 ]
											then
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/usr/bin/pkill -f 'sshd: controller'"
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/usr/sbin/userdel -r controller"
												# Username will be same with remote node hostname:
												sleep 10
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/usr/sbin/useradd -m -c '${Remote_Node_Hostname} Node' -d /home/$Remote_Node_Hostname $Remote_Node_Hostname -s /bin/bash"
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo ${Remote_Node_Hostname}:openstack | /usr/sbin/chpasswd"
											fi
										fi
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'apt -y install nova-compute'
										break;;
								[Nn]* ) 
										echo "Installation Aborted"
										exit 1
										break;;
								* ) 	
										echo " please answer [y]es or [n]o.";;
							esac
						done
#read -p "  > Starting Configuration1. OK?" OK
						RETURN_VAL=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "ifconfig eth1 | grep 'inet addr'"`
						MGMT_INTERFACE_IP_REMOTE=`echo $RETURN_VAL | awk '{print $2}' | sed 's/addr://g'`
						Nova_Config_File_Remote="/etc/nova/nova.conf"
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@${default_hostname}/g' '$Nova_Config_File_Remote'"
						Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep 'transport_url = rabbit://openstack:${RabbitMQ_Password}@controller' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[api]/\[api]\nauth_strategy = keystone/g' '$Nova_Config_File_Remote'"
Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep '^\[api]
auth_strategy = keystone' | grep -v '#' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_url = http:\/\/${default_hostname}:5000\/v3\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = service\nusername = nova\npassword = ${NOVA_PASS}\n/g' $Nova_Config_File_Remote"
						Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A8 '^\[keystone_authtoken]' | tail -1 | grep 'password = ${NOVA_PASS}' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\nmy_ip = ${MGMT_INTERFACE_IP_REMOTE}\nuse_neutron = True\nfirewall_driver = nova.virt.firewall.NoopFirewallDriver\n/g' $Nova_Config_File_Remote"
						Control4=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A3 '^\[DEFAULT]' | tail -1 | grep 'firewall_driver = nova.virt.firewall.NoopFirewallDriver' | wc -l"`					
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[vnc]/[vnc]\nenabled = True\nserver_listen = 0.0.0.0\nserver_proxyclient_address = \$my_ip\nnovncproxy_base_url = http:\/\/${default_hostname}:6080\/vnc_auto.html\n/g' $Nova_Config_File_Remote"
						Control5=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A4 '^\[vnc]' | tail -1 | grep 'novncproxy_base_url = http://${default_hostname}:6080/vnc_auto.html' | wc -l"`				
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[glance]/\[glance]\napi_servers = http:\/\/${default_hostname}:9292\n/g' $Nova_Config_File_Remote"
						Control6=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A1 '^\[glance]' | tail -1 | grep 'api_servers = http://${default_hostname}:9292' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[oslo_concurrency]/\[oslo_concurrency]\nlock_path = \/var\/lib\/nova\/tmp\n/g' $Nova_Config_File_Remote"
						Control7=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A1 '^\[oslo_concurrency]' | tail -1 | grep 'lock_path = /var/lib/nova/tmp' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^log_dir = \/var\/log\/nova/#log_dir = \/var\/log\/nova/g' $Nova_Config_File_Remote"
						Control8=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -v lock | grep -v None | grep '^#log_dir = /var/log/nova' | wc -l"`
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^os_region_name = openstack/os_region_name = RegionOne\nproject_domain_name = Default\nproject_name = service\nauth_type = password\nuser_domain_name = Default\nauth_url = http:\/\/${default_hostname}:5000\/v3\nusername = placement\npassword = ${PLACEMENT_PASS}\n/g' $Nova_Config_File_Remote"
						Control9=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Nova_Config_File_Remote} | grep -A8 '^\[placement]' | tail -1 | grep 'password = ${PLACEMENT_PASS}' | wc -l"`

						if [ $Control1 -ne 1 ] || [ $Control2 -ne 2 ] || [ $Control3 -ne 1 ] || [ $Control4 -ne 1 ] || [ $Control5 -ne 1 ] || [ $Control6 -ne 1 ] || [ $Control7 -ne 1 ] || [ $Control8 -ne 1 ] || [ $Control9 -ne 1 ]
						then
							read -p "  > There is a configuration problem with '${Nova_Config_File_Remote}' file. Please check manually. Do you want to continue? [y/n]: " yn
							case $yn in
								[Yy]* ) 
										break;;
								[Nn]* )
										echo "Script Aborted"
										exit 1
										break;;
								* ) 	echo " please answer [y]es or [n]o.";;
							esac
						else
							echo " > Configuration changes were done in '${Nova_Config_File_Remote}' file successfully."
						fi
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^virt_type=kvm/virt_type = qemu\n/g' /etc/nova/nova-compute.conf"
						Control10=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /etc/nova/nova-compute.conf | grep 'virt_type = qemu' | wc -l"`

						if [ $Control10 -eq 1 ]
						then
							echo " > Configuration change was done in '/etc/nova/nova-compute.conf' file successfully."
						else
							while true; do
							read -p "  > There is a configuration problem with '/etc/nova/nova-compute.conf' file. Please check manually. Do you want to continue? [y/n]: " yn
								case $yn in
								[Yy]* ) 
										;;
								[Nn]* )
										echo "Script Aborted"
										exit 1
										;;
								* ) 	echo " please answer [y]es or [n]o.";;
								esac
							done
						fi
						read -p "  > service nova-compute restart. OK?" OK					
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'service nova-compute restart'
						Nova_compute_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'systemctl | grep "nova-compute" | grep "active running" | wc -l'`
						if [ $Nova_compute_Service_Status -ge 1 ]
						then
							echo "  > 'nova-compute' Service Status is 'active running'"
							echo $Remote_Node_IP" "$Remote_Node_Hostname >> /root/.Compute_Node_Info
							Configured_Nodes_Count=$(($Configured_Nodes_Count + 1))
						else
							read -p "  > 'nova-compute' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
							case $yn in
								[Yy]* ) 
										;;
								[Nn]* )
										echo "Script Aborted"
										exit 1
										break;;
								* ) 	echo " please answer [y]es or [n]o.";;
							esac
						fi	
					fi
				else
					echo " Invalid IP"
				fi
				;;
		[Nn]* )

				echo " > ${Configured_Nodes_Count} Compute Node(s) Configured. Script Will Continue to Configure Controller Node... "
				echo $Configured_Nodes_Count > /root/.Configured_ComputeNodes_Count
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac

done


############################## CONFIGURATION COMPLETE FOR COMPUTE NODES. CONTINUE WITH CONTROLLER NODE'S CONFIG.:

# print status message
echo " > Adding Compute Node(s) To Cell Database..."
cd /home/${default_hostname}
. admin-openrc
openstack compute service list --service nova-compute
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
####################
openstack compute service list >> /root/.service_list
Head_Count=$((6 + $Configured_Nodes_Count))
Tail_Count=$((3 + $Configured_Nodes_Count))
Compute_Service_List=`more /root/.service_list | head -${Head_Count} | tail -${Tail_Count} | awk '{print $12}' | grep "up" | wc -l`
if [ $Compute_Service_List -eq $Tail_Count ]
then
	echo "  > 'openstack compute service list' command returned a successfull result. All services' state is 'UP'."
else
	read -p "  > 'openstack compute service list' command didn't return a successfull result.. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi

rm -f /root/.service_list


openstack catalog list >> /root/.catalog_list
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where url like '%8774/v2.1' or url like '%5000/v3/' or url like '%:8778' or url like '%:9292';
exit
EOF_SQL`
Catalog_List_Size=`echo $SQL_Output | awk '{print $2}'`

if [ $Catalog_List_Size -eq 12 ]
then
	echo "  > 'openstack catalog list' command returned a successfull result. There are 12 entries."
else
	read -p "  > > 'openstack catalog list' command didn't return a successfull result. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f /root/.catalog_list

openstack image list >> /root/.image_list
Image_List=`more /root/.image_list | grep cirros | grep active | wc -l`
if [ $Image_List -eq 1 ]
then
	echo "  > 'openstack image list' command returned a successfull result. Cirros image is active."
else
	read -p "  > 'openstack image list' command didn't return a successfull result.. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f /root/.image_list

nova-status upgrade check >> /root/.upgrade_check
sleep 2
Details_Count=`more /root/.upgrade_check | tail -12 | grep "Details: None" | wc -l`
Results_Count=`more /root/.upgrade_check | tail -12 | grep "Result: Success" | wc -l`
sleep 2
if [ $Results_Count -eq 3 ]
then
	echo "  > 'nova-status upgrade check' command returned a successfull result."
else
	read -p "  > 'nova-status upgrade check' command didn't return a successfull result.. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				break;;
		[Nn]* )
				echo "Script Aborted"
				exit 1
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac
fi
rm -f /root/.upgrade_check

read -p "  > FINISHED... Press ENTER to see the server and OpenStack services' status. OK?" OK
/etc/update-motd.d/05-systeminfo
/etc/update-motd.d/90-updates-available
/etc/update-motd.d/98-reboot-required	
				
fi


