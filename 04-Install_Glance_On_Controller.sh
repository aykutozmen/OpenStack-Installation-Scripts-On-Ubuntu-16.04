#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
cd /home/
default_username=$default_hostname
working_directory=$PWD
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | This script will do:                                                                                                |"
echo " | 1.  Management IP Existence Control in '/etc/hosts' File                                                            |"
echo " | 2.  Create Mysql DB Glance Database & User                                                                          |"
echo " | 3.  Create 'glance' User                                                                                            |"
echo " | 4.  Create 'glance' Service Entity                                                                                  |"
echo " | 5.  Create Image Service API Endpoints                                                                              |"
echo " | 6.  Install Glance Service                                                                                          |"
echo " | 7.  Glance Configuration                                                                                            |"
echo " | 8.  Populate Glance Service Database                                                                                |"
echo " | 9.  Glance Service Verification                                                                                     |"
echo " | 10. Show Server Status Summary                                                                                      |"
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
echo " > Creating Mysql DB Glance Database & User..."
read -sp "  > Please enter GLANCE_DBPASS preferred password: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	GLANCE_DBPASS=$password
fi



Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Mysql Service Status is 'active running'"

SQL_Output=`mysql -u root <<EOF_SQL
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';
FLUSH PRIVILEGES;
exit
EOF_SQL`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from mysql.user where User='glance';
exit
EOF_SQL`
Keystone_User_Count=`echo $SQL_Output | awk '{print $2}'`
	if [ $Keystone_User_Count == 2 ]
	then
		echo "  > 'glance' users created successfully with password '$GLANCE_DBPASS'"
	else
		echo "  > 'glance' users not found in mysql database"
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
cd /root
working_directory=`echo $PWD`
# print status message
echo " > Creating OpenStack 'glance' User..."
openstack user create --domain default --password-prompt glance >> ${working_directory}/glance_user
GlanceUserEnabled=`more ${working_directory}/glance_user | head -5 | tail -1 | awk '{print $4}'`
GlanceUserID=`more ${working_directory}/glance_user | head -6 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$GlanceUserID';
exit
EOF_SQL`
SQL_glance_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_glance_User_Id == 1 ]
then
	echo "  > 'glance' user is created successfully."
else
	read -p "  > 'glance' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/glance_user

openstack role add --project service --user glance admin

# print status message
echo " > Creating 'glance' service entity..."
openstack service create --name glance --description "OpenStack Image" image >> ${working_directory}/glance_service
Glance_Service_Enabled=`more ${working_directory}/glance_service | head -5 | tail -1 | awk '{print $4}'`
if [ $Glance_Service_Enabled == "True" ]
then
	echo "  > 'glance' service entity is created successfully."
else
	read -p "  > 'glance' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/glance_service



# print status message
echo " > Creating Image Service API Endpoints..."
openstack endpoint create --region RegionOne image public http://${default_hostname}:9292 >> ${working_directory}/public_api
Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`


SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url='http://${default_hostname}:9292';
exit
EOF_SQL`
SQL_glance_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_glance_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
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


openstack endpoint create --region RegionOne image internal http://${default_hostname}:9292 >> ${working_directory}/internal_api
Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url='http://${default_hostname}:9292';
exit
EOF_SQL`
SQL_glance_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_glance_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
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


openstack endpoint create --region RegionOne image admin http://${default_hostname}:9292 >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url='http://${default_hostname}:9292';
exit
EOF_SQL`
SQL_glance_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_glance_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
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
echo " > Installing Glance Service..."
while true; do
    read -p " > do you wish to install glance [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'glance' package will be installed. OK?" OK
				apt -y update
				apt -y upgrade
				apt -y install glance
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Glance_Api_Service_Status=`systemctl | grep "glance-api" | grep "active running" | wc -l`
if [ $Glance_Api_Service_Status -ge 1 ]
then
	echo "  > 'glance-api' Service Status is 'active running'"
else
	read -p "  > 'glance-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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

Glance_Registry_Service_Status=`systemctl | grep "glance-registry" | grep "active running" | wc -l`
if [ $Glance_Registry_Service_Status -ge 1 ]
then
	echo "  > 'glance-registry' Service Status is 'active running'"
else
	read -p "  > 'glance-registry' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
echo " > Glance Configuration..."
Glance_Api_Config_File="/etc/glance/glance-api.conf"

read -sp "  > Please enter glance preferred password (GLANCE_PASS): " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	GLANCE_PASS=$password
fi

sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection = mysql+pymysql:\/\/glance:${GLANCE_DBPASS}@${default_hostname}\/glance/g" "$Glance_Api_Config_File"
sed -i -r "s/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_uri = http:\/\/${default_hostname}:5000\nauth_url = http:\/\/${default_hostname}:5000\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = glance\npassword = ${GLANCE_PASS}\n/g" "$Glance_Api_Config_File"
sed -i -r "s/^\[paste_deploy]/\[paste_deploy]\nflavor = keystone\n/g" "$Glance_Api_Config_File"
sed -i -r "s/^\[glance_store]/\[glance_store]\nstores = file,http\ndefault_store = file\nfilesystem_store_datadir = \/var\/lib\/glance\/images\/\n/g" "$Glance_Api_Config_File"

keystone_authtoken_control=`more ${Glance_Api_Config_File} | grep "^\[keystone_authtoken]
auth_uri = http://${default_hostname}:5000
auth_url = http://${default_hostname}:5000
memcached_servers = ${default_hostname}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = ${GLANCE_PASS}" | wc -l`
connection_control=`more ${Glance_Api_Config_File} | grep "^\[database]
connection = mysql+pymysql://glance:${GLANCE_PASS}@${default_hostname}/glance" | wc -l`
paste_deploy_control=`more ${Glance_Api_Config_File} | grep "^\[paste_deploy]
flavor = keystone" | grep -v "^#" | wc -l`
glance_store_control=`more ${Glance_Api_Config_File} | grep "^\[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/" | grep -v "^#" | wc -l`

if [ $keystone_authtoken_control -eq 10 ] && [ $connection_control -eq 2 ] && [ $paste_deploy_control -eq 2 ] && [ ${glance_store_control} -eq 4 ]
then 
	echo "  > Glance API Configuration is OK..."
else 
	read -p "  > Glance API Configuration (${Glance_Api_Config_File}) is not OK. Do you want to continue? [y/n]: " yn
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
	

	
Glance_Registry_Config_File="/etc/glance/glance-registry.conf"

sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/connection = mysql+pymysql:\/\/glance:${GLANCE_DBPASS}@${default_hostname}\/glance/g" "$Glance_Registry_Config_File"
sed -i -r "s/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_uri = http:\/\/${default_hostname}:5000\nauth_url = http:\/\/${default_hostname}:5000\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = glance\npassword = ${GLANCE_PASS}\n/g" "$Glance_Registry_Config_File"
sed -i -r "s/^\[paste_deploy]/\[paste_deploy]\nflavor = keystone\n/g" "$Glance_Registry_Config_File"
keystone_authtoken_control=`more ${Glance_Registry_Config_File} | grep "^\[keystone_authtoken]
auth_uri = http://${default_hostname}:5000
auth_url = http://${default_hostname}:5000
memcached_servers = ${default_hostname}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = ${GLANCE_PASS}" | wc -l`
connection_control=`more ${Glance_Registry_Config_File} | grep "^\[database]
connection = mysql+pymysql://glance:${GLANCE_PASS}@${default_hostname}/glance" | wc -l`
paste_deploy_control=`more ${Glance_Registry_Config_File} | grep "^\[paste_deploy]
flavor = keystone" | grep -v "^#" | wc -l`


if [ $keystone_authtoken_control -eq 10 ] && [ $connection_control -eq 2 ] && [ $paste_deploy_control -eq 2 ]
then 
	echo "  > Glance Registry Configuration is OK..."
else 
	read -p "  > Glance Registry Configuration (${Glance_Registry_Config_File}) is not OK. Do you want to continue? [y/n]: " yn
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
echo " > Populate Glance Service Database..."
while true; do
    read -p " > do you wish to populate glance database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "glance-manage db_sync" glance
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use glance;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count -eq 15 ]
				then
					echo "  > 'glance' database tables were created successfully."
				else
					read -p "  > 'glance' database tables not found or missing. Do you want to continue? [y/n]: " yn
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
echo " > 'glance-registry' Service will be restarted..."
service glance-registry restart
Glance_Registry_Service_Status=`systemctl | grep "glance-registry" | grep "active running" | wc -l`
if [ $Glance_Registry_Service_Status -ge 1 ]
then
	echo "  > 'glance-registry' Service Status is 'active running'"
else
	read -p "  > 'glance-registry' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
echo " > 'glance-api' Service will be restarted..."
service glance-api restart
Glance_Api_Service_Status=`systemctl | grep "glance-api" | grep "active running" | wc -l`
if [ $Glance_Api_Service_Status -ge 1 ]
then
	echo "  > 'glance-api' Service Status is 'active running'"
else
	read -p "  > 'glance-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
echo " > Glance Service Verification..."

working_directory=`echo $PWD`
read -p "  > Glance Service will be verified. Do you want to continue? [y/n]: " yn
case $yn in
	[Yy]* ) 
			cd /home/${default_username}/
			working_directory=`echo $PWD`
			. admin-openrc
			wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
			if [ -e cirros-0.4.0-x86_64-disk.img ]
			then
				echo "  > Cirros image downloaded successfully"
			else
				read -p "  > Cirros image (${working_directory}/cirros-0.4.0-x86_64-disk.img) could not found. Do you want to continue? [y/n]: " yn
				case $yn in	
					[Yy]* ) break;;
					[Nn]* ) echo "Script Aborted"
							exit 1
							break;;
					* ) 	echo " please answer [y]es or [n]o.";;
				esac
			fi
			openstack image create "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --public >> $working_directory/image_create
			Image_Checksum=`more ${working_directory}/image_create | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from glance.images where checksum = '${Image_Checksum}';
exit
EOF_SQL`
			SQL_Cirros_Image_Checksum=`echo $SQL_Output | awk '{print $2}'`

			if [ $SQL_Cirros_Image_Checksum == 1 ]
			then
				echo "  > Cirros image is created successfully."
			else
				read -p "  > Cirros image could not be created successfully. Do you want to continue? [y/n]: " yn
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
			rm -f ${working_directory}/image_create
			
			openstack image list >> $working_directory/image_list
			
			Image_ID=`more ${working_directory}/image_list | head -4 | tail -1 | awk '{print $2}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from glance.images where id = '${Image_ID}';
exit
EOF_SQL`
			SQL_Cirros_Image_ID=`echo $SQL_Output | awk '{print $2}'`

			if [ $SQL_Cirros_Image_ID == 1 ]
			then
				echo "  > Cirros image is verified."
			else
				read -p "  > Cirros image could not be verified. Do you want to continue? [y/n]: " yn
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
			rm -f ${working_directory}/image_list

			;;
#			break;;
	[Nn]* )
			echo "Script Aborted"
			exit 1
			break;;
	* ) 	echo " please answer [y]es or [n]o.";;
esac
	
read -p "  > FINISHED... Press ENTER to see the server and OpenStack services' status. OK?" OK

/etc/update-motd.d/05-systeminfo

/etc/update-motd.d/90-updates-available

/etc/update-motd.d/98-reboot-required


fi


