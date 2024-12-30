#!/bin/bash

# Update system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo dnf update -y

# Install all necessary packages in one step
echo "Installing all required packages..."
sudo dnf install -y epel-release wget nano net-tools bind-utils firewalld mc postfix dovecot httpd php dhcp-server proftpd libmemcached libmemcached-devel

# Basic setup
function basic_setup() {
    echo "Setting up shell basics and permissions..."
    sudo yum install -y mc
    if [ -d "/home/eit" ]; then
        sudo chmod u+x /home/eit
        setsebool -P httpd_enable_homedirs 1
    else
        echo "User directory /home/eit does not exist. Skipping permissions setup."
    fi
}

# Network configuration
echo "Configuring network settings..."
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO="static"
IPADDR=192.168.60.200
PREFIX=24
GATEWAY=192.168.60.254
DNS1=192.168.50.165
DNS2=192.168.50.166
EOF
if command -v nmcli &> /dev/null; then
    sudo nmcli con reload
    sudo nmcli con up eth0
else
    echo "NetworkManager CLI not found. Skipping network restart."
fi

# Install and configure DHCP server
function configure_dhcp() {
    echo "Installing and configuring DHCP server..."
    sudo dnf install -y dhcp-server
    wget -O /etc/dhcp/dhcpd.conf https://alpha.kts.vspj.cz/~apribyl/dhcpd.txt
    sudo systemctl enable dhcpd
    sudo systemctl start dhcpd
}

# Install and configure DNS server
function configure_dns() {
    echo "Installing and configuring DNS server..."
    sudo dnf install -y bind
    if [ ! -d "/var/named" ]; then
        sudo mkdir -p /var/named
    fi
    wget -O /var/named/myvspj.cz https://alpha.kts.vspj.cz/~apribyl/myvspj.cz.txt
    sudo systemctl enable named
    sudo systemctl start named
}

# Install and configure SMTP (Postfix)
function configure_smtp() {
    echo "Configuring Postfix SMTP server..."
    if systemctl list-units --type=service | grep -q postfix; then
        sudo systemctl enable postfix
        sudo systemctl start postfix
    else
        echo "Postfix service not found. Skipping SMTP configuration."
    fi
}

# Install and configure web server (Apache)
function configure_web_server() {
    echo "Installing and configuring Apache web server with PHP support..."
    if systemctl list-units --type=service | grep -q httpd; then
        sudo systemctl enable httpd
        sudo systemctl start httpd
        sudo mkdir -p /var/www/html
        echo "<h1>Testing 123</h1>" | sudo tee /var/www/html/index.html
        echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/index.php
    else
        echo "Apache service not found. Skipping web server configuration."
    fi
}

# Install and configure FTP server
function configure_ftp_server() {
    echo "Installing and configuring ProFTPD..."
    if systemctl list-units --type=service | grep -q proftpd; then
        sudo systemctl enable proftpd
        sudo systemctl start proftpd
    else
        echo "ProFTPD service not found. Skipping FTP server configuration."
    fi
}

# Main script execution
basic_setup
configure_dhcp
configure_dns
configure_smtp
configure_web_server
configure_ftp_server

echo "All configurations are completed successfully."
