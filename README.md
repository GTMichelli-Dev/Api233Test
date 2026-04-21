# api233Test API

Real-time weight and configuration API for TSS / msTechnologies scale systems.  
Deployed at `https://zm233apitest.scaledata.net`

---

## Project structure

```
Api233Test/
├── Controllers/
│   └── Api233TestController.cs  # All endpoints
├── DTOs/
│   └── ScaleDtos.cs             # Request/response models
├── Services/
│   └── ScaleStore.cs            # In-memory store (swap for SQL later)
├── deploy/
│   ├── nginx-scaleapi.conf      # Nginx with dual ECDSA + RSA certs
│   ├── scaleapi.service         # systemd unit
│   ├── server-setup.sh          # One-time server provisioning (single script)
│   └── deploy.sh                # Build + push from dev machine
├── Program.cs
└── ScaleApi.csproj
```

---

## Endpoints

| Method | Route                          | Description                          |
|--------|--------------------------------|--------------------------------------|
| GET    | `/api/api233Test/config`       | Get scale configuration              |
| GET    | `/api/api233Test/weight`       | Get current weight + deviation       |
| POST   | `/api/api233Test/weight`       | Push a new weight reading            |
| POST   | `/api/api233Test/config`       | Create / update scale configuration  |

Swagger UI is at the root: `https://zm233apitest.scaledata.net/`

---

## Deviation calculation

```
Deviation = Weight - Target
```
Negative = under target, positive = over target.

---

## Server access

| Item     | Value                          |
|----------|--------------------------------|
| User     | `admin`                        |
| Password | *(set during setup — see below)* |
| SSH      | `ssh admin@zm233apitest.scaledata.net` |

### Create the admin user

First, SSH in as root:

```bash
ssh root@<vultr-ip>
```

Then create the admin user:

```bash
useradd -m -s /bin/bash -G sudo admin
read -rsp "Enter password for admin: " ADMIN_PASS && echo
echo "admin:$ADMIN_PASS" | chpasswd
```

---

## First-time Vultr deploy

### Prerequisites

Before running the setup script, add a **DNS A record** for `zm233apitest.scaledata.net` pointing to your server's IP in your DNS provider.

### Run the setup (on the server as root)

One command does everything — installs packages, clones the repo, gets SSL certs, builds, and starts the service:

```bash
apt update && apt install -y git
git clone https://github.com/GTMichelli-Dev/Api233Test.git ~/Api233Test
cd ~/Api233Test
bash deploy/server-setup.sh <vultr-ip>
```

Or if you already have the repo cloned:

```bash
cd ~/Api233Test
git pull
bash deploy/server-setup.sh <vultr-ip>
```

This installs:
- Git, Nginx, Certbot, .NET 8 SDK
- Two Let's Encrypt certs:
  - **ECDSA** on P-256 / secp256r1 (E8 chain) — for modern browsers and mbedTLS clients
  - **RSA** (R12 chain) — for embedded PLC clients like your AWTX controller
- Builds and publishes the app to `/var/www/scaleapi`
- Starts the `scaleapi` systemd service

---

## Re-issuing the ECDSA cert on P-256

If the server already has an ECDSA cert on a different curve (e.g. P-384),
mbedTLS clients will fail with `Elliptic curve is unsupported (only NIST
curves are supported)`. Re-issue the cert on P-256 with `--force-renewal`:

```bash
certbot certonly --nginx \
    --non-interactive --agree-tos --email <your-email> \
    -d zm233apitest.scaledata.net \
    --cert-name zm233apitest.scaledata.net-ecdsa \
    --key-type ecdsa \
    --elliptic-curve secp256r1 \
    --force-renewal

systemctl reload nginx
```

---

## Subsequent deploys

```bash
./deploy/deploy.sh
```

Builds, rsync's, restarts the service. ~15 seconds.

---

## Testing the RSA cert (embedded client simulation)

```bash
curl "https://zm233apitest.scaledata.net/api/api233Test/weight?locationId=1&scaleId=1"

curl -X POST https://zm233apitest.scaledata.net/api/api233Test/weight \
  -H "Content-Type: application/json" \
  -d '{"locationId":1,"scaleId":1,"weight":49750.00}'

curl -X POST https://zm233apitest.scaledata.net/api/api233Test/config \
  -H "Content-Type: application/json" \
  -d '{"locationId":1,"scaleId":1,"target":50000,"underThreshold":500,"overThreshold":500,"submitThreshold":49800}'
```

---

## Lua client code (AWTX controller)

```lua
-- GET weight for location 1, scale 1
function GetWeight()
  local result = awtx.httpclient.GET(
    "/api/api233Test/weight?locationId=1&scaleId=1",
    "zm233apitest.scaledata.net",
    GetResponse, nil, nil, nil, 443, 1)
  DebugSend("Get return = " .. result .. "\r\n")
end

-- POST a weight reading
function PostWeight(weight)
  local body = string.format(
    '{"locationId":1,"scaleId":1,"weight":%.2f}', weight)
  local result = awtx.httpclient.POST(
    "/api/api233Test/weight",
    "zm233apitest.scaledata.net",
    body, "application/json",
    GetResponse, nil, nil, nil, 443, 1)
  DebugSend("Post return = " .. result .. "\r\n")
end
```

---

## Swapping in-memory store for SQL Server

The `IScaleStore` interface is the only thing that needs changing.  
Replace `ScaleStore` with an EF Core / Dapper implementation — `Program.cs` registration is one line:

```csharp
// builder.Services.AddSingleton<IScaleStore, ScaleStore>();
builder.Services.AddScoped<IScaleStore, SqlScaleStore>();
```
