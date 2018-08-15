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
echo " | Before starting step 9 be sure that Controller node can connect to compute node via SSH and compute node's info     |"
echo " | is added to known hosts file.                                                                                       |"
echo " | This script will do:                                                                                                |"
echo " | 1.  Management IP Existence Control in '/etc/hosts' File                                                            |"
echo " | 2.  Create Mysql DB Neutron Databases & Users                                                                       |"
echo " | 3.  Create 'neutron' User                                                                                           |"
echo " | 4.  Create 'neutron' Service Entity                                                                                 |"
echo " | 5.  Create Neutron Service API Endpoints                                                                            |"
echo " | 6.  Install Neutron Services                                                                                        |"
echo " | 7.  Neutron Configuration                                                                                           |"
echo " | 8.  Populate Neutron Service Databases                                                                              |"
echo " | 9.  Connect & Configure A Compute Node                                                                              |"
echo " |        a. IP & Hostname Control Of Compute Node                                                                     |"
echo " |        b. Input Password Of Compute Node For SSH Connection                                                         |"
echo " |        c. Install 'neutron-linuxbridge-agent' Package On Compute Node                                               |"
echo " |        d. Configure 'neutron-linuxbridge-agent' Service On Compute Node                                             |"
echo " | 10. Controlling Neutron Agent List                                                                                  |"
echo " | 11. Show Server Status Summary                                                                                      |"
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
MGMT_INTERFACE_IP=`more /etc/hosts | grep ${default_hostname} |awk '{print $1}'`
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
echo " > Creating Mysql DB Neutron Databases & Users..."
read -sp "  > Please enter NEUTRON_DBPASS preferred password: " password
printf "\n"
read -sp "  > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	NEUTRON_DBPASS=$password
fi

Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Mysql Service Status is 'active running'"

SQL_Output=`mysql -u root <<EOF_SQL
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${NEUTRON_DBPASS}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}';
FLUSH PRIVILEGES;
exit
EOF_SQL`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from mysql.user where User='neutron';
exit
EOF_SQL`
Neutron_User_Count=`echo $SQL_Output | awk '{print $2}'`
	if [ $Neutron_User_Count == 2 ]
	then
		echo "  > 'neutron' users created successfully with password '$NEUTRON_DBPASS'"
	else
		echo "  > 'neutron' users not found in mysql database"
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
echo " > Creating OpenStack 'neutron' User..."
openstack user create --domain default --password-prompt neutron >> ${working_directory}/neutron_user
NeutronUserEnabled=`more ${working_directory}/neutron_user | head -5 | tail -1 | awk '{print $4}'`
NeutronUserID=`more ${working_directory}/neutron_user | head -6 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$NeutronUserID';
exit
EOF_SQL`
SQL_neutron_user_Id=`echo $SQL_Output | awk '{print $2}'`


if [ $SQL_neutron_user_Id == 1 ] && [ $NeutronUserEnabled == "True" ]
then
	echo "  > 'neutron' user is created successfully."
	read -p " > NOTE: 'neutron' User's Password you entered (NEUTRON_PASS) will be asked again in the next steps. Please note it. OK?" OK
else
	read -p "  > 'neutron' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/neutron_user

openstack role add --project service --user neutron admin

# print status message
echo " > Creating 'neutron' service entity..."
openstack service create --name neutron --description "OpenStack Networking" network >> ${working_directory}/neutron_service
Neutron_Service_Enabled=`more ${working_directory}/neutron_service | head -5 | tail -1 | awk '{print $4}'`
Neutron_Service_ID=`more ${working_directory}/neutron_service | head -6 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.service where type='network' and enabled=1 and id='$Neutron_Service_ID';
exit
EOF_SQL`
SQL_neutron_Service_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $Neutron_Service_Enabled == "True" ] && [ $SQL_neutron_Service_Id == 1 ]
then
	echo "  > 'neutron' service entity is created successfully."
else
	read -p "  > 'neutron' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/neutron_service


# print status message
echo " > Creating Neutron Service API Endpoints..."
openstack endpoint create --region RegionOne network public http://${default_hostname}:9696 >> ${working_directory}/public_api

Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`


SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url='http://${default_hostname}:9696';
exit
EOF_SQL`
SQL_neutron_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_neutron_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
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


openstack endpoint create --region RegionOne network internal http://${default_hostname}:9696 >> ${working_directory}/internal_api

Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url='http://${default_hostname}:9696';
exit
EOF_SQL`
SQL_neutron_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_neutron_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
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

openstack endpoint create --region RegionOne network admin http://${default_hostname}:9696 >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url='http://${default_hostname}:9696';
exit
EOF_SQL`
SQL_neutron_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_neutron_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
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
echo " > Installing Neutron Services..."
while true; do
    read -p " > do you wish to install neutron services [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'neutron-server' 'neutron-plugin-ml2' 'neutron-linuxbridge-agent' 'neutron-l3-agent' 'neutron-dhcp-agent' 'neutron-metadata-agent' packages will be installed. OK?" OK
				apt -y install neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Service_Neutron_Server() {
Neutron_Server_Service_Status=`systemctl | grep "neutron-server" | grep "active running" | wc -l`
if [ $Neutron_Server_Service_Status -ge 1 ]
then
	echo "  > 'neutron-server' Service Status is 'active running'"
else
	read -p "  > 'neutron-server' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_Server

Service_Neutron_L3Agent() {
Neutron_L3_Service_Status=`systemctl | grep "neutron-l3-agent" | grep "active running" | wc -l`
if [ $Neutron_L3_Service_Status -ge 1 ]
then
	echo "  > 'neutron-l3-agent' Service Status is 'active running'"
else
	read -p "  > 'neutron-l3-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_L3Agent

Service_Neutron_DHCPAgent() {
Neutron_DHCP_Service_Status=`systemctl | grep "neutron-dhcp-agent" | grep "active running" | wc -l`
if [ $Neutron_DHCP_Service_Status -ge 1 ]
then
	echo "  > 'neutron-dhcp-agent' Service Status is 'active running'"
else
	read -p "  > 'neutron-dhcp-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_DHCPAgent

Service_Neutron_LinuxbridgeAgent() {
Neutron_Linuxbridge_Service_Status=`systemctl | grep "neutron-linuxbridge-agent" | grep "active running" | wc -l`
if [ $Neutron_Linuxbridge_Service_Status -ge 1 ]
then
	echo "  > 'neutron-linuxbridge-agent' Service Status is 'active running'"
else
	read -p "  > 'neutron-linuxbridge-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_LinuxbridgeAgent

Service_Neutron_Linuxbridge_Cleanup() {
Neutron_Linuxbridge_Cleanup_Service_Status=`systemctl | grep "neutron-linuxbridge-cleanup" | grep "active running" | wc -l`
if [ $Neutron_Linuxbridge_Cleanup_Service_Status -ge 1 ]
then
	echo "  > 'neutron-linuxbridge-cleanup' Service Status is 'active running'"
else
	read -p "  > 'neutron-linuxbridge-cleanup' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_Linuxbridge_Cleanup

Service_Neutron_MetadataAgent() {
Neutron_Metadata_Service_Status=`systemctl | grep "neutron-metadata-agent" | grep "active running" | wc -l`
if [ $Neutron_Metadata_Service_Status -ge 1 ]
then
	echo "  > 'neutron-metadata-agent' Service Status is 'active running'"
else
	read -p "  > 'neutron-metadata-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
}
Service_Neutron_MetadataAgent

read -sp " > Please enter neutron user's preferred password (NEUTRON_PASS) that you entered before: " password
printf "\n"
read -sp " > confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit 1
else
	NEUTRON_PASS=$password
	echo $NEUTRON_PASS > /root/.NEUTRON_PASS
	chattr +i /root/.NEUTRON_PASS
fi

MGMT_INTERFACE_IP=`ifconfig eth1 | grep "inet addr" | grep -v "127.0.0.1" | awk '{print $2}' | sed 's/addr://g'`

#CONTROLLER
Neutron_Config_File_1="/etc/neutron/neutron.conf" 
if [ -e $Neutron_Config_File_1 ]
then
	# Configuration changes:
	sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/connection = mysql+pymysql:\/\/neutron:${NEUTRON_DBPASS}@${default_hostname}\/neutron/g" "$Neutron_Config_File_1"
	Control1=`cat $Neutron_Config_File_1 | grep "^connection = mysql+pymysql:\/\/neutron:${NEUTRON_DBPASS}@${default_hostname}\/neutron" | wc -l`
	sed -i -r "s/^core_plugin = ml2/core_plugin = ml2\nservice_plugins = router\nallow_overlapping_ips = true\n/g" "${Neutron_Config_File_1}"
	RabbitMQ_Password=`more /root/.RabbitMQ_User_Password`
	sed -i -r "s/^\[DEFAULT]/[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@${default_hostname}\nauth_strategy = keystone\nnotify_nova_on_port_status_changes = true\nnotify_nova_on_port_data_changes = true/g" "${Neutron_Config_File_1}"
	Control2=`cat $Neutron_Config_File_1 | grep -A7 "^\[DEFAULT]" | tail -1 | grep "allow_overlapping_ips = true" | wc -l`
	sed -i -r "s/^\[keystone_authtoken]/[keystone_authtoken]\nauth_uri = http:\/\/${default_hostname}:5000\nauth_url = http:\/\/${default_hostname}:5000\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\n/g" "${Neutron_Config_File_1}"
	Control3=`cat $Neutron_Config_File_1 | grep -A9 "^\[keystone_authtoken]" | tail -1 | grep "password = ${NEUTRON_PASS}" | wc -l`
	NOVA_PASS=`cat /root/.NOVA_PASS`
	sed -i -r "s/^\[nova]/[nova]\nauth_url = http:\/\/${default_hostname}:5000\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nregion_name = RegionOne\nproject_name = service\nusername = nova\npassword = ${NOVA_PASS}\n/g" "${Neutron_Config_File_1}"
	Control4=`cat $Neutron_Config_File_1 | grep -A8 "^\[nova]" | tail -1 | grep "password = ${NOVA_PASS}" | wc -l`
	if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ] || [ $Control4 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_1}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_1}' file successfully."
	fi	
else
	echo $Neutron_Config_File_1" file not found. "
fi

Neutron_Config_File_2="/etc/neutron/plugins/ml2/ml2_conf.ini" 
if [ -e $Neutron_Config_File_2 ]
then
	# Configuration changes:
	sed -i -r "s/^\[ml2]/[ml2]\ntype_drivers = flat,vlan,vxlan\ntenant_network_types = vxlan\nmechanism_drivers = linuxbridge,l2population\nextension_drivers = port_security\n/g" "${Neutron_Config_File_2}"
	Control1=`cat $Neutron_Config_File_2 | grep -A4 "^\[ml2]" | tail -1 | grep "extension_drivers = port_security" | wc -l`
	sed -i -r "s/^\[ml2_type_flat]/[ml2_type_flat]\nflat_networks = provider\n/g" "${Neutron_Config_File_2}"
	Control2=`cat $Neutron_Config_File_2 | grep -A1 "^\[ml2_type_flat]" | tail -1 | grep "flat_networks = provider" | wc -l`
	sed -i -r "s/^\[ml2_type_vxlan]/[ml2_type_vxlan]\nvni_ranges = 1:1000\n/g" "${Neutron_Config_File_2}"
	Control3=`cat $Neutron_Config_File_2 | grep -A1 "^\[ml2_type_vxlan]" | tail -1 | grep "vni_ranges = 1:1000" | wc -l`
	sed -i -r "s/^\[securitygroup]/[securitygroup]\nenable_ipset = true\n/g" "${Neutron_Config_File_2}"
	Control4=`cat $Neutron_Config_File_2 | grep -A1 "^\[securitygroup]" | tail -1 | grep "enable_ipset = true" | wc -l`
	if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ] || [ $Control4 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_2}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_2}' file successfully."
	fi	
else
	echo $Neutron_Config_File_2" file not found. "
fi

PROVIDER_INTERFACE_IP=`ifconfig | grep "inet addr:" | grep -v ${MGMT_INTERFACE_IP} | grep -v "127.0.0.1" | awk '{print $2}' | tr -d "addr:"`
PROVIDER_INTERFACE_NAME=`ifconfig | grep -C1 "inet addr:$PROVIDER_INTERFACE_IP" | grep "Link encap" | awk '{print $1}'`
Neutron_Config_File_3="/etc/neutron/plugins/ml2/linuxbridge_agent.ini" 
if [ -e $Neutron_Config_File_3 ]
then
	# Configuration changes:
	sed -i -r "s/^\[linux_bridge]/[linux_bridge]\nphysical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}\n/g" "${Neutron_Config_File_3}"
	Control1=`cat $Neutron_Config_File_3 | grep -A1 "^\[linux_bridge]" | tail -1 | grep "physical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}" | wc -l`
	sed -i -r "s/^\[vxlan]/[vxlan]\nenable_vxlan = true\nlocal_ip = ${MGMT_INTERFACE_IP}\nl2_population = true\n/g" "${Neutron_Config_File_3}"
	Control2=`cat $Neutron_Config_File_3 | grep -A2 "^\[vxlan]" | tail -1 | grep "local_ip = ${MGMT_INTERFACE_IP}" | wc -l`
	sed -i -r "s/^\[securitygroup]/[securitygroup]\nenable_security_group = true\nfirewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver\n/g" "${Neutron_Config_File_3}"
	Control3=`cat $Neutron_Config_File_3 | grep -A2 "^\[securitygroup]" | tail -1 | grep "firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver" | wc -l`
	if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_3}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_3}' file successfully."
	fi		
else
	echo $Neutron_Config_File_3" file not found. "
fi

sysctl net.bridge.bridge-nf-call-iptables > /root/.result
Support_For_LinuxBridge_Filters=`more /root/.result | awk '{print $3}'`
if [ $Support_For_LinuxBridge_Filters -ne 1 ]
then
	read -p "  > Your Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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
Support_For_LinuxBridge_Filters=""
sysctl net.bridge.bridge-nf-call-ip6tables > /root/.result
Support_For_LinuxBridge_Filters=`more /root/.result | awk '{print $3}'`
if [ $Support_For_LinuxBridge_Filters -ne 1 ]
then
	read -p "  > Your Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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

Neutron_Config_File_4="/etc/neutron/l3_agent.ini"
if [ -e $Neutron_Config_File_4 ]
then
	# Configuration changes:
	sed -i -r "s/^\[DEFAULT]/[DEFAULT]\ninterface_driver = linuxbridge\n/g" "${Neutron_Config_File_4}"
	Control1=`cat $Neutron_Config_File_4 | grep -A1 "^\[DEFAULT]" | tail -1 | grep "interface_driver = linuxbridge" | wc -l`
	if [ $Control1 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_4}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_4}' file successfully."
	fi
else
	echo $Neutron_Config_File_4" file not found. "
fi


Neutron_Config_File_5="/etc/neutron/dhcp_agent.ini"
if [ -e $Neutron_Config_File_5 ]
then
	# Configuration changes:
	sed -i -r "s/^\[DEFAULT]/[DEFAULT]\ninterface_driver = linuxbridge\ndhcp_driver = neutron.agent.linux.dhcp.Dnsmasq\nenable_isolated_metadata = true\n/g" "${Neutron_Config_File_5}"
	Control1=`cat $Neutron_Config_File_5 | grep -A3 "^\[DEFAULT]" | tail -1 | grep "enable_isolated_metadata = true" | wc -l`
	if [ $Control1 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_5}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_5}' file successfully."
	fi	
else
	echo $Neutron_Config_File_5" file not found. "
fi

Neutron_Config_File_6="/etc/neutron/metadata_agent.ini"
if [ -e $Neutron_Config_File_6 ]
then
	# Configuration changes:
	read -sp "  > Please enter metadata proxy shared secret (METADATA_SECRET): " password
	printf "\n"
	read -sp "  > confirm your preferred password: " password2
	printf "\n"

	# check if the passwords match to prevent headaches
	if [[ "$password" != "$password2" ]]; then
		echo " your passwords do not match; please restart the script and try again"
		echo
		exit 1
	else
		METADATA_SECRET=$password
		echo $METADATA_SECRET > /root/.METADATA_SECRET
		chattr +i /root/.METADATA_SECRET
	fi
	sed -i -r "s/^\[DEFAULT]/[DEFAULT]\nnova_metadata_host = ${default_hostname}\nmetadata_proxy_shared_secret = ${METADATA_SECRET}\n/g" "${Neutron_Config_File_6}" 
	Control1=`cat /etc/neutron/metadata_agent.ini | grep -A2 "^\[DEFAULT]" | tail -1 | grep "metadata_proxy_shared_secret = ${METADATA_SECRET}" | wc -l`
	if [ $Control1 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Neutron_Config_File_6}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Neutron_Config_File_6}' file successfully."
	fi	
else
	echo $Neutron_Config_File_6" file not found. "
fi


Nova_Config_File="/etc/nova/nova.conf"
if [ -e $Nova_Config_File ]
then
	# Configuration changes:
	sed -i -r "s/^\[neutron]/[neutron]\nurl = http:\/\/${default_hostname}:9696\nauth_url = http:\/\/${default_hostname}:5000\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nregion_name = RegionOne\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\nservice_metadata_proxy = true\nmetadata_proxy_shared_secret = ${METADATA_SECRET}\n/g" "${Nova_Config_File}"
	Control1=`cat $Nova_Config_File | grep -A11 "^\[neutron]" | tail -1 | grep "metadata_proxy_shared_secret = ${METADATA_SECRET}" | wc -l`
	if [ $Control1 -ne 1 ]
	then
		read -p "  > There is a configuration problem with '${Nova_Config_File}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		echo " > Configuration changes were done in '${Nova_Config_File}' file successfully."
	fi		
else
	echo $Nova_Config_File" file not found. "
fi

# print status message
echo " > Populate 'neutron' Service Database..."
while true; do
    read -p " > do you wish to populate 'neutron' database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "neutron-db-manage --config-file ${Neutron_Config_File_1} --config-file ${Neutron_Config_File_2} upgrade head" neutron
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use neutron;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count -eq 175 ]
				then
					echo "  > 'neutron' database tables were created successfully."
				else
					read -p "  > 'neutron' database tables not found or missing. Do you want to continue? [y/n]: " yn
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


Service_Nova_Api() {
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
}

# print status message
echo " > 'nova-api' Service will be restarted..."
service nova-api restart
Service_Nova_Api	

echo " > 'neutron-server' Service will be restarted..."
service neutron-server restart
Service_Neutron_Server

echo " > 'neutron-linuxbridge-agent' Service will be restarted..."
service neutron-linuxbridge-agent restart
Service_Neutron_LinuxbridgeAgent

echo " > 'neutron-dhcp-agent' Service will be restarted..."
service neutron-dhcp-agent restart
Service_Neutron_DHCPAgent

echo " > 'neutron-metadata-agent' Service will be restarted..."
service neutron-metadata-agent restart
Service_Neutron_MetadataAgent

echo " > 'neutron-l3-agent' Service will be restarted..."
service neutron-l3-agent restart
Service_Neutron_L3Agent

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

	if [ -e /root/.Configured_ComputeNodes_Count ]
	then
		Configured_Nodes_Count=`cat /root/.Configured_ComputeNodes_Count`
	else
		Configured_Nodes_Count=0
		echo $Configured_Nodes_Count > /root/.Configured_ComputeNodes_Count
	fi
	read -p " > You have configured ${Configured_Nodes_Count} compute node(s) before. Do you want to configure them or configure other one(s)? Configure Them [t/T]hem / Configure Others [o/O]thers: " yn
	case $yn in
		[Oo]* ) 
				Configured_Nodes_Count=0
				
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
										echo " > Installing Neutron Service On Compute Node..."
										while true; do
											read -p " > do you wish to install 'neutron-linuxbridge-agent' service on compute node [y/n]: " yn
											case $yn in
												[Yy]* ) 
														read -p "  > 'neutron-linuxbridge-agent' package will be installed on compute node [ IP: ${Remote_Node_IP} ] OK?" OK
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
														sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'apt -y install neutron-linuxbridge-agent'
														break;;
												[Nn]* ) 
														echo "Installation Aborted"
														exit 1
														break;;
												* ) 	
														echo " please answer [y]es or [n]o.";;
											esac
										done
				
										Neutron_Config_File_Remote1="/etc/neutron/neutron.conf"
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/\#connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/g' '$Neutron_Config_File_Remote1'"
										Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep '^#connection = sqlite:////var/lib/neutron/neutron.sqlite' | wc -l"`
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@controller\nauth_strategy = keystone\n/g' '$Neutron_Config_File_Remote1'"
										Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep -A1 '^transport_url = rabbit://openstack:${RabbitMQ_Password}@controller' | tail -1 | grep 'auth_strategy = keystone' | wc -l"`
										Neutron_Config_File_Remote2="/etc/nova/nova.conf"
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_uri = http:\/\/${default_hostname}:5000\nauth_url = http:\/\/${default_hostname}:5000\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\n/g' '$Neutron_Config_File_Remote1'"
										Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep -A9 '^\[keystone_authtoken]' | tail -1 | grep 'password = ${NEUTRON_PASS}' | wc -l"`

										if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ]
										then
											read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote1}' file. Please check manually. Do you want to continue? [y/n]: " yn
											case $yn in
												[Yy]* ) 
														;;
												[Nn]* )
														echo "Script Aborted"
														exit 1
														break;;
												* ) 	echo " please answer [y]es or [n]o.";;
											esac
										else
											echo " > Configuration changes were done in '${Neutron_Config_File_Remote1}' file successfully."
										fi
				
										Neutron_Config_File_Remote2="/etc/neutron/plugins/ml2/linuxbridge_agent.ini"
										MGMT_INTERFACE_IP_REMOTE=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "ifconfig eth1 | grep 'inet addr'" | awk '{print $2}' | sed 's/addr://g'`
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[linux_bridge]/[linux_bridge]\nphysical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}\n/g' '${Neutron_Config_File_Remote2}'"
										Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote2} | grep -A1 '\[linux_bridge]' | tail -1 | grep 'physical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}' | wc -l"`
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[vxlan]/[vxlan]\nenable_vxlan = true\nlocal_ip = ${MGMT_INTERFACE_IP_REMOTE}\nl2_population = true\n/g' '${Neutron_Config_File_Remote2}'"
										Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote2 | grep -A2 '^\[vxlan]' | tail -1 | grep 'local_ip = ${MGMT_INTERFACE_IP_REMOTE}' | wc -l"`
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[securitygroup]/[securitygroup]\nenable_security_group = true\nfirewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver\n/g' '${Neutron_Config_File_Remote2}'"
										Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote2 | grep -A2 '^\[securitygroup]' | tail -1 | grep 'firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' | wc -l"`
										if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ]
										then
											read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote2}' file. Please check manually. Do you want to continue? [y/n]: " yn
											case $yn in
												[Yy]* ) 
														;;
												[Nn]* )
														echo "Script Aborted"
														exit 1
														break;;
												* ) 	echo " please answer [y]es or [n]o.";;
											esac
										else
											echo " > Configuration changes were done in '${Neutron_Config_File_Remote2}' file successfully."
										fi		
				
										Support_For_LinuxBridge_Filters=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sysctl net.bridge.bridge-nf-call-iptables | sed 's/net.bridge.bridge-nf-call-iptables = //g'"`
										if [ $Support_For_LinuxBridge_Filters -ne 1 ]
										then
											read -p "  > This compute node's Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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
										
										Support_For_LinuxBridge_Filters=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sysctl net.bridge.bridge-nf-call-ip6tables | sed 's/net.bridge.bridge-nf-call-ip6tables = //g'"`
										if [ $Support_For_LinuxBridge_Filters -ne 1 ]
										then
											read -p "  > This compute node's Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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
										
										Neutron_Config_File_Remote3="/etc/nova/nova.conf"
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[neutron]/[neutron]\nurl = http:\/\/${default_hostname}:9696\nauth_url = http:\/\/${default_hostname}:5000\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nregion_name = RegionOne\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\n/g' '${Neutron_Config_File_Remote3}'"
										Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote3 | grep -A9 '^\[neutron]' | tail -1 | grep 'password = ${NEUTRON_PASS}' | wc -l"`
										if [ $Control1 -ne 1 ] 
										then
											read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote3}' file. Please check manually. Do you want to continue? [y/n]: " yn
											case $yn in
												[Yy]* ) 
														;;
												[Nn]* )
														echo "Script Aborted"
														exit 1
														break;;
												* ) 	echo " please answer [y]es or [n]o.";;
											esac
										else
											echo " > Configuration changes were done in '${Neutron_Config_File_Remote3}' file successfully."
										fi		
				
										read -p "  > service nova-compute restart. OK?" OK					
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service nova-compute restart"
										sleep 1
										Nova_compute_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'nova-compute' | grep 'active running' | wc -l"`
										if [ $Nova_compute_Service_Status -ge 1 ]
										then
											echo "  > 'nova-compute' Service Status is 'active running'"
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
										
										read -p "  > service neutron-linuxbridge-agent restart. OK?" OK					
										sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service neutron-linuxbridge-agent restart"
										sleep 1
										Nova_compute_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'neutron-linuxbridge-agent' | grep 'active running' | wc -l"`
										if [ $Nova_compute_Service_Status -ge 1 ]
										then
											echo "  > 'neutron-linuxbridge-agent' Service Status is 'active running'"
										else
											read -p "  > 'neutron-linuxbridge-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
										Configured_Nodes_Count=$(($Configured_Nodes_Count + 1))
									fi
								else
									echo " Invalid IP"
								fi
							;;
						
						[Nn]* )						
								echo " > ${Configured_Nodes_Count} Compute Node(s) Configured... "
								echo $Configured_Nodes_Count > /root/.Configured_ComputeNodes_Count
								break
							;;
						* ) 	echo " please answer [y]es or [n]o.";;
					esac
				done
			;;
			
		[Tt]* )
				Success_Flag=0
				if [ -e /root/.Configured_ComputeNodes_Count ] && [ -e /root/.Compute_Node_Info ]
				then
					Configured_Nodes_Count=`cat /root/.Configured_ComputeNodes_Count`
					Info_Control=`more /root/.Compute_Node_Info | wc -l`					
					if [ $Configured_Nodes_Count -gt 0 ] && [ $Info_Control -eq $Configured_Nodes_Count ]
					then
						# Compute Nodes' Information OK
						echo " > ${Configured_Nodes_Count} Compute Node(s) will be configured... "
						Success_Flag=1
					else
						# Compute Nodes' Information Inconsistency 
						read -p " > Count of configured compute nodes seems wierd at file '/root/.Configured_ComputeNodes_Count'. Do yo want to continue? [y/n]" yn
						case $yn in
							[Yy]* )
									Success_Flag=1
									;;
							[Nn]* )
									Success_Flag=0
									;;
							*)		echo " please answer [y]es or [n]o.";;
						esac
					fi						
						
					if [ $Success_Flag -eq 1 ]
					then
						i=1
						while [ $i -le $Configured_Nodes_Count ]
						do
							Remote_Node_IP=`more /root/.Compute_Node_Info | sed "${i}q;d" | awk '{print $1}'`
							Remote_Node_Hostname=`more /root/.Compute_Node_Info | sed "${i}q;d" | awk '{print $2}'`
							#Control for /etc/hosts file
							Hosts_File_Remote_Node_Hostname=`more /etc/hosts | grep "$Remote_Node_Hostname" | awk '{print $2}'`
							if [ "$Hosts_File_Remote_Node_Hostname" == "$Remote_Node_Hostname" ]
							then
								echo "  > The IP '$Remote_Node_IP' was inserted in /etc/hosts file with hostname '${Remote_Node_Hostname}'"
								
							else
								read -p "  > The IP '$Remote_Node_IP' couldn't found in /etc/hosts file. Do you want to insert a record on this node? [y/n] " yn
								case $yn in
									[Yy]* ) echo $Remote_Node_IP" "$Remote_Node_Hostname >> /etc/hosts
											
											Success=`more /etc/hosts | grep "$Remote_Node_IP $Remote_Node_Hostname" | wc -l`
											if [ $Success -ge 1 ]
											then
												echo " Record inserted."
											else
												echo " Record not found. Check /etc/hosts file manually."
											fi
											;;
									[Nn]* )
											echo "Script Aborted"
											exit 1
											;;
									* ) 	echo " please answer [y]es or [n]o.";;
								esac	
							fi


							
							echo " > Compute Node [ IP: $Remote_Node_IP ] with hostname '$Remote_Node_Hostname' will be configured."
							Password_Input
							if [ $? == "2" ]
							then
								echo " Passwords don't match. Exiting..."
							else

								# print status message
								echo " > Installing Neutron Service On Compute Node..."
								while true; do
									read -p " > do you wish to install 'neutron-linuxbridge-agent' service on compute node [y/n]: " yn
									case $yn in
										[Yy]* ) 
												read -p "  > 'neutron-linuxbridge-agent' package will be installed on compute node [ IP: ${Remote_Node_IP} ] OK?" OK
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
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname 'apt -y install neutron-linuxbridge-agent'
												break;;
										[Nn]* ) 
												echo "Installation Aborted"
												exit 1
												break;;
										* ) 	
												echo " please answer [y]es or [n]o.";;
									esac
								done
				
								Neutron_Config_File_Remote1="/etc/neutron/neutron.conf"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/\#connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/g' '$Neutron_Config_File_Remote1'"
								Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep '^#connection = sqlite:////var/lib/neutron/neutron.sqlite' | wc -l"`
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@controller\nauth_strategy = keystone\n/g' '$Neutron_Config_File_Remote1'"
								Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep -A1 '^transport_url = rabbit://openstack:${RabbitMQ_Password}@controller' | tail -1 | grep 'auth_strategy = keystone' | wc -l"`
								Neutron_Config_File_Remote2="/etc/nova/nova.conf"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[keystone_authtoken]/\[keystone_authtoken]\nauth_uri = http:\/\/${default_hostname}:5000\nauth_url = http:\/\/${default_hostname}:5000\nmemcached_servers = ${default_hostname}:11211\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\n/g' '$Neutron_Config_File_Remote1'"
								Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote1} | grep -A9 '^\[keystone_authtoken]' | tail -1 | grep 'password = ${NEUTRON_PASS}' | wc -l"`

								if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ]
								then
									read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote1}' file. Please check manually. Do you want to continue? [y/n]: " yn
									case $yn in
										[Yy]* ) 
												;;
										[Nn]* )
												echo "Script Aborted"
												exit 1
												break;;
										* ) 	echo " please answer [y]es or [n]o.";;
									esac
								else
									echo " > Configuration changes were done in '${Neutron_Config_File_Remote1}' file successfully."
								fi
				
								Neutron_Config_File_Remote2="/etc/neutron/plugins/ml2/linuxbridge_agent.ini"
								MGMT_INTERFACE_IP_REMOTE=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "ifconfig eth1 | grep 'inet addr'" | awk '{print $2}' | sed 's/addr://g'`
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[linux_bridge]/[linux_bridge]\nphysical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}\n/g' '${Neutron_Config_File_Remote2}'"
								Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat ${Neutron_Config_File_Remote2} | grep -A1 '\[linux_bridge]' | tail -1 | grep 'physical_interface_mappings = provider:${PROVIDER_INTERFACE_NAME}' | wc -l"`
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[vxlan]/[vxlan]\nenable_vxlan = true\nlocal_ip = ${MGMT_INTERFACE_IP_REMOTE}\nl2_population = true\n/g' '${Neutron_Config_File_Remote2}'"
								Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote2 | grep -A2 '^\[vxlan]' | tail -1 | grep 'local_ip = ${MGMT_INTERFACE_IP_REMOTE}' | wc -l"`
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[securitygroup]/[securitygroup]\nenable_security_group = true\nfirewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver\n/g' '${Neutron_Config_File_Remote2}'"
								Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote2 | grep -A2 '^\[securitygroup]' | tail -1 | grep 'firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' | wc -l"`
								if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ]
								then
									read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote2}' file. Please check manually. Do you want to continue? [y/n]: " yn
									case $yn in
										[Yy]* ) 
												;;
										[Nn]* )
												echo "Script Aborted"
												exit 1
												break;;
										* ) 	echo " please answer [y]es or [n]o.";;
									esac
								else
									echo " > Configuration changes were done in '${Neutron_Config_File_Remote2}' file successfully."
								fi		
				
								Support_For_LinuxBridge_Filters=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sysctl net.bridge.bridge-nf-call-iptables | sed 's/net.bridge.bridge-nf-call-iptables = //g'"`
								if [ $Support_For_LinuxBridge_Filters -ne 1 ]
								then
									read -p "  > This compute node's Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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
								
								Support_For_LinuxBridge_Filters=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sysctl net.bridge.bridge-nf-call-ip6tables | sed 's/net.bridge.bridge-nf-call-ip6tables = //g'"`
								if [ $Support_For_LinuxBridge_Filters -ne 1 ]
								then
									read -p "  > This compute node's Linux operating system kernel does not support network bridge filters. Do you want to continue? [y/n]: " yn
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
								
								Neutron_Config_File_Remote3="/etc/nova/nova.conf"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[neutron]/[neutron]\nurl = http:\/\/${default_hostname}:9696\nauth_url = http:\/\/${default_hostname}:5000\nauth_type = password\nproject_domain_name = default\nuser_domain_name = default\nregion_name = RegionOne\nproject_name = service\nusername = neutron\npassword = ${NEUTRON_PASS}\n/g' '${Neutron_Config_File_Remote3}'"
								Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Neutron_Config_File_Remote3 | grep -A9 '^\[neutron]' | tail -1 | grep 'password = ${NEUTRON_PASS}' | wc -l"`
								if [ $Control1 -ne 1 ] 
								then
									read -p "  > There is a configuration problem with '${Neutron_Config_File_Remote3}' file. Please check manually. Do you want to continue? [y/n]: " yn
									case $yn in
										[Yy]* ) 
												;;
										[Nn]* )
												echo "Script Aborted"
												exit 1
												break;;
										* ) 	echo " please answer [y]es or [n]o.";;
									esac
								else
									echo " > Configuration changes were done in '${Neutron_Config_File_Remote3}' file successfully."
								fi		
				
								read -p "  > service nova-compute restart. OK?" OK					
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service nova-compute restart"
								sleep 1
								Nova_compute_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'nova-compute' | grep 'active running' | wc -l"`
								if [ $Nova_compute_Service_Status -ge 1 ]
								then
									echo "  > 'nova-compute' Service Status is 'active running'"
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
								
								read -p "  > service neutron-linuxbridge-agent restart. OK?" OK					
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service neutron-linuxbridge-agent restart"
								sleep 1
								Nova_compute_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'neutron-linuxbridge-agent' | grep 'active running' | wc -l"`
								if [ $Nova_compute_Service_Status -ge 1 ]
								then
									echo "  > 'neutron-linuxbridge-agent' Service Status is 'active running'"
								else
									read -p "  > 'neutron-linuxbridge-agent' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
						i=$[$i+1]	
						done
					else
						echo "Script Aborted"
					fi
				else
					# Files Could not found.
					read -p "'/root/.Configured_ComputeNodes_Count' or '/root/.Compute_Node_Info' file could not found. Do you want to continue? [y/n]" yn
					case $yn in
						[Yy]* ) 
								;;
						[Nn]* )
								echo "Script Aborted"
								;;
						* ) 	echo " please answer [y]es or [n]o.";;
					esac
				fi
			;;
		* ) 	echo " please answer [t]hem or [o]thers."
			;;
	esac

	cd /home/${default_hostname}
	if [ -e /home/${default_hostname}/admin-openrc ]
	then
		. admin-openrc
	else
		read -p "  > /home/${default_hostname}/admin-openrc could not be found. Do you want to continue? [y/n]: " yn
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

	openstack network agent list >> /root/.agent_list
	openstack network agent list
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use neutron;
select count(*) from neutron.agents;
exit
EOF_SQL`
	Agent_Count=`more $working_directory/tmp_file | tail -1`
	Control=$(($Configured_Nodes_Count + 4))
	if [ $Agent_Count -eq $Control ]
	then
		echo "  > 'openstack network agent list' command returned a successfull result."
	else
		read -p "  > 'openstack network agent list' command didn't return a successfull result.. Do you want to continue? [y/n]: " yn
		case $yn in
			[Yy]* ) 
					;;
			[Nn]* )
					echo "Script Aborted"
					exit 1
					;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	fi
	rm -f $working_directory/tmp_file
	

read -p "  > FINISHED... Press ENTER to see the server and OpenStack services' status. OK?" OK
/etc/update-motd.d/05-systeminfo
/etc/update-motd.d/90-updates-available
/etc/update-motd.d/98-reboot-required

fi


