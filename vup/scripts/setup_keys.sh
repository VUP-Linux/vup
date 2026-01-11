#!/bin/bash
set -e

# Setup VUP Signing Keys
KEY_DIR="keys"
mkdir -p "$KEY_DIR"

echo "Generating RSA 4096 keypair for XBPS signing..."
openssl genrsa -out "$KEY_DIR/privkey.pem" 4096
openssl rsa -in "$KEY_DIR/privkey.pem" -pubout -out "$KEY_DIR/pubkey.pem"

echo "----------------------------------------------------------------"
echo "KEYS GENERATED SUCCESSFULLY in '$KEY_DIR/'"
echo "----------------------------------------------------------------"
echo "1. PUBLIC KEY (Clients must install this):"
echo "   File: $KEY_DIR/pubkey.pem"
echo "   Command to install on client:"
echo "   sudo cp $KEY_DIR/pubkey.pem /var/db/xbps/keys/$(openssl rsa -pubin -in "$KEY_DIR/pubkey.pem" -outform DER | openssl dgst -sha256 | awk '{print $2}').plist"
echo ""
echo "   (Wait, XBPS public keys are just .pem files in /var/db/xbps/keys/)"
echo "   Actually, copy it like this:"
echo "   sudo cp $KEY_DIR/pubkey.pem /var/db/xbps/keys/"
echo ""
echo "2. PRIVATE KEY (GitHub Action Secret):"
echo "   File: $KEY_DIR/privkey.pem"
echo "   Content:"
cat "$KEY_DIR/privkey.pem"
echo ""
echo "   ACTION REQUIRED: Go to GitHub Repo -> Settings -> Secrets -> Actions"
echo "   Create a new secret named 'XBPS_PRIVATE_KEY' with the content above."
echo "----------------------------------------------------------------"
