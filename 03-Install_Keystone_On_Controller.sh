#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
default_username=`hostname`
working_directory=`echo $PWD`
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | This script will do:                                                                                                |"
echo " | 1. Management IP Existence Control in '/etc/hosts' File                                                             |"
echo " | 2. Creating Mysql DB Keystone Database & User                                                                       |"
echo " | 3. Keystone, Apache2 and libapache2-mod-wsgi Installation                                                           |"
echo " | 4. Keystone Configuration                                                                                           |"
echo " | 5. Populate Keystone Service Database                                                                               |"
echo " | 6. Initialize Fernet Key Repositories                                                                               |"
echo " | 7. Bootstrapping the Keystone Service                                                                               |"
echo " | 8. Apache Server Configuration                                                                                      |"
echo " | 9. Administrative Account Configuration                                                                             |"
echo " | 10. Creating OpenStack Domain, Projects, Users & Roles                                                              |"
echo " | 11. Creating OpenStack User Environment Scripts                                                                     |"
echo " | 12. Controlling User Scripts                                                                                        |"
echo " | 13. Show Server Status Summary                                                                                      |"
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
echo " > Creating Mysql DB Keystone Database & User..."
read -sp "  > Please enter KEYSTONE_DBPASS preferred password: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	KEYSTONE_DBPASS=$password
fi



Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Mysql Service Status is 'active running'"

SQL_Output=`mysql -u root <<EOF_SQL
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';
FLUSH PRIVILEGES;
exit
EOF_SQL`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from mysql.user where User='keystone';
exit
EOF_SQL`
Keystone_User_Count=`echo $SQL_Output | awk '{print $2}'`
	if [ $Keystone_User_Count == 2 ]
	then
		echo "  > 'keystone' users created successfully with password '$KEYSTONE_DBPASS'"
	else
		echo "  > 'keystone' users not found in mysql database"
		echo "Script Aborted"
		exit 1		
	fi

else
	echo "  > Mysql service status is not 'active running'. please restart the script and try again"
	echo "Script Aborted"
	exit 1
fi

# print status message
echo " > Installing Keystone..."
while true; do
    read -p " > do you wish to install 'keystone', 'apache2' and 'libapache2-mod-wsgi' packages [y/n]: " yn
    case $yn in
        [Yy]* ) 
#				read -p "  > 'keystone' package will be installed. OK?" OK
				apt -y install keystone
#				read -p "  > 'apache2' package will be installed. OK?" OK
				apt -y install apache2	
#				read -p "  > 'libapache2-mod-wsgi' package will be installed. OK?" OK
				apt -y install libapache2-mod-wsgi					
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
echo " > Keystone Configuration..."
Keystone_Config_File="/etc/keystone/keystone.conf"
sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection = mysql+pymysql:\/\/keystone:${KEYSTONE_DBPASS}@${default_hostname}\/keystone/g" "$Keystone_Config_File"
sed -i -r "s/^\[token]/\[token]\nprovider = fernet/g" "$Keystone_Config_File"
Connection_Config_OK=`more ${Keystone_Config_File} | grep "connection = mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${default_hostname}/keystone" | wc -l`
Provider_Config_OK=`more ${Keystone_Config_File} | grep -v "^#" | grep "provider = fernet" | wc -l`
if [ $Connection_Config_OK -eq 1 ] && [ $Provider_Config_OK -eq 1 ]
then 
	echo "  > Configuration is OK..."
else 
	read -p "  > Configuration is not OK. Do you want to continue? [y/n]: " yn
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
echo " > Populate Keystone Service Database..."
while true; do
    read -p " > do you wish to populate keystone database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "keystone-manage db_sync" keystone
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use keystone;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count -eq 44 ]
				then
					echo "  > 'keystone' database tables were created successfully."
				else
					read -p "  > 'keystone' database tables not found or missing. Do you want to continue? [y/n]: " yn
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


# print status message
echo " > Initialize Fernet key repositories..."
read -p "  > Fernet key repositories will be initalized. OK?" OK
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# print status message
echo " > Bootstrapping the identity service..."
read -p "  > The Keystone Service will be bootstrapped. OK?" OK
read -sp "  > Please enter administrative user's preferred password (ADMIN_PASS): " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	ADMIN_PASS=$password
fi

keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} --bootstrap-admin-url http://${default_hostname}:5000/v3/ --bootstrap-internal-url http://${default_hostname}:5000/v3/ --bootstrap-public-url http://${default_hostname}:5000/v3/ --bootstrap-region-id RegionOne


# print status message
echo " > Apache Server Configuration..."
Apache_Config_File="/etc/apache2/apache2.conf"
echo "ServerName "${default_hostname} >> $Apache_Config_File
Apache_Config_OK=`more $Apache_Config_File | grep "ServerName "${default_hostname} | wc -l`
if [ $Apache_Config_OK -eq 1 ]
then 
	echo "  > Configuration is OK..."
else 
	read -p "  > Configuration is not OK. Do you want to continue? [y/n]: " yn
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
echo " > Apache Service will be restarted..."
service apache2 restart
Apache_Service_Status=`systemctl | grep apache2 | grep "active running" | wc -l`
if [ $Apache_Service_Status -ge 1 ]
then
	echo "  > Service Status is 'active running'"
else
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
fi	

# print status message
echo " > Administrative Account Configuration..."
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${default_hostname}:5000/v3
export OS_IDENTITY_API_VERSION=3
echo "
   OS_USERNAME="$OS_USERNAME"
   OS_PASSWORD="$ADMIN_PASS"
   OS_PROJECT_NAME="$OS_PROJECT_NAME"
   OS_USER_DOMAIN_NAME="$OS_USER_DOMAIN_NAME"
   OS_PROJECT_DOMAIN_NAME="$OS_PROJECT_DOMAIN_NAME"
   OS_AUTH_URL="$OS_AUTH_URL"
   OS_IDENTITY_API_VERSION="$OS_IDENTITY_API_VERSION"
"

# print status message
echo " > Creating OpenStack Domain, Projects, Users & Roles ..."
openstack domain create --description "An Example Domain" example >> ${working_directory}/domain
Domain_Enabled=`more ${working_directory}/domain| head -5 | tail -1 | awk '{print $4}'`
if [ $Domain_Enabled == "True" ]
then
	echo "  > 'An Example Domain' is created successfully."
else
	read -p "  > 'An Example Domain' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/domain

openstack project create --domain default --description "Service Project" service >> ${working_directory}/service_project
Service_Project_Enabled=`more ${working_directory}/service_project| head -6 | tail -1 | awk '{print $4}'`
if [ $Service_Project_Enabled == "True" ]
then
	echo "  > 'Service Project' is created successfully."
else
	read -p "  > 'Service Project' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/service_project


openstack project create --domain default --description "Demo Project" demo >> ${working_directory}/demo_project
Demo_Project_Enabled=`more ${working_directory}/demo_project| head -6 | tail -1 | awk '{print $4}'`
if [ $Demo_Project_Enabled == "True" ]
then
	echo "  > 'Demo Project' is created successfully."
else
	read -p "  > 'Demo Project' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/demo_project

openstack user create --domain default --password-prompt demo >> ${working_directory}/demo_user
Demo_User_Enabled=`more ${working_directory}/demo_user | head -5 | tail -1 | awk '{print $4}'`
Demo_User_Name=`more ${working_directory}/demo_user | head -7 | tail -1 | awk '{print $4}'`
if [ $Demo_User_Enabled == "True" ] && [ $Demo_User_Name == "demo" ]
then
	echo "  > 'demo' user is created successfully."
else
	read -p "  > 'demo' user could not be created successfully. [ select * from keystone.local_user where name='demo'; ] Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/demo_user

openstack role create user >> ${working_directory}/role
Role_Name=`more ${working_directory}/role | head -6 | tail -1 | awk '{print $4}'`
if [ $Role_Name == "user" ]
then
	echo "  > 'user' role is created successfully."
else
	read -p "  > 'user' role could not be created successfully. [ select * from keystone.role where name='user'; ] Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/role


openstack role add --project demo --user demo user

unset OS_AUTH_URL OS_PASSWORD

openstack --os-auth-url http://${default_hostname}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-username admin token issue >> ${working_directory}/admin_token_issue
Admin_User_Id=`more ${working_directory}/admin_token_issue | head -7 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$Admin_User_Id';
exit
EOF_SQL`
SQL_Admin_User_Id=`echo $SQL_Output | awk '{print $2}'`
if [ $SQL_Admin_User_Id == 1 ]
then
	echo "  > Token is created successfully by OpenStack for 'admin' user."
else
	read -p "  > Token ID for 'admin' user is not matching with database record for 'admin' user.  [ select count(*) from keystone.user where id = '${Admin_User_Id}'; ] Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/admin_token_issue


openstack --os-auth-url http://${default_hostname}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name demo --os-username demo token issue >> ${working_directory}/demo_token_issue
Demo_User_Id=`more ${working_directory}/demo_token_issue | head -7 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$Demo_User_Id';
exit
EOF_SQL`
SQL_Admin_User_Id=`echo $SQL_Output | awk '{print $2}'`
if [ $SQL_Admin_User_Id == 1 ]
then
	echo "  > Token is created successfully by OpenStack for 'demo' user."
else
	read -p "  > Token ID for 'demo' user is not matching with database record for 'admin' user.  [ select count(*) from keystone.user where id = '${Demo_User_Id}'; ] Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/demo_token_issue

# print status message
default_hostname=`hostname`
echo " > Creating OpenStack User Environment Scripts..."
touch /home/${default_hostname}/admin-openrc
echo "export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_AUTH_URL=http://${default_hostname}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
" >> /home/${default_hostname}/admin-openrc

if [ -e /home/${default_hostname}/admin-openrc ]
then
	echo "  > /home/${default_hostname}/admin-openrc is created successfully."
else
	read -p "  > /home/${default_hostname}/admin-openrc could not be created successfully. Do you want to continue? [y/n]: " yn
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

read -sp "  > Please enter demo user's preferred password (DEMO_PASS): " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	DEMO_PASS=$password
fi

touch /home/${default_hostname}/demo-openrc
echo "export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=${DEMO_PASS}
export OS_AUTH_URL=http://${default_hostname}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
" >> /home/${default_hostname}/demo-openrc

if [ -e /home/${default_hostname}/demo-openrc ]
then
	echo "  > /home/${default_hostname}/demo-openrc is created successfully."
else
	read -p "  > /home/${default_hostname}/demo-openrc could not be created successfully. Do you want to continue? [y/n]: " yn
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
echo " > Controlling User Scripts..."
echo "  > 'openstack token issue' with admin-openrc"
cd /home/${default_hostname}/
. admin-openrc
openstack token issue

echo "  > 'openstack token issue' with demo-openrc"
. demo-openrc
openstack token issue
rm -f $working_directory/tmp_file
read -p "  > FINISHED... Press ENTER to see the server and OpenStack services' status. OK?" OK

/etc/update-motd.d/05-systeminfo

/etc/update-motd.d/90-updates-available

/etc/update-motd.d/98-reboot-required


fi




