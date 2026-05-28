#!/bin/bash

set -e

REALM="ZOHOSERVER.LOCAL"
DOMAIN="zohoserver.local"

CLIENT_NAME=$1
CLIENT_IP=$2

if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_IP" ]; then
    echo "Usage:"
    echo "./add-client.sh client-02 192.168.1.13"
    exit 1
fi

FQDN="${CLIENT_NAME}.${DOMAIN}"

echo "[1/4] Creating Kerberos principals..."

kadmin.local -q "addprinc -randkey host/$FQDN" || true
kadmin.local -q "addprinc -randkey nfs/$FQDN" || true

echo "[2/4] Generating keytab..."

rm -f /tmp/${CLIENT_NAME}.keytab

kadmin.local -q "ktadd -k /tmp/${CLIENT_NAME}.keytab host/$FQDN"
kadmin.local -q "ktadd -k /tmp/${CLIENT_NAME}.keytab nfs/$FQDN"

echo "[3/4] Copying keytab..."

scp /tmp/${CLIENT_NAME}.keytab root@$CLIENT_IP:/tmp/

echo "[4/4] Installing keytab on client..."

ssh root@$CLIENT_IP \
"mv /tmp/${CLIENT_NAME}.keytab /etc/krb5.keytab && chmod 600 /etc/krb5.keytab && systemctl restart sssd"

echo
echo "===================================="
echo "CLIENT ADDED SUCCESSFULLY"
echo "===================================="
echo
echo "Test on client:"
echo
echo "getent passwd sanji"
echo "id sanji"
echo "su - sanji"
echo
