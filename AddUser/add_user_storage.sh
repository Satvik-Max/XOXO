#!/bin/bash

set -e

# ==========================================
# CONFIGURATION
# ==========================================

NFS_BASE="/srv/nfs/users"
EXPORTS_FILE="/etc/exports"

# ==========================================
# INPUT
# ==========================================

echo "========== STORAGE USER ONBOARDING =========="

read -p "Enter Username: " USERNAME

if [ -z "$USERNAME" ]; then
    echo "ERROR: Username cannot be empty."
    exit 1
fi

# ==========================================
# VERIFY USER EXISTS IN LDAP
# ==========================================

if ! getent passwd "$USERNAME" >/dev/null 2>&1; then
    echo "ERROR: User '$USERNAME' not found."
    echo "Create user on server-auth first."
    exit 1
fi

# Pull UID/GID dynamically
UID_NUM=$(id -u "$USERNAME")
GID_NUM=$(id -g "$USERNAME")

USER_DIR="$NFS_BASE/$USERNAME"
EXPORT_LINE="$USER_DIR *(rw,sync,no_subtree_check,sec=krb5p)"

echo
echo "[+] LDAP user found"
echo "Username : $USERNAME"
echo "UID      : $UID_NUM"
echo "GID      : $GID_NUM"

# ==========================================
# CREATE STORAGE DIRECTORY
# ==========================================

echo
echo "[+] Creating storage directory..."

sudo mkdir -p "$USER_DIR"

# ==========================================
# OWNERSHIP & PERMISSIONS
# ==========================================

echo "[+] Setting ownership..."

sudo chown "$UID_NUM:$GID_NUM" "$USER_DIR"

echo "[+] Setting permissions..."

sudo chmod 700 "$USER_DIR"

# ==========================================
# UPDATE EXPORTS
# ==========================================

echo "[+] Updating /etc/exports..."

if grep -Fxq "$EXPORT_LINE" "$EXPORTS_FILE"; then
    echo "[+] Export already exists."
else
    echo "$EXPORT_LINE" | sudo tee -a "$EXPORTS_FILE" >/dev/null
    echo "[+] Export added."
fi

# ==========================================
# RELOAD EXPORTS
# ==========================================

echo "[+] Reloading exports..."

sudo exportfs -ra

# ==========================================
# VERIFY
# ==========================================

echo
echo "========== VERIFICATION =========="

ls -ld "$USER_DIR"

echo
showmount -e localhost | grep "$USERNAME" || true

echo
echo "=================================="
echo "STORAGE USER CREATED SUCCESSFULLY"
echo "Username : $USERNAME"
echo "Path     : $USER_DIR"
echo "UID:GID  : $UID_NUM:$GID_NUM"
echo "=================================="
