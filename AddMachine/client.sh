#!/bin/bash

set -e

########################################
# CONFIG
########################################

AUTH_IP="192.168.1.10"
STORAGE_IP="192.168.1.11"
GATEWAY="192.168.1.1"
REALM="ZOHOSERVER.LOCAL"
DOMAIN="zohoserver.local"

########################################
# VALIDATION
########################################

if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

CLIENT_NAME=$1
CLIENT_IP=$2

if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_IP" ]; then
    echo "Usage:"
    echo "./client-bootstrap.sh client-02 192.168.1.13"
    exit 1
fi

echo "[+] Starting bootstrap for $CLIENT_NAME ($CLIENT_IP)"

########################################
# HOSTNAME
########################################

echo "[1/10] Setting hostname..."

hostnamectl set-hostname "$CLIENT_NAME"

########################################
# HOSTS FILE
########################################

echo "[2/10] Configuring /etc/hosts..."

cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $CLIENT_NAME

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

$AUTH_IP auth.zohoserver.local auth server-auth
$STORAGE_IP storage.zohoserver.local storage server-storage
$CLIENT_IP $CLIENT_NAME.zohoserver.local $CLIENT_NAME
EOF

########################################
# NETWORK CONFIG
########################################

echo "[3/10] Configuring network..."

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $CLIENT_IP
    netmask 255.255.255.0
    gateway $GATEWAY
EOF

systemctl restart networking || true
sleep 3

########################################
# PACKAGES
########################################

echo "[4/10] Installing packages..."

apt update

apt install -y \
openssh-server \
nfs-common \
krb5-user \
sssd \
sssd-tools \
sssd-ldap \
sssd-krb5 \
libnss-sss \
libpam-sss

########################################
# SSH
########################################

echo "[5/10] Enabling SSH..."

systemctl enable ssh
systemctl restart ssh

########################################
# KERBEROS CONFIG
########################################

echo "[6/10] Configuring Kerberos..."

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false

[realms]
    $REALM = {
        kdc = auth.$DOMAIN
        admin_server = auth.$DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF

########################################
# SSSD CONFIG
########################################

echo "[7/10] Configuring SSSD..."

mkdir -p /etc/sssd

cat > /etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam
config_file_version = 2
domains = LDAP

[domain/LDAP]
id_provider = ldap
auth_provider = krb5
chpass_provider = krb5

ldap_uri = ldap://auth.$DOMAIN
ldap_search_base = dc=zohoserver,dc=local

ldap_id_use_start_tls = false
ldap_tls_reqcert = never

ldap_default_bind_dn = cn=admin,dc=zohoserver,dc=local
ldap_default_authtok = satvik

krb5_server = auth.$DOMAIN
krb5_realm = $REALM

ldap_schema = rfc2307
enumerate = true
cache_credentials = true
EOF

chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf

########################################
# NSSWITCH
########################################

echo "[8/10] Configuring NSS..."

sed -i 's/^passwd:.*/passwd: files systemd sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group: files systemd sss/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow: files sss/' /etc/nsswitch.conf

grep -q '^services:.*sss' /etc/nsswitch.conf || \
sed -i 's/^services:.*/services: db files sss/' /etc/nsswitch.conf

########################################
# IDMAPD
########################################

echo "[9/10] Configuring NFS idmap..."

cat > /etc/idmapd.conf <<EOF
[General]
Verbosity = 0
Domain = $DOMAIN

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup
EOF

########################################
# SERVICES
########################################

echo "[10/10] Restarting services..."

systemctl enable sssd
systemctl restart sssd

systemctl restart rpc-gssd || true
systemctl restart nfs-idmapd || true

echo
echo "===================================="
echo "CLIENT SETUP COMPLETE"
echo "===================================="
echo
echo "Now go to auth server and run:"
echo
echo "./add-client.sh $CLIENT_NAME $CLIENT_IP"
echo
