# api233Test API

Real-time weight and configuration API for TSS / msTechnologies scale systems.  
Deployed at `https://api233test.scaledata.net`

---

## Project structure

```
ScaleApi/
├── Controllers/
│   └── ScaleController.cs     # All endpoints
├── DTOs/
│   └── ScaleDtos.cs           # Request/response models
├── Services/
│   └── ScaleStore.cs          # In-memory store (swap for SQL later)
├── deploy/
│   ├── nginx-scaleapi.conf    # Nginx with dual ECDSA + RSA certs
│   ├── scaleapi.service       # systemd unit
│   ├── server-setup.sh        # One-time Vultr server provisioning
│   └── deploy.sh              # Build + push from dev machine
├── Program.cs
├── appsettings.json
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

Swagger UI is at the root: `https://api233test.scaledata.net/`

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
| SSH      | `ssh admin@api233test.scaledata.net` |

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

Before running the setup script, add a **DNS A record** for `api233test.scaledata.net` pointing to your server's IP in your DNS provider.

### Run the setup (on the server as root)

One command does everything — installs packages, clones the repo, gets SSL certs, builds, and starts the service:

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Api233Test/main/deploy/server-setup.sh | bash -s -- <vultr-ip>
```

Or if you already have the repo cloned:

```bash
cd ~/Api233Test
bash deploy/server-setup.sh <vultr-ip>
```

This installs:
- Git, Nginx, Certbot, .NET 8 SDK
- Two Let's Encrypt certs:
  - **ECDSA** (default, E8 chain) — for modern browsers
  - **RSA** (R12 chain) — for embedded PLC clients like your AWTX controller
- Builds and publishes the app to `/var/www/scaleapi`
- Starts the `scaleapi` systemd service

---

## Subsequent deploys

```bash
./deploy/deploy.sh
```

Builds, rsync's, restarts the service. ~15 seconds.

---

## Testing the RSA cert (embedded client simulation)

```bash
curl "https://api233test.scaledata.net/api/api233Test/weight?locationId=1&scaleId=1"

curl -X POST https://api233test.scaledata.net/api/api233Test/weight \
  -H "Content-Type: application/json" \
  -d '{"locationId":1,"scaleId":1,"weight":49750.00}'

curl -X POST https://api233test.scaledata.net/api/api233Test/config \
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
    "api233test.scaledata.net",
    GetResponse, nil, nil, nil, 443, 1)
  DebugSend("Get return = " .. result .. "\r\n")
end

-- POST a weight reading
function PostWeight(weight)
  local body = string.format(
    '{"locationId":1,"scaleId":1,"weight":%.2f}', weight)
  local result = awtx.httpclient.POST(
    "/api/api233Test/weight",
    "api233test.scaledata.net",
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
