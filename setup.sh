#!/bin/bash

#colors!!!
R="\e[31m"
G="\e[32m"
Y="\e[33m"
F="\e[0m"

if [ $(id -u) -ne 0 ]
then 
	echo -e "${R}Please run Command as sudo or root${F}\n"
 	exit
fi

echo -e "${Y}\nDisabling SELINUX, wireguard will not work otherwise${F}"
read -r -p "are you OK with that? [y/N]: " response
response=${response,,} # to lower chars
if [[ "$response" =~ ^(yes|y)$ ]]
then
	echo SELINUX=disabled > /etc/selinux/semanage.conf
	echo -e "${G}Disabled${F}"
else
	echo -e "\n${R}Understandable Have a nice day! c:${F}"
	exit
fi

echo -e "\n${G}We'll update the list of available packages and their versions${F}"
apt-get update
echo -e "\n${G}Updated! ${F}"

echo -e "\n${G}Installing Wireguard${F}"
apt-get install wireguard qrencode -y
echo -e "\n${G}Installed${F}"

echo -e "\n${G}Now to the Configuration Partner!${F}"
if [ ! -d "/etc/wireguard" ]
then
	echo -e "${G}Seems like there's no Wireguard directory, Creating...${F}"
	mkdir -m 0700 /etc/wireguard/
fi

cd /etc/wireguard/
echo -e "${G}\nSetting umask to safe keys ${F}"
umask 077;
echo -e "${G}\nGenerating key pair${F}"
wg genkey > ServerPrivate | cat ServerPrivate | wg pubkey > ServerPublic

echo -e "THIS IS SUPER SECRET KEY THAT NOBODY SHOULD KNOW, ONLY READABLE BY ROOT BY DEFAULT\nYOU WILL SEE IT HERE ONLY ONCE"
echo -e "${G}Private key:$(cat ServerPrivate)${F}"
echo -e "THIS IS PUBLIC KEY FOR YOU CLIENTS AND PEERS"
echo -e "${G}Public key:$(cat ServerPublic)${F}"

echo -e "${G}\nSetting up conf file${F}\n"

echo "[Interface]" > wg0.conf
read -r -p "Choose your VPN private network subnet address default:10.10.10.0/24 " subnet
if [ -z "$subnet" ]
then
	subnet="10.10.10.0/24"
fi
echo "Address = $subnet" >> wg0.conf

read -r -p "Choose port to run your VPN on, you'd need to open that on router. default:5180" port
if [ -z "$port" ]
then
	port="5180"
fi
echo "ListenPort = $port" >> wg0.conf
echo "PrivateKey = $(cat ServerPrivate)" >> wg0.conf

echo -e "${G}Finished configuration, checking firewall"
ufws=$(sudo ufw status | grep inactive |wc -l)
if [ $ufws == 0 ]
then
	echo -e "\n${Y}UFW(firewall) is running openning port on host${F}"
	ufw allow $port/udp
else
	echo -e "\n${G}UFW(firewall) is inactive, we are good to go${F}"
fi

echo -e "${G}\nEnable wireguard onboot and start it${F}"
systemctl enable --now wg-quick@wg0

echo -e "${G}\n Deploy Script to easily Manage users${F}"

echo '
#!/bin/bash
#script for managing wireguard users
function add(){
echo args:$1 $2 $3 $4
wg genkey | tee /etc/wireguard/PeerPrivate.key | wg pubkey > /etc/wireguard/PeerPublic.key
Private=`cat /etc/wireguard/PeerPrivate.key`
Public=`cat /etc/wireguard/PeerPublic.key`
rm -rf PeerP*
echo -e "Private Key:   "$Private"\nPublic Key: "$Public
echo "[Interface]" > $3".conf"
echo "PrivateKey = "$Private >> $3".conf"
echo "Address = "$2"/32" >> $3".conf"
echo "DNS = 1.1.1.1" >> $3".conf"
echo "[Peer]" >> $3".conf"
echo "PublicKey = "$(cat /etc/wireguard/ServerPublic) >> $3".conf"
echo "AllowedIPs = "$4 >> $3".conf"
echo "Endpoint = '$(curl ifconfig.co):$port'" >> $3".conf"
qrencode -t UTF8 < $3".conf"
wg set wg0 peer $Public allowed-ips $2
}

function remove(){
        if [[ $2 -eq 0 ]];
        then
        echo -e "must have peer id as arg: wgclient remove <id>; use wgclient list"
        else
        wg set wg0 peer "$2" remove
fi
}

function list(){
        wg | grep -E "peer|allowed" --color=auto
}

function monit2(){
        while sleep 1; do clear; wg; done;
}

case $1 in
    "add")
    add $1 $2 $3 $4
        ;;
    "remove")
    remove $1 $2
        ;;
    "list")
    list
        ;;
    "monit2")
    monit2
        ;;
    *)
        echo "
        usage: wgclient <command> <args>

        add - add client to vpn; args: <ip> <name> <split tunnels separated by comma>
        remove - remove client from vpn list; args: public id
        list - shows vpn clients;
        monit2 - gives real time statistic;
        	Brought To you By Nikita
        "
        exit 1
        ;;
esac
' > wgclient
echo -e "\n${G}Give script run permission and link to /usr/bin${F}"
chmod 755 wgclient
mv wgclient /usr/bin/wgclient
echo -e "\n${G}now you can create users by running wgclient\n${F}"
wgclient
echo -e "\n${G}FINISH! YOU ARE GOOD TO GO, ONE LAST STEP!!!${F}"
echo -e "\n${Y}REBOOT HOST FOR SELINUX TO TAKE EFFECT\n${F}"
