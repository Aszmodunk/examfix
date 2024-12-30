#!/bin/bash

# Update system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo dnf update -y
sudo dnf install -y epel-release wget nano net-tools bind-utils firewalld mc postfix dovecot proftpd httpd php

# Basic setup
function basic_setup() {
    echo "Setting up shell basics and permissions..."
    sudo yum install -y mc
    sudo chmod u+x ~eit
    setsebool -P httpd_enable_homedirs 1
}

# Network configuration
echo "Configuring network settings..."
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO="static"
IPADDR=192.168.60.200
PREFIX=24
GATEWAY=192.168.60.254
DNS1=192.168.50.165
DNS2=192.168.50.166
EOF
sudo systemctl restart network
sudo systemctl enable firewalld
sudo systemctl start firewalld

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
    wget -O /var/named/myvspj.cz https://alpha.kts.vspj.cz/~apribyl/myvspj.cz.txt
    sudo systemctl enable named
    sudo systemctl start named
}

# Install and configure SMTP (Postfix)
function configure_smtp() {
    echo "Configuring Postfix SMTP server..."
    sudo systemctl enable postfix
    sudo systemctl start postfix
}

# Install and configure web server (Apache)
function configure_web_server() {
    echo "Installing and configuring Apache web server..."
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<h1>Testing 123</h1>" | sudo tee /var/www/html/index.html
    echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/index.php
    sudo mv /var/www/html/index.html /var/www/html/index-old.html
}

# Install and configure FTP server
function configure_ftp_server() {
    echo "Installing and configuring ProFTPD..."
    sudo dnf install -y proftpd
    sudo systemctl enable proftpd
    sudo systemctl start proftpd
}

# Main script execution
basic_setup
configure_dhcp
configure_dns
configure_smtp
configure_web_server
configure_ftp_server

echo "All configurations are completed successfully."
