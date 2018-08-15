#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
default_username=$default_hostname
clear

echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | This script will do:                                                                                                |"
echo " | 1. Management IP Existence Control in '/etc/hosts' File                                                             |"
echo " | 2. Install Dashboard (Horizon)                                                                                      |"
echo " | 3. Horizon Configuration (Netas-Logo.svg file should be in the same directory where this script runs)               |"
echo " | 4. Finalize Installation                                                                                            |"
echo " | 5. Show Server Status Summary                                                                                       |"
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
	
	SuccessFlag=0
	echo " > Installing Horizon Dashboard..."
	while true; do
		read -p " > do you wish to install Horizon Dashboard [y/n]: " yn
		case $yn in
			[Yy]* ) 
					read -p "  > 'openstack-dashboard' package will be installed. OK?" OK
					apt -y install openstack-dashboard
					Result=`dpkg -l openstack-dashboard | grep "openstack-dashboard" | grep "Django web interface for OpenStack" | wc -l`
					if [ $Result -eq 1 ]
					then
						SuccessFlag=1
					else
						SuccessFlag=0
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

	if [ $SuccessFlag -eq 1 ]
	then
		Horizon_Config_File="/etc/openstack-dashboard/local_settings.py" #CONTROLLER
		sed -i -r "s/^OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"${default_hostname}\"/g" "$Horizon_Config_File"
		Control1=`cat $Horizon_Config_File | grep "OPENSTACK_HOST = \"${default_hostname}\"" | wc -l`
		sed -i -r "s/#ALLOWED_HOSTS = \['horizon.example.com', \]/ALLOWED_HOSTS = \['*'\]/g" "$Horizon_Config_File"
		Control2=`cat $Horizon_Config_File | grep "^ALLOWED_HOSTS = \['\*']" | wc -l`
		sed -i -r "s/^CACHES = \{/SESSION_ENGINE = 'django.contrib.sessions.backends.cache'\n\nCACHES = \{/g" "$Horizon_Config_File"
		sed -i -r "s/^    'default': \{/    'default': \{/g" "$Horizon_Config_File"
		sed -i -r "s/^        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',/        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',/g" "$Horizon_Config_File"
		sed -i -r "s/^        'LOCATION': '127.0.0.1:11211',/        'LOCATION': '${default_hostname}:11211',/g" "$Horizon_Config_File"
		Control3=`cat $Horizon_Config_File | grep -A7 "SESSION_ENGINE = 'django.contrib.sessions.backends.cache'" | tail -1 | grep "}" | wc -l`
		Control4=`cat $Horizon_Config_File | grep -A7 "SESSION_ENGINE = 'django.contrib.sessions.backends.cache'" | tail -3 | head -1 | grep "        'LOCATION': '${default_hostname}:11211'," | wc -l`
		Control5=`cat $Horizon_Config_File | grep 'OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST' | wc -l`
		Choice="Yes"
		read -ep " > Do you want to enable Keystone Multidomain Support? [ Default: Yes ] [y/n]: " yn
		if [ -z "$yn" ]; then Choice="Yes"; fi
		case $yn in
			[Yy]* ) 
					Choice="Yes"
					;;
			[Nn]* )
					Choice="No"
					;;
			* ) 	
					echo " Answer will be accepted as 'No'"
					Choice="No"
					;;
		esac
		if [ $Choice == "Yes" ]
		then
			sed -i -r "s/^#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/g" "$Horizon_Config_File"
			Control6=`cat $Horizon_Config_File | grep 'OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True' | wc -l`
		else
			sed -i -r "s/^#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False/g" "$Horizon_Config_File"
			Control6=`cat $Horizon_Config_File | grep 'OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False' | wc -l`
		fi
		sed -i -r "s/^#OPENSTACK_API_VERSIONS = \{/OPENSTACK_API_VERSIONS = \{\n    \"identity\": 3,\n    \"image\": 2,\n    \"volume\": 2,\n\}/g" "$Horizon_Config_File"
		Control7=`cat $Horizon_Config_File | grep -A4 "^OPENSTACK_API_VERSIONS = {" | tail -1 | grep "}" | wc -l`
		Control8=`cat $Horizon_Config_File | grep -A4 "^OPENSTACK_API_VERSIONS = {" | tail -2 | head -1 | grep "    \"volume\": 2," | wc -l`
		sed -i -r "s/^#OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'Default'/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"/g" "$Horizon_Config_File"
		Control9=`cat $Horizon_Config_File | grep 'OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"' | wc -l`
		sed -i -r "s/^OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"_member_\"/OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"/g" "$Horizon_Config_File"
		Control10=`cat $Horizon_Config_File | grep 'OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"' | wc -l`
		read -p " > Please insert time zone information. Options listed in 'https://en.wikipedia.org/wiki/List_of_time_zone_abbreviations' [Default=UTC]: " TimeZone
		if [ -z "$TimeZone" ]; then TimeZone="UTC"; fi
		sed -i -r "s/^TIME_ZONE = \"UTC\"/TIME_ZONE = \"${TimeZone}\"/g" "$Horizon_Config_File"
		Control11=`cat $Horizon_Config_File | grep "^TIME_ZONE = \"${TimeZone}\"" | wc -l`
		
		#Configure Defult Theme as 'default':
		sed -i -r "s/^#AVAILABLE_THEMES = \[/AVAILABLE_THEMES = \[\n    ('default', 'Gray', 'themes\/default'),\n    ('material', 'Material', 'themes\/material'),\n    ('ubuntu', 'Ubuntu', 'themes\/ubuntu'),\n]\n/g" "$Horizon_Config_File"
		sed -i "s/^#    ('default', 'Default', 'themes\/default'),//g" "$Horizon_Config_File"
		sed -i "s/^#    ('material', 'Material', 'themes\/material'),//g" "$Horizon_Config_File"
		sed -i -r "/^#]/ d" "$Horizon_Config_File"
		sed -i -r "s/^DEFAULT_THEME = 'ubuntu'/DEFAULT_THEME = 'default'/g" "$Horizon_Config_File"
		Control12=`cat $Horizon_Config_File | grep -A4 "^AVAILABLE_THEMES = \[" | grep -e material -e default -e ubuntu | wc -l`
		
		if [ $Control1 -ne 1 ] || [ $Control2 -ne 1 ] || [ $Control3 -ne 1 ] || [ $Control4 -ne 1 ] || [ $Control5 -ne 1 ] || [ $Control6 -ne 1 ] || [ $Control7 -ne 1 ] || [ $Control8 -ne 1 ] || [ $Control9 -ne 1 ] || [ $Control10 -ne 1 ] || [ $Control11 -ne 1 ] || [ $Control12 -ne 3 ]
		then
			read -p "  > There is a configuration problem with '${Horizon_Config_File}' file. Please check manually. Do you want to continue? [y/n]: " yn
			case $yn in
				[Yy]* ) 
						;;
				[Nn]* )
						echo "Script Aborted"
						exit 1
						;;
				* ) 	echo " please answer [y]es or [n]o.";;
			esac
		else
			echo " > Configuration changes were done in '${Horizon_Config_File}' file successfully."
		fi
		Current_Directory=$PWD
		if [ -e $Current_Directory/Netas-Logo.svg ]
		then
			if [ -e /var/lib/openstack-dashboard/static/dashboard/img/logo-splash.svg ]
			then
				mv /var/lib/openstack-dashboard/static/dashboard/img/logo-splash.svg /var/lib/openstack-dashboard/static/dashboard/img/logo-splash.svg.orig
			fi
			chown root:root $Current_Directory/Netas-Logo.svg
			mv $Current_Directory/Netas-Logo.svg /var/lib/openstack-dashboard/static/dashboard/img/logo-splash.svg
		fi 
		
		Apache_Config_File="/etc/apache2/conf-available/openstack-dashboard.conf"
		Control1=`cat $Apache_Config_File | grep "WSGIApplicationGroup %{GLOBAL}" | wc -l`
		if [ $Control1 -eq 1 ]
		then
			echo " > Configuration change was done in '${Apache_Config_File}' file successfully."
		else
			sed -i -r "s/^WSGIProcessGroup horizon/WSGIProcessGroup horizon\nWSGIApplicationGroup %{GLOBAL}\n/g" "$Horizon_Config_File"
			Control2=`cat $Apache_Config_File | grep "WSGIApplicationGroup %{GLOBAL}" | wc -l`
			if [ $Control2 -eq 1 ]
			then
				echo " > Configuration change was done in '${Apache_Config_File}' file successfully."
			else
				read -p "  > There is a configuration problem with '${Apache_Config_File}' file. Please check manually. Do you want to continue? [y/n]: " yn
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
		fi
		
		
		
		
		read -p " > 'apache2' Service will be reloaded. OK?" OK
		Apache_UP=0
		Service_Apache2() {
		Apache2_Service_Status=`systemctl | grep "apache2" | grep "active running" | wc -l`
		if [ $Apache2_Service_Status -ge 1 ]
		then
			echo "  > 'apache2' Service Status is 'active running'"
			Apache_UP=1
		else
			Apache_UP=0
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
		Service_Apache2
		service apache2 reload
		if [ $? -eq 0 ]
		then
			echo "  > 'apache2' Service is reloaded successfully."
		else
			echo "  > 'apache2' Service could not be reloaded successfully. Please check manually."
		fi

		echo " > FINISHED..."
		echo " > Access the dashboard using a web browser at 'http://${default_hostname}/horizon'"
		echo " > Authenticate using admin or demo user and default domain credentials"
		if [ -e /home/${default_username}/admin-openrc ]
		then
			. /home/${default_hostname}/admin-openrc
			echo "  > 'admin' user's password: '"$OS_PASSWORD"'"
		else
			echo "  > /home/${default_username}/admin-openrc could not be found. Please check for 'OS_PASSWORD' variable in this file for 'admin' user's password."
		fi
		if [ -e /home/${default_hostname}/demo-openrc ]
		then
			. /home/${default_hostname}/demo-openrc
			echo "  > 'demo' user's password: '"$OS_PASSWORD"'"
		else
			echo "  > /home/${default_username}/demo-openrc could not be found. Please check for 'OS_PASSWORD' variable in this file for 'demo' user's password."
		fi
		read -p "  > Press ENTER to see the server and OpenStack services' status. OK?" OK
		/etc/update-motd.d/05-systeminfo
		/etc/update-motd.d/90-updates-available
		/etc/update-motd.d/98-reboot-required	

	else
		echo " > 'apt -y install openstack-dashboard' command returned unsuccessful result. Please try to run this script again."
		read -p "  > Press ENTER to see the server and OpenStack services' status. OK?" OK
		/etc/update-motd.d/05-systeminfo
		/etc/update-motd.d/90-updates-available
		/etc/update-motd.d/98-reboot-required		
	fi

fi




