# api233Test API

Real-time weight and configuration API for TSS / msTechnologies scale systems.  
Deployed at `https://george.scaledata.net`

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

Swagger UI is at the root: `https://george.scaledata.net/`

---

## Deviation calculation

```
Deviation = Weight - Target
```
Negative = under target, positive = over target.

---

## First-time Vultr deploy

### 1. On the server

```bash
scp deploy/scaleapi.service root@<vultr-ip>:/tmp/
bash deploy/server-setup.sh george.scaledata.net your@email.com
```

This installs:
- .NET 8 runtime
- Nginx
- Certbot
- Two Let's Encrypt certs:
  - **ECDSA** (default, E8 chain) — for modern browsers
  - **RSA** (R12 chain) — for embedded PLC clients like your AWTX controller

### 2. From your dev machine (Git Bash or WSL)

```bash
chmod +x deploy/deploy.sh
./deploy/deploy.sh root@<vultr-ip>
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
curl "https://george.scaledata.net/api/api233Test/weight?locationId=1&scaleId=1"

curl -X POST https://george.scaledata.net/api/api233Test/weight \
  -H "Content-Type: application/json" \
  -d '{"locationId":1,"scaleId":1,"weight":49750.00}'

curl -X POST https://george.scaledata.net/api/api233Test/config \
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
    "george.scaledata.net",
    GetResponse, nil, nil, nil, 443, 1)
  DebugSend("Get return = " .. result .. "\r\n")
end

-- POST a weight reading
function PostWeight(weight)
  local body = string.format(
    '{"locationId":1,"scaleId":1,"weight":%.2f}', weight)
  local result = awtx.httpclient.POST(
    "/api/api233Test/weight",
    "george.scaledata.net",
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
