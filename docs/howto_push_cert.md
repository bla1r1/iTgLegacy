# APNs Push Certificate Guide

### 1. Generate private key
```bash
openssl genrsa -out app.key 2048
```

### 2. Create Apple Certificate Signing Request (CSR)
```bash
openssl req -new -key app.key -out Certificate.csr
```

### 3. Generate Certificate on Apple Developer Portal
* Go to [developer.apple.com](https://developer.apple.com) -> **Certificates, Identifiers & Profiles**.
* Create and download the Apple Push Notification service SSL certificate (`aps.cer` / `aps_development.cer`) and provisioning profile.

### 4. Convert downloaded Apple Certificate to PEM
```bash
openssl x509 -in aps.cer -inform DER -out aps.pem -outform PEM
openssl x509 -in aps_development.cer -inform DER -out aps_development.pem -outform PEM
```

### 5. Export PKCS#12 (.p12)
```bash
openssl pkcs12 -export -out aps.p12 -inkey app.key -in aps.pem
openssl pkcs12 -export -out aps_development.p12 -inkey app.key -in aps_development.pem
```

### 6. Convert .p12 to unencrypted PEM
```bash
openssl pkcs12 -in aps.p12 -out apns.pem -nodes -clcerts
openssl pkcs12 -in aps_development.p12 -out apns_development.pem -nodes -clcerts
```

### 7. Upload to Telegram
Upload the generated certificates to the [Telegram Apps Portal](https://my.telegram.org/apps).

