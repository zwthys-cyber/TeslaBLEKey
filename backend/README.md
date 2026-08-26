# Tesla Fleet API backend

This service adds optional Tesla account connectivity to the existing local BLE key. It is a confidential OAuth client: Tesla access and rotating refresh tokens stay encrypted on the server, while the iOS app receives only a revocable application session token.

## China endpoints

- Authorization: `https://auth.tesla.cn/oauth2/v3/authorize`
- Token: `https://auth.tesla.cn/oauth2/v3/token`
- Fleet API: `https://fleet-api.prd.cn.vn.cloud.tesla.cn`
- Redirect URI: `https://api.txx.app/oauth/callback`
- Virtual-key enrollment: `https://tesla.cn/_ak/api.txx.app`
- Hosted public key: `https://api.txx.app/.well-known/appspecific/com.tesla.3p.public-key.pem`

## Required secrets

Never commit these values. Production reads them from `/opt/xiaote-backend/secrets/backend.env` with mode `0600`:

```dotenv
TESLA_CLIENT_ID=
TESLA_CLIENT_SECRET=
TOKEN_ENCRYPTION_KEY=
```

`TOKEN_ENCRYPTION_KEY` is a base64-encoded random 32-byte value. Tesla access and refresh tokens are AES-256-GCM encrypted at rest. App session tokens are only stored as SHA-256 hashes.

## API flow

1. iOS calls `POST /v1/auth/start` and opens `authorization_url` in `ASWebAuthenticationSession`.
2. Tesla redirects to the HTTPS backend callback.
3. The backend exchanges the authorization code, encrypts Tesla tokens, and redirects to `teslablekey://oauth/callback` with a two-minute, single-use code.
4. iOS exchanges that code at `POST /v1/auth/exchange` and stores the returned app session in Keychain.
5. Vehicle reads and commands use the app session. The backend rotates Tesla refresh tokens automatically.

Remote commands are allowlisted and sent through Tesla's official `tesla/vehicle-command` proxy. The fleet private key never enters the iOS app or public repository.

## Local verification

```bash
go test ./...
go vet ./...
docker build -t xiaote-backend:test .
```
