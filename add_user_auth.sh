#!/bin/bash

set -e

# ==========================================
# CONFIGURATION
# ==========================================

DOMAIN_DN="dc=zohoserver,dc=local"
PEOPLE_OU="ou=users"
GROUPS_OU="ou=groups"

REALM="ZOHOSERVER.LOCAL"
MIN_UID=10001

# ==========================================
# INPUT
# ==========================================

echo "========== AUTH USER ONBOARDING =========="

read -p "Enter Username: " USERNAME

if [ -z "$USERNAME" ]; then
    echo "ERROR: Username cannot be empty."
    exit 1
fi

# Check if user already exists
if getent passwd "$USERNAME" >/dev/null 2>&1; then
    echo "ERROR: User '$USERNAME' already exists."
    exit 1
fi

# LDAP admin password
read -s -p "Enter LDAP admin password: " LDAP_PASS
echo

# ==========================================
# FIND NEXT UID
# ==========================================

echo "[+] Finding next available UID..."

LAST_UID=$(ldapsearch -x -LLL \
    -b "$DOMAIN_DN" \
    "(uidNumber=*)" uidNumber | \
    awk '/uidNumber:/ {print $2}' | \
    sort -n | tail -1)

if [ -z "$LAST_UID" ]; then
    NEW_UID=$MIN_UID
else
    NEW_UID=$((LAST_UID + 1))
fi

echo "[+] Assigned UID/GID: $NEW_UID"

# ==========================================
# CREATE LDAP GROUP
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
# CREATE LDAP USER
# ==========================================

USER_FILE="/tmp/${USERNAME}.ldif"

cat > "$USER_FILE" <<EOF
dn: uid=$USERNAME,$PEOPLE_OU,$DOMAIN_DN
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
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
# CREATE KERBEROS PRINCIPAL
# ==========================================

echo
echo "[+] Creating Kerberos principal..."
echo "Set password for $USERNAME"

sudo kadmin.local -q "addprinc $USERNAME"

# ==========================================
# VERIFY
# ==========================================

echo
echo "========== VERIFICATION =========="

getent passwd "$USERNAME" || true
id "$USERNAME" || true

echo
echo "Kerberos Principal:"
sudo kadmin.local -q "listprincs" | grep "^$USERNAME@"

echo
echo "=================================="
echo "AUTH USER CREATED SUCCESSFULLY"
echo "Username : $USERNAME"
echo "UID/GID  : $NEW_UID"
echo "Realm    : $REALM"
echo "=================================="
