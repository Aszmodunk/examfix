#!/bin/bash

# Error handling
set -e
trap 'echo "Error occurred at line $LINENO. Exit code: $?"' ERR

# Logging configuration
LOG_FILE="/var/log/service_setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to handle package installation
install_packages() {
    log "Installing required packages..."
    
    # Enable EPEL repository first
    dnf install -y epel-release
    
    # Enable CRB repository for ProFTPD dependencies
    dnf config-manager --set-enabled crb
    
    # Update package lists
    dnf update -y
    
    # Install all required packages
    dnf install -y \
        wget \
        nano \
        net-tools \
        bind-utils \
        firewalld \
        mc \
        bind \
        postfix \
        dovecot \
        httpd \
        php \
        dhcp-server \
        proftpd \
        libmemcached \
        libmemcached-devel
        
    if [ $? -eq 0 ]; then
        log "Package installation completed successfully"
    else
        log "ERROR: Package installation failed"
        exit 1
    fi
}

# Network configuration
configure_network() {
    log "Configuring network settings..."
    
    local NETWORK_CONFIG="/etc/sysconfig/network-scripts/ifcfg-eth0"
    
    cat > "$NETWORK_CONFIG" << EOF
BOOTPROTO="static"
DEVICE="eth0"
ONBOOT="yes"
IPADDR=192.168.60.200
PREFIX=24
GATEWAY=192.168.60.254
DNS1=192.168.50.165
DNS2=192.168.50.166
EOF

    # Restart network service
    systemctl restart NetworkManager
    
    # Verify network configuration
    if ip addr show eth0 | grep -q "192.168.60.200"; then
        log "Network configuration successful"
    else
        log "ERROR: Network configuration failed"
        return 1
    fi
}

# DHCP Server configuration
configure_dhcp() {
    log "Configuring DHCP server..."
    
    # Backup original configuration if exists
    if [ -f "/etc/dhcp/dhcpd.conf" ]; then
        cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup
    fi
    
    # Download and set up DHCP configuration
    wget -O /etc/dhcp/dhcpd.conf https://alpha.kts.vspj.cz/~apribyl/dhcpd.txt
    
    # Configure SELinux for DHCP
    if command -v setsebool >/dev/null; then
        setsebool -P dhcpd_disable_trans 0
    fi
    
    # Start and enable DHCP service
    systemctl enable --now dhcpd
    
    # Verify DHCP service
    if systemctl is-active dhcpd >/dev/null; then
        log "DHCP server configuration successful"
    else
        log "ERROR: DHCP server configuration failed"
        return 1
    fi
}

# DNS Server configuration
configure_dns() {
    log "Configuring DNS server..."
    
    # Backup original configuration if exists
    if [ -f "/etc/named.conf" ]; then
        cp /etc/named.conf /etc/named.conf.backup
    fi
    
    # Configure main DNS settings
    cat > "/etc/named.conf" << EOF
options {
    listen-on port 53 { any; };
    directory       "/var/named";
    allow-query     { localhost; 10.0.0.0/8; };
    allow-recursion { localhost; 10.0.0.0/8; };
    recursion yes;
};

zone "myvspj.cz" IN {
    type master;
    file "myvspj.cz";
};
EOF

    # Download zone file
    wget -O /var/named/myvspj.cz https://alpha.kts.vspj.cz/~apribyl/myvspj.cz.txt
    chown named:named /var/named/myvspj.cz
    
    # Configure SELinux for DNS
    if command -v setsebool >/dev/null; then
        setsebool -P named_write_master_zones 1
    fi
    
    # Start and enable DNS service
    systemctl enable --now named
    
    # Verify DNS service
    if systemctl is-active named >/dev/null; then
        log "DNS server configuration successful"
    else
        log "ERROR: DNS server configuration failed"
        return 1
    fi
}

# Web Server configuration
configure_web() {
    log "Configuring Apache web server..."
    
    # Configure Apache for IPv4
    sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf
    
    # Create virtual hosts configuration
    cat > "/etc/httpd/conf.d/virtualhosts.conf" << EOF
<VirtualHost *:80>
    DocumentRoot "/var/www/html"
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/var/www/web1"
    ServerName web1.myvspj.cz
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/var/www/web2"
    ServerName web2.myvspj.cz
</VirtualHost>
EOF

    # Create web directories
    mkdir -p /var/www/{html,web1,web2}
    
    # Create test pages
    echo "<h1>Main Website</h1>" > /var/www/html/index.html
    echo "<h1>Web1 Subdomain</h1>" > /var/www/web1/index.html
    echo "<h1>Web2 Subdomain</h1>" > /var/www/web2/index.html
    
    # Configure SELinux for Apache
    if command -v setsebool >/dev/null; then
        setsebool -P httpd_enable_homedirs 1
        setsebool -P httpd_can_network_connect 1
    fi
    
    # Start and enable Apache service
    systemctl enable --now httpd
    
    # Verify Apache service
    if systemctl is-active httpd >/dev/null; then
        log "Web server configuration successful"
    else
        log "ERROR: Web server configuration failed"
        return 1
    fi
}

# Firewall configuration
configure_firewall() {
    log "Configuring firewall..."
    
    # Start and enable firewalld
    systemctl enable --now firewalld
    
    # Configure firewall rules
    firewall-cmd --permanent --add-service=dns
    firewall-cmd --permanent --add-service=dhcp
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-service=ftp
    firewall-cmd --permanent --add-service=smtp
    firewall-cmd --permanent --add-service=imap
    
    # Reload firewall
    firewall-cmd --reload
    
    log "Firewall configuration completed"
}

# Main execution
main() {
    check_root
    log "Starting service configuration script..."
    
    install_packages
    configure_network
    configure_dhcp
    configure_dns
    configure_web
    configure_firewall
    
    log "All services have been configured successfully"
}

# Execute main function
main
