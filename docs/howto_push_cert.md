# APNs Push Certificate

```bash
# 1. Private key
openssl genrsa -out app.key 2048

# 2. CSR
openssl req -new -key app.key -out Certificate.csr
```

Go to [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → create and download `aps.cer` / `aps_development.cer` and a provisioning profile.

```bash
# 3. Convert .cer → PEM
openssl x509 -in aps.cer -inform DER -out aps.pem -outform PEM
openssl x509 -in aps_development.cer -inform DER -out aps_development.pem -outform PEM

# 4. Export PKCS#12
openssl pkcs12 -export -out aps.p12 -inkey app.key -in aps.pem
openssl pkcs12 -export -out aps_development.p12 -inkey app.key -in aps_development.pem

# 5. Unencrypted PEM (for upload)
openssl pkcs12 -in aps.p12 -out apns.pem -nodes -clcerts
openssl pkcs12 -in aps_development.p12 -out apns_development.pem -nodes -clcerts
```

Upload the resulting `.pem` files to the [Telegram Apps Portal](https://my.telegram.org/apps).
