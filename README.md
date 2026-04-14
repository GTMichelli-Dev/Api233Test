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
| Password | `Scale_Us3r`                   |
| SSH      | `ssh admin@api233test.scaledata.net` |

### Create the admin user

First, SSH in as root:

```bash
ssh root@<vultr-ip>
```

Then create the admin user:

```bash
useradd -m -s /bin/bash -G sudo admin
echo 'admin:Scale_Us3r' | chpasswd
```

---

## First-time Vultr deploy

### 0. Prerequisites

Before running the setup script, make sure:

1. **DNS** — Add an A record for `api233test.scaledata.net` pointing to your server's IP (e.g. `207.148.13.214`) in your DNS provider.
2. **Firewall** — Open ports 80 and 443:
   ```bash
   ufw allow 80
   ufw allow 443
   ufw reload
   ```

Certbot needs both of these to issue SSL certificates.

### 1. On the server

```bash
apt update && apt install -y git
git clone https://github.com/GTMichelli-Dev/Api233Test.git
cd Api233Test
cp deploy/scaleapi.service /tmp/
bash deploy/server-setup.sh
```

This installs:
- .NET 8 runtime
- Nginx
- Certbot
- Two Let's Encrypt certs:
  - **ECDSA** (default, E8 chain) — for modern browsers
  - **RSA** (R12 chain) — for embedded PLC clients like your AWTX controller

### 2. Build and start the app (on the server)

```bash
# Install .NET SDK
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet

# Build and publish
cd ~/Api233Test
dotnet publish -c Release -o /var/www/scaleapi
```

#### From your dev machine (Git Bash or WSL)

```bash
chmod +x deploy/deploy.sh
./deploy/deploy.sh admin@<vultr-ip>
```

#### Start the service (on the server)

```bash
systemctl restart scaleapi
systemctl status scaleapi
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
