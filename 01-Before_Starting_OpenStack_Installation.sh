#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="$(hostname).local"
default_puppetmaster="foreman.netson.nl"
tmp="/root/"
clear
echo " +---------------------------------------------------------------------------------------------------------------------+"
echo " |                                                  IMPORTANT NOTES                                                    |"
echo " | This script must be run with maximum privileges. Run with sudo or run it as 'root'.                                 |"
echo " | This script will do:                                                                                                |"
echo " | 1.  Hostname Configuration                                                                                          |"
echo " | 2.  Preferred Domain Configuration                                                                                  |"
echo " | 3.  Add Puppetlab Repositories (Optional)                                                                           |"
echo " | 4.  Setup Puppet Agent (Optional)                                                                                   |"
echo " | 5.  NTP Synchronization Control                                                                                     |"
echo " | 6.  User Environment Configuration                                                                                  |"
echo " | 7.  Enable Remote SSH With Root User                                                                                |"
echo " | 8.  Change Welcome Message & Insert OpenStack Specific Messages                                                     |"
echo " |     ('05-systeminfo' file should be located in the directory where this script runs in)                             |"
echo " | 9.  Change Ethernet Name Format To ethXX (Optional)                                                                 |"
echo " | 10. '/etc/hosts' File Configuration                                                                                 |"
echo " | 11. Static IP Configuration & Installation of Required Packages                                                     |"
echo " | 12. Enable OpenStack Repository                                                                                     |"
echo " | 13. 'software-properties-common' Package Installation                                                               |"
echo " | 14. Add OpenStack Queens Repository (Optional)                                                                      |"
echo " | 15. 'python-openstackclient' Package Installation                                                                   |"
echo " | 16. Ubuntu Desktop Installation (Optional)                                                                          |"
echo " | 17. Update Repositories                                                                                             |"
echo " | 18. Remove This Script & Reboot                                                                                     |"
echo " +---------------------------------------------------------------------------------------------------------------------+"
echo

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# determine ubuntu version
ubuntu_version=$(lsb_release -cs)

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

    # ask questions
    read -ep " > please enter your preferred hostname: " -i "$default_hostname" hostname
	
    while true
	do
		read -ep " > please enter your preferred domain: " -i "$default_domain" domain
		DotCount=`echo $domain | awk -F"." '{print NF-1}'`
		if [ $DotCount -ge 1 ]
		then
			break
		else
			echo " Domain name must have at least one dot. Please enter domain name again."
		fi
	done

    # ask whether to add puppetlabs repositories
    while true; do
        read -p " > do you wish to add the latest puppet repositories from puppetlabs? [y/n]: " yn
        case $yn in
            [Yy]* ) include_puppet_repo=1
                    puppet_deb="puppetlabs-release-"$ubuntu_version".deb"
                    break;;
            [Nn]* ) include_puppet_repo=0
                    puppet_deb=""
                    puppetmaster="puppet"
                    break;;
            * ) echo " please answer [y]es or [n]o.";;
        esac
    done

    if [[ include_puppet_repo ]] ; then
        # ask whether to setup puppet agent or not
        while true; do
            read -p " > do you wish to setup the puppet agent? [y/n]: " yn
            case $yn in
                [Yy]* ) setup_agent=1
                        read -ep " > please enter your puppet master: " -i "$default_puppetmaster" puppetmaster
                        break;;
                [Nn]* ) setup_agent=0
                        puppetmaster="puppet"
                        break;;
                * ) echo " please answer [y]es or [n]o.";;
            esac
        done
    fi

# install puppet
if [[ include_puppet_repo -eq 1 ]]; then
    # install puppet repo
    wget https://apt.puppetlabs.com/$puppet_deb -O $tmp/$puppet_deb
    dpkg -i $tmp/$puppet_deb
    apt-get -y update
    rm $tmp/$puppet_deb
    
    # check to install puppet agent
    if [[ setup_agent -eq 1 ]] ; then
        # install puppet
        apt-get -y install puppet

        # set puppet master settings
        sed -i "s@\[master\]@\
# configure puppet master\n\
server=$puppetmaster\n\
report=true\n\
pluginsync=true\n\
\n\
\[master\]@g" /etc/puppet/puppet.conf

        # remove the deprecated template dir directive from the puppet.conf file
        sed -i "/^templatedir=/d" /etc/puppet/puppet.conf

        # download the finish script if it doesn't yet exist
        if [[ ! -f $tmp/finish.sh ]]; then
            echo -n " downloading finish.sh: "
            cd $tmp
            download "https://raw.githubusercontent.com/netson/ubuntu-unattended/master/finish.sh"
        fi

        # set proper permissions on finish script
        chmod +x $tmp/finish.sh

        # connect to master and ensure puppet is always the latest version
        echo " connecting to puppet master to request new certificate"
        echo " please sign the certificate request on your puppet master ..."
        puppet agent --waitforcert 60 --test
        echo " once you've signed the certificate, please run finish.sh from your home directory"
    fi
fi	

# print status message
echo " > preparing your server, this may take a few minutes ..."

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# NTP Control
NTP_State=`timedatectl | grep "NTP synchronized" | sed 's/NTP synchronized//g'| tr -d ': '`

if [ $NTP_State != "yes" ]
then
	while true; do
		read -p " > NTP synchronization not OK. Do you wish to continue? [y/n]: " yn
		case $yn in
			[YyNn]* ) 
					break;;
			* ) 	echo " please answer [y]es or [n]o.";;
		esac
	done
fi

# print status message
echo " > preparing your server environments..."
#UserName=`who | cut -f1 -d" " | head -1`
UserName=`more /etc/passwd | tail -1 | cut -f1 -d":"`
echo 'HISTTIMEFORMAT="%F %T > "' >> /home/$UserName/.bashrc
echo 'HISTTIMEFORMAT="%F %T > "' >> /root/.bashrc
echo 'HISTFILESIZE=1000000000' >> /home/$UserName/.bashrc
echo 'HISTFILESIZE=1000000000' >> /root/.bashrc
echo 'HISTSIZE=1000000000' >> /home/$UserName/.bashrc
echo 'HISTSIZE=1000000000' >> /root/.bashrc
working_directory=`echo $PWD`
system_info_file=$working_directory"/05-systeminfo"
if [ -e $system_info_file ]
then 
	chmod +x $system_info_file
	mv $system_info_file /etc/update-motd.d/
fi

sed -i '/printf /d' /etc/update-motd.d/10-help-text
sed -i '/stamp/d' /etc/update-motd.d/90-updates-available
sed -i '/-r "$stamp"/d' /etc/update-motd.d/90-updates-available

# print status message
echo " > Changing Remote Login Setting For 'root' User..."

while true; do
    read -p " > do you wish to enable 'root' user to login this server from remote? (Recommended) [y/n]: " yn
    case $yn in
        [Yy]* ) 
				sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
				service ssh restart
                break;;
        [Nn]* ) 
				
                break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

echo root:root123 | /usr/sbin/chpasswd

# print status message
echo " > Changing ethernet interface names if needed..."
EthFormat=`more /etc/network/interfaces | grep auto | grep -v lo | cut -f2 -d" " | cut -c1-3`
if [ $EthFormat != "eth" ]
then
while true; do
    read -p " > do you wish to change ethernet name format to ethXX? [y/n]: " yn
    case $yn in
        [Yy]* ) 
				sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/g' /etc/default/grub
				grub-mkconfig -o /boot/grub/grub.cfg
				sed -i 's/enp0s3/eth0/g' /etc/network/interfaces
				sed -i 's/enp0s8/eth1/g' /etc/network/interfaces
                break;;
        [Nn]* ) 
				
                break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done
fi

while true; do
read -p " > Which IP block do you wish to use on the OpenStack Nodes [Ex. 192.168.1.0] [Default=192.168.1.0]: " Input
	if [ -z $Input ]
	then
		Input="192.168.1.0"
	fi
	
	DotCount=`echo $Input | awk -F"." '{print NF-1}'`
	FirstOctet=`echo $Input | tr "." "\n" | head -1`
	SecondOctet=`echo $Input | tr "." "\n" | head -2 | tail -1`
	ThirdOctet=`echo $Input | tr "." "\n" | head -3 | tail -1`
	FourthOctet=`echo $Input | tr "." "\n" | head -4 | tail -1`
	if [ $DotCount -eq 3 ] && [ $FirstOctet -lt 255 ] && [ $SecondOctet -lt 255 ] && [ $ThirdOctet -lt 255 ] && [ $FourthOctet -lt 255 ] && [ $FirstOctet -gt 0 ] && [ $SecondOctet -ge 0 ] && [ $ThirdOctet -ge 0 ] && [ $FourthOctet -eq 0 ]
	then
		IP_Block=${Input::-1}
		break
	else
		if [ $FourthOctet -ne 0 ]
		then
			echo " > Your IP format is wrong. Last octet must be zero. Please correct and try again. "
		fi
		
		if [ $FirstOctet -eq 0 ]
		then
			echo " > Your IP format is wrong. First octet can not be zero. Please correct and try again. "
		fi
		
		if [ $FirstOctet -ge 255 ] || [ $SecondOctet -ge 255 ] || [ $ThirdOctet -ge 255 ] || [ $FourthOctet -ge 255 ]
		then
			echo " > Your IP format is wrong. Octets must be less than 255. Please correct and try again. "
		fi	
		
		if [ $FirstOctet -lt 0 ] || [ $SecondOctet -lt 0 ] || [ $ThirdOctet -lt 0 ] || [ $FourthOctet -lt 0 ]
		then
			echo " > Your IP format is wrong. Octets can not be negative numbers. Please correct and try again. "
		fi			
	fi
done

# print status message
echo " > Name resolution configuration..."
while true; do
    read -p " > do you wish to insert other host IP adresses to /etc/hosts file? [y/n]: " yn
    case $yn in
        [Yy]* ) 
				read -p " > Please insert 1. controller node's IP [Default=${IP_Block}100]: " IP_controller
				if [ -z "$IP_controller" ]; then IP_controller="${IP_Block}100"; fi
				read -p " > Please insert 1. controller node's hostname [Default=controller1]: " HostName_controller
				if [ -z "$HostName_controller" ]; then HostName_controller="controller1"; fi
				echo $IP_controller" "$HostName_controller >> /etc/hosts

				read -p " > Please insert 2. controller node's IP [Default=${IP_Block}101]: " IP_controller
				if [ -z "$IP_controller" ]; then IP_controller="${IP_Block}101"; fi
				read -p " > Please insert 2. controller node's hostname [Default=controller2]: " HostName_controller
				if [ -z "$HostName_controller" ]; then HostName_controller="controller2"; fi
				echo $IP_controller" "$HostName_controller >> /etc/hosts
				
				read -p " > Please insert 1. compute node's IP [Default=${IP_Block}111]: " IP_compute1
				if [ -z "$IP_compute1" ]; then IP_compute1="${IP_Block}111"; fi
				read -p " > Please insert 1. compute node's hostname [Default=compute1]: " HostName_compute1
				if [ -z "$HostName_compute1" ]; then HostName_compute1="compute1"; fi
				echo $IP_compute1" "$HostName_compute1 >> /etc/hosts
				
				read -p " > Please insert 2. compute node's IP [Default=${IP_Block}112]: " IP_compute2
				if [ -z "$IP_compute2" ]; then IP_compute2="${IP_Block}112"; fi
				read -p " > Please insert 2. compute node's hostname [Default=compute2]: " HostName_compute2
				if [ -z "$HostName_compute2" ]; then HostName_compute2="compute2"; fi
				echo $IP_compute2" "$HostName_compute2 >> /etc/hosts
				
				read -p " > Please insert 1. block storage node's IP [Default=${IP_Block}121]: " IP_block1
				if [ -z "$IP_block1" ]; then IP_block1="${IP_Block}121"; fi				
				read -p " > Please insert 1. block storage node's hostname [Default=block1]: " HostName_block1
				if [ -z "$HostName_block1" ]; then HostName_block1="block1"; fi
				echo $IP_block1" "$HostName_block1 >> /etc/hosts
				
				read -p " > Please insert 2. block storage node's IP [Default=${IP_Block}122]: " IP_block2
				if [ -z "$IP_block2" ]; then IP_block2="${IP_Block}122"; fi
				read -p " > Please insert 2. block storage node's hostname [Default=block2]: " HostName_block2
				if [ -z "$HostName_block2" ]; then HostName_block2="block2"; fi
				echo $IP_block2" "$HostName_block2 >> /etc/hosts
				
				read -p " > Please insert 1. object storage node's IP [Default=${IP_Block}131]: " IP_object1
				if [ -z "$IP_object1" ]; then IP_object1="${IP_Block}131"; fi
				read -p " > Please insert 1. object storage node's hostname [Default=object1]: " HostName_object1
				if [ -z "$HostName_object1" ]; then HostName_object1="object1"; fi
				echo $IP_object1" "$HostName_object1 >> /etc/hosts
				
				read -p " > Please insert 2. object storage node's IP [Default=${IP_Block}132]: " IP_object2
				if [ -z "$IP_object2" ]; then IP_object2="${IP_Block}132"; fi
				read -p " > Please insert 2. object storage node's hostname [Default=object2]: " HostName_object2
				if [ -z "$HostName_object2" ]; then HostName_object2="object2"; fi
				echo $IP_object2" "$HostName_object2 >> /etc/hosts
				
				sed -i '/127.0.1.1/d' /etc/hosts
				sed -i '/# The following lines are desirable for IPv6 capable hosts/d' /etc/hosts
				sed -i '/::1/d' /etc/hosts
				sed -i '/ff02::/d' /etc/hosts
				break;;
        [Nn]* ) 
                break;;
        * ) 
				echo " please answer [y]es or [n]o.";;
    esac
done

# print status message
echo " > Making Static IP Configuration Of Management Interface... "
while true; do
	read -p " > do you wish to configure management interface IP according to server hostname (${hostname})? [y/n]: " yn
	case $yn in
		[Yy]* )

			case $hostname in
				$HostName_controller ) 
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_controller}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces	
										break;;
				$HostName_compute1 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_compute1}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				$HostName_compute2 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_compute2}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				$HostName_block1 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_block1}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				$HostName_block2 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_block2}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				$HostName_object1 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_object1}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				$HostName_object2 )
										echo "auto eth1" >> /etc/network/interfaces
										echo "iface eth1 inet static" >> /etc/network/interfaces				
										echo "address ${IP_object2}" >> /etc/network/interfaces
										echo "netmask 255.255.255.0" >> /etc/network/interfaces
										break;;
				* )
										read -p " > WARNING! Static IP Configuration could not be made! Server's hostname is not matching with the hostname in /etc/hosts file." OK
			esac
			break;;
		[Nn]* )
			echo 
			break;;
		* )
			echo " please answer [y]es or [n]o.";;
	esac
done

echo " > Installing 'dos2unix'..."
apt -y install dos2unix 
echo " > Installing 'sshpass'..."
apt -y install sshpass
echo " > Installing 'man'..."
apt -y install man
echo " > Installing 'telnet'..."
apt -y install telnet
echo " > Installing 'traceroute'..."
apt -y install traceroute
echo " > Installing 'tcpdump'..."
apt -y install tcpdump
echo " > Installing 'curl'..."
apt -y install curl
echo " > Installing 'multitail'..."
apt -y install multitail

# print status message
echo " > Enabling OpenStack Repository..."
while true; do
    read -p " > do you wish to install and enable OpenStack repository for OpenStack Queens? [y/n]: " yn
    case $yn in
        [Yy]* ) 
#				read -p "  > software-properties-common package will be installed. OK?" OK
				apt-get -y install software-properties-common
#				read -p "  > openstack queens repository will be added. OK?" OK
				yes | add-apt-repository cloud-archive:queens
#				read -p "  > python-openstackclient package will be installed. OK?" OK
				apt-get -y install python-openstackclient
					while true; do
					read -p " > do you wish to install ubuntu-desktop? [y/n]: " yn
					case $yn in
						[Yy]* ) 
								echo "  > ubuntu-desktop will be installed."
								apt-get -y install ubuntu-desktop
								break;;
						[Nn]* ) 
					
								break;;
						* ) 	
								echo " please answer [y]es or [n]o.";;
					esac
					done
				break;;
        [Nn]* ) 
                break;;
        * ) 	
				echo " please answer [y]es or [n]o.";;
    esac
done

# update repos
while true; do
    read -p " > do you wish to update repos? (Recommended) [y/n]: " yn
    case $yn in
        [Yy]* ) 
				apt-get -y update
				apt-get -y upgrade
				apt-get -y dist-upgrade
                break;;
        [Nn]* ) 
                break;;
        * ) 	echo " please answer [y]es or [n]o.";;
    esac
done
	
# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
read -p "  > FINISHED... Rebooting the server. OK?" OK

# reboot
reboot	
	
	
	
fi

