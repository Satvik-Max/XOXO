#!/bin/bash

# Configuration - Change these to match your setup
DOMAIN_DN="dc=zohoserver,dc=local"
STORAGE_SERVER="192.168.1.11" # Your Storage VM Static IP
REALM="ZOHOSERVER.LOCAL"

# 1. Get Inputs
read -p "Enter Username: " USERNAME
if [ -z "$USERNAME" ]; then echo "Username cannot be empty"; exit 1; fi

# 2. Automatically find the next available UID (Starts from 10005 to avoid system users)
LAST_UID=$(getent passwd | awk -F: '$3 >= 10000 && $3 < 65534 {print $3}' | sort -n | tail -1)
if [ -z "$LAST_UID" ]; then
    NEW_UID=10001
else
    NEW_UID=$((LAST_UID + 1))
fi

echo "Assigning UID: $NEW_UID"

# 3. Create LDAP entry (Identity)
cat <<EOF > /tmp/new_user.ldif
dn: uid=$USERNAME,ou=people,$DOMAIN_DN
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

ldapadd -x -D "cn=admin,$DOMAIN_DN" -W -f /tmp/new_user.ldif
rm /tmp/new_user.ldif

# 4. Create Kerberos Principal (Security)
echo "Setting up Kerberos. Please enter a password for $USERNAME when prompted."
sudo kadmin.local -q "addprinc $USERNAME"

# 5. Remote Storage Setup (The "Locker")
echo "Connecting to Storage Server to create locker..."
ssh root@$STORAGE_SERVER <<EOF
    mkdir -p /srv/nfs/users/$USERNAME
    chown $NEW_UID:$NEW_UID /srv/nfs/users/$USERNAME
    chmod 700 /srv/nfs/users/$USERNAME
    echo "/srv/nfs/users/$USERNAME  *(rw,sync,no_subtree_check,sec=krb5p)" >> /etc/exports
    exportfs -ra
EOF

echo "--- SUCCESS ---"
echo "User: $USERNAME | UID: $NEW_UID | Locker: Created & Exported"
