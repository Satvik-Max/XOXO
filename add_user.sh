#!/bin/bash

set -e

# ==========================================
# Configuration
# ==========================================

DOMAIN_DN="dc=zohoserver,dc=local"
PEOPLE_OU="ou=people"
GROUPS_OU="ou=groups"

STORAGE_SERVER="192.168.1.11"
REALM="ZOHOSERVER.LOCAL"

MIN_UID=10001

# ==========================================
# Input
# ==========================================

echo "========== USER ONBOARDING =========="

read -p "Enter Username: " USERNAME

if [ -z "$USERNAME" ]; then
    echo "ERROR: Username cannot be empty."
    exit 1
fi

# prevent duplicates
if getent passwd "$USERNAME" >/dev/null 2>&1; then
    echo "ERROR: User '$USERNAME' already exists."
    exit 1
fi

# LDAP password prompt (hidden)
read -s -p "Enter LDAP admin password: " LDAP_PASS
echo

# ==========================================
# UID Generation
# ==========================================

echo "[+] Finding next available UID..."

LAST_UID=$(ldapsearch -x \
    -LLL \
    -b "$DOMAIN_DN" \
    uidNumber | \
    awk '/uidNumber:/ {print $2}' | \
    sort -n | tail -1)

if [ -z "$LAST_UID" ]; then
    NEW_UID=$MIN_UID
else
    NEW_UID=$((LAST_UID + 1))
fi

echo "[+] Assigned UID: $NEW_UID"

# ==========================================
# Create LDAP Group
# ==========================================

GROUP_FILE="/tmp/${USERNAME}_group.ldif"

cat > "$GROUP_FILE" <<EOF
dn: cn=$USERNAME,$GROUPS_OU,$DOMAIN_DN
objectClass: top
objectClass: posixGroup

cn: $USERNAME
gidNumber: $NEW_UID
EOF

echo "[+] Creating LDAP group..."

ldapadd -x \
-D "cn=admin,$DOMAIN_DN" \
-w "$LDAP_PASS" \
-f "$GROUP_FILE"

rm -f "$GROUP_FILE"

# ==========================================
# Create LDAP User
# ==========================================

USER_FILE="/tmp/${USERNAME}.ldif"

cat > "$USER_FILE" <<EOF
dn: uid=$USERNAME,$PEOPLE_OU,$DOMAIN_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top

uid: $USERNAME
sn: $USERNAME
cn: $USERNAME
uidNumber: $NEW_UID
gidNumber: $NEW_UID
homeDirectory: /home/$USERNAME
loginShell: /bin/bash
EOF

echo "[+] Creating LDAP user..."

ldapadd -x \
-D "cn=admin,$DOMAIN_DN" \
-w "$LDAP_PASS" \
-f "$USER_FILE"

rm -f "$USER_FILE"

# ==========================================
# Kerberos Principal
# ==========================================

echo "[+] Creating Kerberos principal..."
echo "Set password for $USERNAME"

sudo kadmin.local -q "addprinc $USERNAME"

# ==========================================
# Storage Provisioning
# ==========================================

echo "[+] Creating NFS storage..."

ssh root@$STORAGE_SERVER <<EOF
set -e

USER_DIR="/srv/nfs/users/$USERNAME"
EXPORT_LINE="\$USER_DIR *(rw,sync,no_subtree_check,sec=krb5p)"

mkdir -p "\$USER_DIR"

chown $NEW_UID:$NEW_UID "\$USER_DIR"
chmod 700 "\$USER_DIR"

grep -Fxq "\$EXPORT_LINE" /etc/exports || \
echo "\$EXPORT_LINE" >> /etc/exports

exportfs -ra
EOF

# ==========================================
# Verification
# ==========================================

echo
echo "========== VERIFICATION =========="

getent passwd "$USERNAME" || true

echo
echo "Kerberos Principal:"
sudo kadmin.local -q "listprincs" | grep "^$USERNAME@"

echo
echo "=================================="
echo "User Created Successfully"
echo "Username : $USERNAME"
echo "UID/GID  : $NEW_UID"
echo "Realm    : $REALM"
echo "Storage  : /srv/nfs/users/$USERNAME"
echo "=================================="
