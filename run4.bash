#!/bin/bash

###########################################################################
#  SERVICE CONFIGURATION SCRIPT
#  by <Tvé jméno> - doplněno pro splnění všech úkolů (DNS, DHCP, IMAP, FTP, HTTPD, NAT,...)
###########################################################################

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

#======================================================================
# 1) Package Installation
#======================================================================
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
        libmemcached-devel \
        policycoreutils-python-utils   # pro semanage (pokud bude potřeba)
        
    if [ $? -eq 0 ]; then
        log "Package installation completed successfully"
    else
        log "ERROR: Package installation failed"
        exit 1
    fi
}

#======================================================================
# 2) Network Configuration
#======================================================================
configure_network() {
    log "Configuring network settings..."
    
    local NETWORK_CONFIG="/etc/sysconfig/network-scripts/ifcfg-enp0s8"
    
    cat > "$NETWORK_CONFIG" << EOF
BOOTPROTO="static"
DEVICE="enp0s8"
ONBOOT="yes"
IPADDR=192.168.60.200
PREFIX=24
GATEWAY=192.168.60.254
DNS1=192.168.50.165
DNS2=192.168.50.166
EOF

    # Restart network service (CentOS/AlmaLinux 8+ use NetworkManager)
    systemctl restart NetworkManager
    
    # Verify network configuration
    if ip addr show enp0s8 | grep -q "192.168.60.200"; then
        log "Network configuration successful"
    else
        log "ERROR: Network configuration failed"
        return 1
    fi
}

#======================================================================
# 3) DHCP Server
#======================================================================
configure_dhcp() {
    log "Configuring DHCP server..."
    
    # Backup original configuration if exists
    if [ -f "/etc/dhcp/dhcpd.conf" ]; then
        cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup
    fi
    
    # Download and set up DHCP configuration
    wget -O /etc/dhcp/dhcpd.conf https://alpha.kts.vspj.cz/~apribyl/dhcpd.txt
    
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

#======================================================================
# 4) DNS Server (BIND)
#======================================================================
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
    
    # Configure SELinux for DNS (allow named to write master zones if needed)
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

#======================================================================
# 5) Web Server (Apache HTTPD) + VirtualHosts
#======================================================================
configure_web() {
    log "Configuring Apache web server..."
    
    # Configure Apache for IPv4
    sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/httpd/conf/httpd.conf || true
    
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

#======================================================================
# 6) Firewall
#======================================================================
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
    
    # (Dovecot typically uses IMAP, which is covered by --add-service=imap,
    #  if you also want IMAPS, add 'imaps' service likewise.)
    
    # Reload firewall
    firewall-cmd --reload
    
    log "Firewall configuration completed"
}


#======================================================================
# 7) Dovecot (IMAP) - Additional Configuration
#======================================================================
configure_dovecot() {
    log "Configuring Dovecot (IMAP)..."

    # Backup
    if [ -f /etc/dovecot/dovecot.conf ]; then
        cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak
    fi

    # Minimal config for IMAP
    cat > /etc/dovecot/dovecot.conf <<EOF
listen = *
protocols = imap
log_path = /var/log/dovecot.log
login_greeting = "Dovecot ready."
login_trusted_networks = 10.0.0.0/8 127.0.0.0/8
EOF

    # Povolit plaintext auth (pokud chceme testovat bez TLS - v reálu je to nebezpečné)
    sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf || true

    # Start/enable
    systemctl enable --now dovecot

    if systemctl is-active dovecot >/dev/null; then
        log "Dovecot IMAP server configuration successful"
    else
        log "ERROR: Dovecot configuration failed"
        return 1
    fi
}

#======================================================================
# 8) ProFTPD - Additional Configuration
#======================================================================
configure_proftpd() {
    log "Configuring ProFTPD..."

    if [ -f /etc/proftpd.conf ]; then
        cp /etc/proftpd.conf /etc/proftpd.conf.bak
    fi
    
    # Basic config
    cat > /etc/proftpd.conf <<EOF
ServerName "ProFTPD Server"
UseIPv6 off
DefaultAddress 0.0.0.0

# Port 21 is the standard FTP port.
Port 21

# If you want passive mode:
PassivePorts 40000 41000

# This is for standard Unix authentication
AuthOrder mod_auth_unix.c

# Default root can be commented out if you want chroot for users
#DefaultRoot ~

# For anonymous FTP (optional):
<IfDefine ANONYMOUS_FTP>
  <Anonymous ~ftp>
    User ftp
    Group ftp
    # We want anyone can download, but not upload
    <Directory *>
      <Limit WRITE>
        DenyAll
      </Limit>
    </Directory>
  </Anonymous>
</IfDefine>
EOF

    # Enable anonymous FTP if needed
    # In /etc/sysconfig/proftpd, set: PROFTPD_OPTIONS="-DANONYMOUS_FTP"
    
    # Shell for ftp user if we want truly anonymous
    usermod --shell /bin/bash ftp || true
    
    # SELinux booleans
    if command -v setsebool >/dev/null; then
        setsebool -P ftpd_anon_write=1
        setsebool -P ftpd_full_access=1
        setsebool -P ftpd_use_passive_mode=1
    fi

    # Start/enable
    systemctl enable --now proftpd

    if systemctl is-active proftpd >/dev/null; then
        log "ProFTPD configuration successful"
    else
        log "ERROR: ProFTPD configuration failed"
        return 1
    fi
}

#======================================================================
# 9) NAT / IP Forwarding
#======================================================================
configure_nat() {
    log "Configuring NAT and IP forwarding..."

    # 1) Enable IP Forwarding permanently
    if ! grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # Apply changes
    sysctl -p

    # 2) Firewalld masquerade
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload

    # Quick check
    FORWARD_VALUE=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$FORWARD_VALUE" -eq 1 ]; then
        log "NAT / IP forwarding enabled successfully"
    else
        log "ERROR: NAT / IP forwarding not set"
        return 1
    fi
}

#======================================================================
# 10) UserDir config (uživatelské weby)
#======================================================================
configure_userdir() {
    log "Enabling userdir feature in Apache..."

    local USERDIR_CONF="/etc/httpd/conf.d/userdir.conf"
    if [ -f "$USERDIR_CONF" ]; then
        cp "$USERDIR_CONF" "${USERDIR_CONF}.bak"
    fi

    # Odkomentovat v userdir.conf
    sed -i 's/^#\(.*\)UserDir disabled/\#\1UserDir disabled/' $USERDIR_CONF
    sed -i 's/^#UserDir public_html/UserDir public_html/' $USERDIR_CONF

    # Restart Apache after changes
    systemctl restart httpd

    # Pro test (předpokládejme uživatele 'eit')
    log "Creating public_html for user 'eit'..."
    mkdir -p /home/eit/public_html
    echo "<h1>Hello from ~eit</h1>" > /home/eit/public_html/index.html

    # Nastavit právo +x pro other na /home/eit
    chmod o+x /home/eit

    # SELinux bool
    setsebool -P httpd_enable_homedirs 1

    # Volitelně je někdy nutné nastavit kontext: chcon -R -t httpd_sys_content_t /home/eit/public_html

    log "UserDir configuration done. Try: http://<server_ip>/~eit"
}

#======================================================================
# MAIN
#======================================================================
main() {
    check_root
    log "Starting service configuration script..."
    
    install_packages
    configure_network
    configure_dhcp
    configure_dns
    configure_web
    configure_firewall
    
    # Doplňující části, pokud chceme plně splnit IMAP, FTP, NAT, atd.
    configure_dovecot
    configure_proftpd
    configure_nat
    configure_userdir

    log "All services have been configured successfully"
}

main
