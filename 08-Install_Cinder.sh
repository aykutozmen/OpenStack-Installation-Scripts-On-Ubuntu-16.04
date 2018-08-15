#!/bin/bash
#set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
default_username=$default_hostname
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | Before starting step 2 be sure that Controller node can connect to block storage node via SSH and block storage     |"
echo " | node's info is added to known hosts file.                                                                           |"
echo " | This script will do:                                                                                                |"
echo " | 1.  Management IP Existence Control in '/etc/hosts' File                                                            |"
echo " | 2.  Connect & Configure A Block Storage Node                                                                        |"
echo " |        a. IP & Hostname Control Of Block Storage Node                                                               |"
echo " |        b. Input Password Of Block Storage Node For SSH Connection                                                   |"
echo " |        c. Install 'lvm' and 'thin-provisioning-tools' Packages On Block Storage Node                                |"
echo " |        d. Create A Disk Volume Named 'cinder-volumes'                                                               |"
echo " |        d. Install 'cinder-volume' Package On Block Storage Node                                                     |"
echo " |        e. Configure 'cinder-volume' Service On Block Storage Node                                                   |"
echo " | 3.  Create Mysql DB Cinder Database & Users                                                                         |"
echo " | 4.  Create 'cinder' User                                                                                            |"
echo " | 5.  Create 'cinderv2' and 'cinderv3' Service Entities                                                               |"
echo " | 6.  Create Cinder Service API Endpoints For volumev2 And volumev3                                                   |"
echo " | 7.  Install Cinder Services ('cinder-api' and 'cinder-scheduler' Packages)                                          |"
echo " | 8.  Cinder Configuration                                                                                            |"
echo " | 9.  Populate Cinder Service Databases                                                                               |"
echo " | 10. Connect & Configure A Block Storage Node For Backup Service                                                     |"
echo " |        a. Install 'cinder-backup' Package On Block Storage Node                                                     |"
echo " |        b. Configure 'cinder-backup' Service On Block Storage Node                                                   |"
echo " | 11. Verify Installation                                                                                             |"
echo " | 12. Show Server Status Summary                                                                                      |"
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
HOSTS_IP=`more /etc/hosts | grep -w ${hostname} | awk '{print $1}'`
MGMT_INTERFACE_IP=`more /etc/hosts | grep -w ${default_hostname} | awk '{print $1}'`

if [ "$HOSTS_IP" != "$MGMT_INTERFACE_IP" ]
then
	read -ep " > IP address of this server is not inserted correctly in /etc/hosts file. Do you want to continue? [y/n]: " yn
	case $yn in
		[Yy]* ) 
				;;
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
	
############################## CONFIGURATION OF BLOCK STORAGE NODES:

Configured_Nodes_Count=0

IP_Input() {
	read -p "  > Please enter IP address of the block storage node that will be configured:" Node_IP
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
	read -sp "  > Please enter root password to get connection of the block storage node that will be configured:" Node_Password
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
	read -p " > Do you want to configure a block storage node? [y/n]: " yn
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
										read -p "  > Please enter the hostname of block storage node: " Remote_Node_Hostname
										
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

						SuccessFlag=0
						# print status message
						echo " > Installing Cinder Block Storage Service On Storage Node..."
						read -p "  > 'lvm2' and 'thin-provisioning-tools' packages will be installed. OK?" OK
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "apt -y install lvm2 thin-provisioning-tools"
						Result1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "dpkg -l lvm2 | grep 'lvm2' | grep 'Linux Logical Volume Manager' | wc -l"`
						Result2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "dpkg -l thin-provisioning-tools | grep 'thin-provisioning-tools' | grep 'Tools for handling thinly provisioned device-mapper meta-data' | wc -l"`
						if [ $Result1 -eq 1 ] && [ $Result2 -eq 1 ]
						then
							SuccessFlag=1
						else
							SuccessFlag=0
						fi

						if [ $SuccessFlag -eq 1 ]
						then
							IP_REMOTE=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "ifconfig eth1 | grep 'inet addr'"`
							MGMT_INTERFACE_IP_REMOTE=`echo $IP_REMOTE | awk '{print $2}' | sed 's/addr://g'`
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "fdisk -l | grep '/dev/sd' | grep 'sectors'" > /root/temp_file
							Disk_Count=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "fdisk -l | grep '/dev/sd' | grep 'sectors' | awk -F' ' '{print $2}' | awk -F':' '{print $1}' | wc -l"`
							i=0
							while true; do
								if [ $i -eq $Disk_Count ]
								then
									break
								else
									i=$((i+1))
									Disk_Name=`cat /root/temp_file | head -$i | tail -1 | awk '{print $2}' | tr -d ':'`

									read -ep " > Do you want to create volume for $Disk_Name? [y/n]: " yn
									case $yn in
										[Yy]* ) 
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/sbin/pvcreate $Disk_Name >> /root/Result_pvcreate 2>&1"
												Result=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/Result_pvcreate | grep -e 'successfully created' -e 'Physical volume' | wc -l"`
												if [ $Result -ne 1 ]
												then
													echo "  > $Disk_Name Volume couldn't created successfully."
												fi
												sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "rm -f /root/Result_pvcreate"
												Flag=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "fdisk -l | grep $Disk_Name | grep -v sectors | wc -l"`
												if [ $Flag -eq 0 ]
												then
													sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo $Disk_Name' ' >> /root/.Volume_Candidates"
												fi
												;;
										[Nn]* )
												echo "  > $Disk_Name Volume not created."
												;;
										* ) 	echo " please answer [y]es or [n]o.";;
									esac
								fi
							done
							
							Volumes=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/.Volume_Candidates | tr '\n' ' '"`
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/sbin/vgremove cinder-volumes >> /dev/null 2>&1"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/sbin/vgcreate cinder-volumes $Volumes >> /root/Result_vgcreate"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/Result_vgcreate"
							Result=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/Result_vgcreate | grep -e 'successfully created' -e 'Volume group' | wc -l"`
							if [ $Result -ne 1 ]
							then
								echo "  > Volume group named 'cinder-volumes' couldn't created successfully."
							else
								i=0
								String_To_Be_Inserted="filter = [ "
								Disk_Count=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/.Volume_Candidates | wc -l"`
								while true; do
									if [ $i -eq $Disk_Count ]
									then
										break
									else
										i=$((i+1))
										Disk_Name=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat /root/.Volume_Candidates | head -$i | tail -1 | sed 's/\/dev\///'"`
										if [ $Disk_Name != '' ]
										then
											String_To_Be_Inserted=$String_To_Be_Inserted'"a/'$Disk_Name'/", '
										fi
									fi
								done
								String_To_Be_Inserted=$String_To_Be_Inserted'"r/.*/"]'
							fi
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/bin/rm -f /root/Result_vgcreate"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "/bin/rm -f /root/.Volume_Candidates"
							/bin/rm -f /root/temp_file
							LVM_Config_File="/etc/lvm/lvm.conf"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's|devices \{|devices \{\n\t${String_To_Be_Inserted}|g' '$LVM_Config_File'"
						else
							read -p "  > 'lvm2' or 'thin-provisioning-tools' packages couldn't be installed. OK?" OK
						fi

						read -p "  > 'cinder-volume' package will be installed. OK?" OK
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "apt -y install cinder-volume"
						Result1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "dpkg -l cinder-volume | grep 'cinder-volume' | grep 'Cinder storage service' | wc -l"`
						if [ $Result1 -eq 1 ]
						then
							SuccessFlag=1
						else
							SuccessFlag=0
						fi

						if [ $SuccessFlag -eq 1 ]
						then
							read -sp "  > Please enter CINDER_DBPASS preferred password: " password
							printf "\n"
							read -sp "  > confirm your preferred password: " password2
							printf "\n"

							# check if the passwords match to prevent headaches
							if [[ "$password" != "$password2" ]]; then
								echo " your passwords do not match; please restart the script and try again"
								echo
								exit 1
							else
								CINDER_DBPASS=$password
							fi
							read -sp "  > Please enter CINDER_PASS preferred password: " password
							printf "\n"
							read -sp "  > confirm your preferred password: " password2
							printf "\n"

							# check if the passwords match to prevent headaches
							if [[ "$password" != "$password2" ]]; then
								echo " your passwords do not match; please restart the script and try again"
								echo
								exit 1
							else
								CINDER_PASS=$password
							fi

							Cinder_Config_File_Remote="/etc/cinder/cinder.conf"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^connection = sqlite:\/\/\/\/var\/lib\/cinder\/cinder.sqlite/connection = mysql+pymysql:\/\/cinder:${CINDER_DBPASS}@${default_hostname}\/cinder/g' '$Cinder_Config_File_Remote'"
							Control1=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A1 '^\[database]' | tail -1 | grep 'connection = mysql+pymysql://cinder:${CINDER_DBPASS}@${default_hostname}/cinder' | wc -l"`
							# 1
							Control2=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep 'auth_strategy = keystone' | wc -l"`
							# 1
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo >> $Cinder_Config_File_Remote"
							
							Keystone_Configured=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A9 '^\[keystone_authtoken]' | tail -1 | grep 'password = ${CINDER_PASS}' | wc -l"`
							if [ $Keystone_Configured -eq 0 ]
							then
								# Keystone section needs to be configured				
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo '[keystone_authtoken]' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'auth_uri = http://${default_hostname}:5000' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'auth_url = http://${default_hostname}:5000' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'memcached_servers = ${default_hostname}:11211' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'auth_type = password' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'project_domain_id = default' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'user_domain_id = default' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'project_name = service' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'username = cinder' >> $Cinder_Config_File_Remote"
								sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'password = ${CINDER_PASS}' >> $Cinder_Config_File_Remote"
							fi
							Control3=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A9 '^\[keystone_authtoken]' | tail -1 | grep 'password = ${CINDER_PASS}' | wc -l"`
							# 1
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\nmy_ip = ${MGMT_INTERFACE_IP_REMOTE}/g' '$Cinder_Config_File_Remote'"
							Control4=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep 'my_ip = ${MGMT_INTERFACE_IP_REMOTE}' | wc -l"`
							# 1
							RabbitMQ_Password=`more /root/.RabbitMQ_User_Password`
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@${default_hostname}/g' '$Cinder_Config_File_Remote'"
							Control5=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep 'transport_url = rabbit://openstack:${RabbitMQ_Password}@${default_hostname}' | wc -l"`
							# 1
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo '' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo '[lvm]' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'volume_group = cinder-volumes' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'iscsi_protocol = iscsi' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'iscsi_helper = tgtadm' >> $Cinder_Config_File_Remote"
							Control6=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A4 '^\[lvm]' | tail -1 | grep 'iscsi_helper = tgtadm' | wc -l"`
							# 1
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/enabled_backends = lvm/enabled_backends = lvm\nglance_api_servers = http:\/\/${default_hostname}:9292\n/g' '$Cinder_Config_File_Remote'"
							Control7=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -e 'enabled_backends = lvm' -e 'glance_api_servers = http://${default_hostname}:9292' | wc -l"`
							# 2
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo '' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo '[oslo_concurrency]' >> $Cinder_Config_File_Remote"
							sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "echo 'lock_path = /var/lib/cinder/tmp' >> $Cinder_Config_File_Remote"
							Control8=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A1 '^\[oslo_concurrency]' | tail -1 | grep 'lock_path = /var/lib/cinder/tmp' | wc -l"`
							# 1
							if [ $Control1 -eq 1 ] && [ $Control2 -eq 1 ] && [ $Control3 -eq 1 ] && [ $Control4 -eq 1 ] && [ $Control5 -eq 1 ] && [ $Control6 -eq 1 ] && [ $Control7 -eq 2 ] && [ $Control8 -eq 1 ]
							then
								echo " > Configuration changes were done in '${Cinder_Config_File_Remote}' file successfully."
							else
								read -p "  > There is a configuration problem with '${Cinder_Config_File_Remote}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
						else
							read -p "  > 'cinder-volume' package couldn't be installed. OK?" OK
						fi
						
						echo " > 'tgt' Service will be restarted..."
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service tgt restart"
						sleep 1
						Service_tgt() {
						tgt_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'tgt' | grep 'active running' | wc -l"`
						if [ $tgt_Service_Status -ge 1 ]
						then
							echo "  > 'tgt' Service Status is 'active running'"
						else
							read -p "  > 'tgt' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
						Service_tgt
						
						echo " > 'cinder-volume' Service will be restarted..."
						sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service cinder-volume restart"
						sleep 1
						Service_cinder_volume() {
						Cinder_Volume_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'cinder-volume' | grep 'active running' | wc -l"`
						if [ $Cinder_Volume_Service_Status -ge 1 ]
						then
							echo "  > 'cinder-volume' Service Status is 'active running'"
						else
							read -p "  > 'cinder-volume' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
						Service_cinder_volume
						if [ $Cinder_Volume_Service_Status -eq 1 ] && [ $tgt_Service_Status -eq 1 ]
						then
							echo $Node_IP" "$Remote_Node_Hostname" "$Node_Password >> /root/.Storage_Node_Info
							Configured_Nodes_Count=$(($Configured_Nodes_Count + 1))
						fi
					fi
				fi
				;;
		[Nn]* )
				echo " > ${Configured_Nodes_Count} Block Storage Node(s) Configured. Script Will Continue to Configure Controller Node... "
				echo $Configured_Nodes_Count > /root/.Configured_BlockStorage_Nodes_Count
				break;;
		* ) 	echo " please answer [y]es or [n]o.";;
	esac	
done

############################## CONFIGURATION OF CONTROLLER NODE:

# print status message
echo " > Creating Mysql DB Cinder Database & User..."

Mysql_Service_Status=`systemctl | grep mysql | grep "active running" | wc -l`
if [ $Mysql_Service_Status -ge 1 ]
then
	echo "  > Mysql Service Status is 'active running'"

SQL_Output=`mysql -u root <<EOF_SQL
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '${CINDER_DBPASS}';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '${CINDER_DBPASS}';
FLUSH PRIVILEGES;
exit
EOF_SQL`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from mysql.user where User='cinder';
exit
EOF_SQL`
Cinder_User_Count=`echo $SQL_Output | awk '{print $2}'`
	if [ $Cinder_User_Count == 2 ]
	then
		echo "  > 'cinder' users created successfully with password '$CINDER_DBPASS'"
	else
		echo "  > 'cinder' users not found in mysql database"
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
				;;
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
echo " > Creating OpenStack 'cinder' User..."
openstack user create --domain default --password-prompt cinder >> ${working_directory}/cinder_user
CinderUserEnabled=`more ${working_directory}/cinder_user | head -5 | tail -1 | awk '{print $4}'`
CinderUserID=`more ${working_directory}/cinder_user | head -6 | tail -1 | awk '{print $4}'`
SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.user where id='$CinderUserID';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ]
then
	echo "  > 'cinder' user is created successfully."
else
	read -p "  > 'cinder' could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/cinder_user

openstack role add --project service --user cinder admin

# print status message
echo " > Creating 'cinder' service entity..."
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2 >> ${working_directory}/cinder_service
Cinder_Service_Enabled=`more ${working_directory}/cinder_service | head -5 | tail -1 | awk '{print $4}'`
if [ $Cinder_Service_Enabled == "True" ]
then
	echo "  > 'cinderv2' service entity is created successfully."
else
	read -p "  > 'cinderv2' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/cinder_service

openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3 >> ${working_directory}/cinder_service
Cinder_Service_Enabled=`more ${working_directory}/cinder_service | head -5 | tail -1 | awk '{print $4}'`
if [ $Cinder_Service_Enabled == "True" ]
then
	echo "  > 'cinderv3' service entity is created successfully."
else
	read -p "  > 'cinderv3' service entity could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/cinder_service

# print status message
echo " > Creating Cinder Service API Endpoints..."
openstack endpoint create --region RegionOne volumev2 public http://${default_hostname}:8776/v2/%\(project_id\)s >> ${working_directory}/public_api
Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`


SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
then
	echo "  > Public endpoint API for volumev2 is created successfully."
else
	read -p "  > Public endpoint API for volumev2 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/public_api


openstack endpoint create --region RegionOne volumev2 internal http://${default_hostname}:8776/v2/%\(project_id\)s >> ${working_directory}/internal_api
Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
then
	echo "  > Internal endpoint API for volumev2 is created successfully."
else
	read -p "  > Internal endpoint API for volumev2 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/internal_api


openstack endpoint create --region RegionOne volumev2 admin http://${default_hostname}:8776/v2/%\(project_id\)s >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
then
	echo "  > Admin endpoint API for volumev2 is created successfully."
else
	read -p "  > Admin endpoint API for volumev2 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/admin_api

openstack endpoint create --region RegionOne volumev3 public http://${default_hostname}:8776/v3/%\(project_id\)s >> ${working_directory}/public_api
Public_API_ID=`more ${working_directory}/public_api | head -5 | tail -1 | awk '{print $4}'`
Public_API_Enabled=`more ${working_directory}/public_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Public_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Public_API_Enabled == "True" ]
then
	echo "  > Public endpoint API for volumev3 is created successfully."
else
	read -p "  > Public endpoint API for volumev3 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/public_api

openstack endpoint create --region RegionOne volumev3 internal http://${default_hostname}:8776/v3/%\(project_id\)s >> ${working_directory}/internal_api
Internal_API_ID=`more ${working_directory}/internal_api | head -5 | tail -1 | awk '{print $4}'`
Internal_API_Enabled=`more ${working_directory}/internal_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Internal_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Internal_API_Enabled == "True" ]
then
	echo "  > Internal endpoint API for volumev3 is created successfully."
else
	read -p "  > Internal endpoint API for volumev3 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/internal_api

openstack endpoint create --region RegionOne volumev3 admin http://${default_hostname}:8776/v3/%\(project_id\)s >> ${working_directory}/admin_api
Admin_API_ID=`more ${working_directory}/admin_api | head -5 | tail -1 | awk '{print $4}'`
Admin_API_Enabled=`more ${working_directory}/admin_api | head -4 | tail -1 | awk '{print $4}'`

SQL_Output=`mysql -u root <<EOF_SQL
use mysql;
select count(*) from keystone.endpoint where id = '${Admin_API_ID}' and url like 'http://${default_hostname}:8776%';
exit
EOF_SQL`
SQL_cinder_User_Id=`echo $SQL_Output | awk '{print $2}'`

if [ $SQL_cinder_User_Id == 1 ] && [ $Admin_API_Enabled == "True" ]
then
	echo "  > Admin endpoint API for volumev3 is created successfully."
else
	read -p "  > Admin endpoint API for volumev3 could not be created successfully. Do you want to continue? [y/n]: " yn
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
rm -f ${working_directory}/admin_api

# print status message
echo " > Installing Cinder Service..."
while true; do
    read -p " > do you wish to install cinder service on this node? [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p "  > 'cinder-api' and 'cinder-scheduler' packages will be installed. OK?" OK
				apt -y install cinder-api cinder-scheduler
				break;;
        [Nn]* ) 
                echo "Installation Aborted"
				exit 1
				break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

Service_cinder_api() {
Cinder_Api_Service_Status=`systemctl | grep 'cinder-api' | grep 'active running' | wc -l`
if [ $Cinder_Api_Service_Status -ge 1 ]
then
	echo "  > 'cinder-api' Service Status is 'active running'"
else
	read -p "  > 'cinder-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
sleep 2
Service_cinder_api

Service_cinder_scheduler() {
Cinder_Scheduler_Service_Status=`systemctl | grep 'cinder-scheduler' | grep 'active running' | wc -l`
if [ $Cinder_Scheduler_Service_Status -ge 1 ]
then
	echo "  > 'cinder-scheduler' Service Status is 'active running'"
else
	read -p "  > 'cinder-scheduler' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
sleep 2
Service_cinder_scheduler

# print status message
Cinder_Config_File="/etc/cinder/cinder.conf"
echo " > Cinder Configuration On Controller Node. Config File: "$Cinder_Config_File

sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/cinder\/cinder.sqlite/connection = mysql+pymysql:\/\/cinder:${CINDER_DBPASS}@${default_hostname}\/cinder/g" "$Cinder_Config_File"
Control1=`cat $Cinder_Config_File | grep "connection = mysql+pymysql://cinder:${CINDER_DBPASS}@${default_hostname}/cinder" | wc -l`
# 1
RabbitMQ_Password=`more /root/.RabbitMQ_User_Password`
echo "MGMT_INTERFACE_IP="$MGMT_INTERFACE_IP
sed -i -r "s/^\[DEFAULT]/\[DEFAULT]\ntransport_url = rabbit:\/\/openstack:${RabbitMQ_Password}@${default_hostname}\nauth_strategy = keystone\nmy_ip = ${MGMT_INTERFACE_IP}/g" "${Cinder_Config_File}"
Control2=`cat $Cinder_Config_File | grep -A3 "^\[DEFAULT]" | tail -1 | grep "my_ip = ${MGMT_INTERFACE_IP}" | wc -l`
# 1
echo "" >> ${Cinder_Config_File}
echo "[keystone_authtoken]" >> ${Cinder_Config_File}
echo "auth_uri = http://${default_hostname}:5000">> ${Cinder_Config_File}
echo "auth_url = http://${default_hostname}:5000">> ${Cinder_Config_File}
echo "memcached_servers = ${default_hostname}:11211">> ${Cinder_Config_File}
echo "auth_type = password">> ${Cinder_Config_File}
echo "project_domain_id = default">> ${Cinder_Config_File}
echo "user_domain_id = default">> ${Cinder_Config_File}
echo "project_name = service">> ${Cinder_Config_File}
echo "username = cinder">> ${Cinder_Config_File}
echo "password = ${CINDER_PASS}">> ${Cinder_Config_File}
Control3=`cat $Cinder_Config_File | grep -A9 "^\[keystone_authtoken]" | tail -1 | grep "password = ${CINDER_PASS}" | wc -l`
# 1
echo "" >> ${Cinder_Config_File}
echo "[oslo_concurrency]" >> ${Cinder_Config_File}
echo "lock_path = /var/lib/cinder/tmp" >> ${Cinder_Config_File}
Control4=`cat $Cinder_Config_File | grep -A1 "^\[oslo_concurrency]" | tail -1 | grep "lock_path = /var/lib/cinder/tmp" | wc -l`
# 1

if [ $Control1 -eq 1 ] && [ $Control2 -eq 1 ] && [ $Control3 -eq 1 ] && [ $Control4 -eq 1 ]
then
	echo " > Configuration changes were done in '${Cinder_Config_File}' file successfully."
else
	read -p "  > There is a configuration problem with '${Cinder_Config_File}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
	
# print status message
echo " > Populate Cinder Service Database..."
while true; do
    read -p " > do you wish to populate cinder database [y/n]: " yn
    case $yn in
        [Yy]* ) 
				su -s /bin/sh -c "cinder-manage db sync" cinder
SQL_Output=`mysql -u root <<EOF_SQL >> $working_directory/tmp_file
use cinder;
SHOW TABLES;
SELECT FOUND_ROWS();
exit
EOF_SQL`
				Table_Count=`more $working_directory/tmp_file | tail -1`
				if [ $Table_Count -eq 35 ]
				then
					echo "  > 'cinder' database tables were created successfully."
				else
					read -p "  > 'cinder' database tables not found or missing. Do you want to continue? [y/n]: " yn
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
				;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done	
rm -f $working_directory/tmp_file

Nova_Config_File="/etc/nova/nova.conf"
echo " > Cinder Configuration On Controller Node. Config File: "$Nova_Config_File

sed -i -r "s/^\[cinder]/\[cinder]\nos_region_name = RegionOne\n/g" "$Nova_Config_File"

# print status message
echo " > 'nova-api' Service will be restarted..."
service nova-api restart
Service_nova_api() {
Nova_Api_Service_Status=`systemctl | grep 'nova-api' | grep 'active running' | wc -l`
if [ $Nova_Api_Service_Status -ge 1 ]
then
	echo "  > 'nova-api' Service Status is 'active running'"
else
	read -p "  > 'nova-api' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
sleep 1
Service_nova_api

# print status message
echo " > 'cinder-scheduler' Service will be restarted..."
service cinder-scheduler restart
sleep 1
Service_cinder_scheduler

# print status message
echo " > 'apache2' Service will be restarted..."
service apache2 restart
Service_apache2() {
Apache2_Service_Status=`systemctl | grep 'apache2' | grep 'active running' | wc -l`
if [ $Apache2_Service_Status -ge 1 ]
then
	echo "  > 'apache2' Service Status is 'active running'"
else
	read -p "  > 'apache2' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
sleep 1
Service_apache2

############################## INSTALLATION AND CONFIGURATION OF BACKUP SERVICE ON BLOCK STORAGE NODE(S):

read -p " > Do you want to install and configure the backup service on block storage node(s)? [y/n]: " yn
case $yn in
	[Yy]* ) 
			Configured_Nodes_Count=`cat /root/.Configured_BlockStorage_Nodes_Count`
			echo " > You have configured "${Configured_Nodes_Count}" block storage node(s). Node(s) Information:"
			cat /root/.Storage_Node_Info | while read line
			do
				echo "	Block Storage Node IP and hostname: "`echo $line | awk '{print $1}'`" - "`echo $line | awk '{print $2}'`
			done
			cat /root/.Storage_Node_Info | while read line
			do
				Node_IP=`echo $line | awk '{print $1}'`
				Remote_Node_Hostname=`echo $line | awk '{print $2}'`
				Node_Password=`echo $line | awk '{print $3}'`
				echo " > Installing backup service on node IP: '"$Node_IP"' which has hostname: '"$Remote_Node_Hostname"'"
				sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "apt -y install cinder-backup"
					
				Result=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "dpkg -l cinder-backup | grep 'cinder-backup' | grep 'Cinder storage service - Scheduler server' | wc -l"`
				if [ $Result -eq 1 ]
				then
					SuccessFlag=1
				else
					SuccessFlag=0
				fi

				if [ $SuccessFlag -eq 1 ]
				then
					Cinder_Config_File_Remote="/etc/cinder/cinder.conf"
					echo " > Cinder Configuration On Block Storage Node. Config File: "$Node_IP":"$Cinder_Config_File_Remote
					sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "sed -i -r 's/^\[DEFAULT]/[DEFAULT]\nbackup_driver = cinder.backup.drivers.swift\nbackup_swift_url = http:\/\/${default_hostname}:8080\/v1/g' '$Cinder_Config_File_Remote'"  #SWIFT_URL will be replaced after object storage installation. Look : https://docs.openstack.org/cinder/queens/install/cinder-backup-install-ubuntu.html
					Control=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "cat $Cinder_Config_File_Remote | grep -A1 'backup_driver = cinder.backup.drivers.swift' | tail -1 | grep 'backup_swift_url = http' | wc -l"`
					if [ $Control -eq 1 ]
					then
						echo " > Configuration changes were done in '${Cinder_Config_File_Remote}' file successfully."
					else
						read -p "  > There is a configuration problem with '${Cinder_Config_File_Remote}' file. Please check 'backup_driver' and 'backup_swift_url' parameters under DEFAULT section. Do you want to continue? [y/n]: " yn
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
					echo " > 'cinder-backup' Service will be restarted..."
					sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service cinder-backup restart"
					sleep 1
					Service_cinder_backup() {
					cinder_backup_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'cinder-backup' | grep 'active running' | wc -l"`
					if [ $cinder_backup_Service_Status -ge 1 ]
					then
						echo "  > 'cinder-backup' Service Status is 'active running'"
					else
						read -p "  > 'cinder-backup' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
					Service_cinder_backup				
					
					echo " > 'cinder-volume' Service will be restarted..."
					sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "service cinder-volume restart"
					sleep 3
					Service_cinder_volume() {
					cinder_volume_Service_Status=`sshpass -p $Node_Password ssh root@$Remote_Node_Hostname "systemctl | grep 'cinder-volume' | grep 'active running' | wc -l"`
					if [ $cinder_volume_Service_Status -ge 1 ]
					then
						echo "  > 'cinder-volume' Service Status is 'active running'"
					else
						read -p "  > 'cinder-volume' Service Status is not 'active running'. Do you want to continue? [y/n]: " yn
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
					Service_cinder_volume						
				else
					read -p "  > 'cinder-backup' package couldn't be installed. OK?" OK
				fi
			done
			;;
	[Nn]* )
			echo " > ${Configured_Nodes_Count} Block Storage Node(s) Configured. Script Will Continue to Configure Controller Node... "
			echo $Configured_Nodes_Count > /root/.Configured_BlockStorage_Nodes_Count
			break;;
	* ) 	echo " please answer [y]es or [n]o.";;
esac	

############################## VERIFICATION:

if [ -e /home/${default_username}/admin-openrc ]
then
	. /home/${default_hostname}/admin-openrc
	openstack volume service list
	openstack volume service list >> /root/.volume_service_list
	Head_Count=$((5 + $Configured_Nodes_Count))
	Tail_Count=$((2 + $Configured_Nodes_Count))
	Volume_Service_List=`more /root/.volume_service_list | head -${Head_Count} | tail -${Tail_Count} | awk '{print $10}' | grep "up" | wc -l`
	if [ $Volume_Service_List -eq $Tail_Count ]
	then
		echo "  > 'openstack volume service list' command returned a successfull result. All services' state is 'UP'."
	else
		read -p "  > 'openstack volume service list' command didn't return a successfull result.. Do you want to continue? [y/n]: " yn
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
	rm -f /root/.volume_service_list
else
	read -p "  > /home/${default_username}/admin-openrc could not be found. Do you want to continue? [y/n]: " yn
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
		
read -p "  > Press ENTER to see the server and OpenStack services' status. OK?" OK
/etc/update-motd.d/05-systeminfo
/etc/update-motd.d/90-updates-available
/etc/update-motd.d/98-reboot-required		

fi





