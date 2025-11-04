# Parachute Deployment Guide

This guide covers deploying the Parachute backend server for daily driver use.

## Overview

**Architecture for Daily Use:**
```
Phone (Flutter App)
  ↓ HTTP/WebSocket
Server (Docker Container)
  ↓ File System
Obsidian Vault (~/Obsidian/Parachute/ or ~/Parachute/)
  ↓ Obsidian Sync/Git/Syncthing
Other Devices (Desktop, Tablet, etc.)
```

**Benefits:**
- Phone uploads recordings → Server writes to vault → Sync propagates everywhere
- Works offline on phone (local storage, uploads when online)
- Works offline on desktop (direct vault access)
- Obsidian handles cross-device sync with E2E encryption
- All data in standard formats (markdown, audio files)

---

## Quick Start with Docker

### Prerequisites

- Docker and Docker Compose installed
- An Obsidian vault or Parachute folder to mount
- (Optional) Anthropic API key or Claude OAuth credentials

### 1. Configure Environment

Copy the example environment file:
```bash
cp .env.example .env
```

Edit `.env` and set your vault path:
```bash
# Point to your Obsidian vault or Parachute folder
VAULT_PATH=/Users/yourname/Obsidian/Parachute

# Or use home directory shorthand
VAULT_PATH=~/Parachute
```

### 2. Start the Server

```bash
docker-compose up -d
```

This will:
- Build the backend Docker image
- Mount your vault at `/vault` inside the container
- Start the server on `http://localhost:8080`
- Persist the database in a Docker volume

### 3. Verify It's Running

Check the health endpoint:
```bash
curl http://localhost:8080/health
```

View logs:
```bash
docker-compose logs -f
```

### 4. Configure Your Flutter App

In the Parachute mobile app:
1. Go to Settings
2. Set Backend URL to your server's IP (e.g., `http://192.168.1.100:8080`)
3. Make a test recording to verify sync

---

## Deployment Options

### Option 1: Home Server / NAS

**Best for:** Complete control, privacy, local network access

**Setup:**
1. Run Docker Compose on your NAS (Synology, QNAP, etc.)
2. Point vault to a network share
3. Access via local IP from phone when on WiFi
4. Use VPN for remote access

**Pros:**
- Full control of data
- No cloud costs
- Fast local access

**Cons:**
- Requires home server or NAS
- Need VPN for remote access

### Option 2: Cloud VPS

**Best for:** Access anywhere, no home server needed

**Recommended providers:**
- DigitalOcean ($6/month)
- Linode ($5/month)
- Vultr ($6/month)

**Setup:**
```bash
# SSH into your VPS
ssh user@your-vps-ip

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Clone Parachute
git clone https://github.com/yourusername/parachute.git
cd parachute

# Configure
cp .env.example .env
nano .env  # Set VAULT_PATH

# Start
docker-compose up -d
```

**Pros:**
- Access from anywhere
- No VPN needed
- Reliable uptime

**Cons:**
- Monthly cost (~$5-10)
- Data stored in cloud (but encrypted in transit)

### Option 3: Tailscale + Home Server

**Best for:** Secure remote access without port forwarding

**Setup:**
1. Install Tailscale on your home server and phone
2. Run Parachute on home server via Docker
3. Access via Tailscale IP from anywhere

**Pros:**
- Secure WireGuard VPN
- No port forwarding
- Data stays at home

**Cons:**
- Requires Tailscale setup
- Slightly more complex

---

## Integration with Obsidian

### Vault Structure

The server writes to your vault in this structure:
```
~/Obsidian/Parachute/          # or ~/Parachute/
├── captures/                   # Voice recordings
│   ├── YYYY-MM-DD_HH-MM-SS.md # Transcript
│   ├── YYYY-MM-DD_HH-MM-SS.wav
│   └── YYYY-MM-DD_HH-MM-SS.json
│
└── spaces/                     # AI conversation spaces
    ├── project-name/
    │   ├── SPACE.md           # System prompt
    │   ├── space.sqlite       # Knowledge graph
    │   └── files/
    └── another-space/
```

### Sync Options

**Option A: Obsidian Sync (Recommended)**
- Enable Obsidian Sync on desktop/mobile
- Vault syncs automatically with E2E encryption
- No additional setup needed

**Option B: Git**
- Initialize git repo in vault
- Push to private GitHub/GitLab
- Pull on other devices
- Good for version control

**Option C: Syncthing**
- Open-source, peer-to-peer sync
- No cloud needed
- Requires Syncthing on all devices

### Obsidian Configuration

To view recordings in Obsidian:

1. **Audio Plugin**: Install "Audio Player" plugin
2. **Markdown Links**: Recordings use standard markdown links
3. **Graph View**: See connections between notes and spaces

---

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `VAULT_PATH` | Path to your vault | `~/Parachute` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key | (uses OAuth) |
| `SERVER_PORT` | Port to listen on | `8080` |
| `SERVER_HOST` | Host to bind to | `0.0.0.0` |
| `DB_PATH` | SQLite database path | `/app/data/parachute.db` |

---

## Anthropic API Authentication

The server supports two authentication methods:

### Method 1: OAuth (Default)

Mount your Claude credentials:
```yaml
volumes:
  - ~/.claude:/root/.claude:ro
```

The server will use your Claude OAuth tokens automatically.

### Method 2: API Key

Set the environment variable:
```bash
export ANTHROPIC_API_KEY=your-key-here
docker-compose up -d
```

Or add to `.env`:
```bash
ANTHROPIC_API_KEY=your-key-here
```

---

## Monitoring & Maintenance

### View Logs

```bash
# Follow logs
docker-compose logs -f

# Last 100 lines
docker-compose logs --tail=100
```

### Restart Server

```bash
docker-compose restart
```

### Update to Latest Version

```bash
git pull
docker-compose down
docker-compose up -d --build
```

### Backup

The important data to backup:
1. **Vault folder**: Your recordings and notes (already in Obsidian/Git)
2. **Database**: `docker volume inspect parachute_parachute-data`

Backup database:
```bash
docker-compose exec parachute-backend cp /app/data/parachute.db /vault/backup.db
```

---

## Troubleshooting

### Server won't start

Check logs:
```bash
docker-compose logs
```

Common issues:
- **Port 8080 in use**: Change `SERVER_PORT` in `.env`
- **Vault path doesn't exist**: Create the directory first
- **Permission denied**: Ensure Docker has access to vault path

### Phone can't connect

1. **Check firewall**: Allow port 8080
2. **Use server IP, not localhost**: e.g., `192.168.1.100:8080`
3. **Test from terminal**:
   ```bash
   curl http://your-server-ip:8080/health
   ```

### Recordings not appearing in Obsidian

1. **Check vault path**: Ensure `VAULT_PATH` is correct
2. **Check permissions**: Server must have write access to vault
3. **Force Obsidian refresh**: Close and reopen vault

### Background transcription not working

1. **Check logs**: Look for transcription errors
2. **API key**: Ensure Anthropic or OpenAI API key is set
3. **Auto-transcribe enabled**: Check app Settings

---

## Security Considerations

### For Home Server

- **Firewall**: Only open port 8080 if needed
- **VPN recommended**: Use Tailscale/WireGuard instead of port forwarding
- **HTTPS**: Use reverse proxy (nginx, Caddy) for SSL

### For Cloud VPS

- **Enable HTTPS**: Use Caddy or Certbot for Let's Encrypt
- **Firewall rules**: Only allow ports 80, 443, and SSH
- **SSH key auth**: Disable password authentication
- **Vault encryption**: Consider encrypting vault at rest

### Example HTTPS Setup with Caddy

```bash
# Install Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/setup.deb.sh' | sudo bash
sudo apt install caddy

# Configure Caddy
sudo nano /etc/caddy/Caddyfile
```

```
parachute.yourdomain.com {
    reverse_proxy localhost:8080
}
```

```bash
sudo systemctl reload caddy
```

---

## Next Steps

1. **Deploy the server** using one of the options above
2. **Configure your phone** to connect to the server
3. **Make a test recording** to verify sync works
4. **Set up Obsidian Sync** to propagate recordings to other devices
5. **Enable auto-transcribe** in app settings

**Questions?** See [ARCHITECTURE.md](../ARCHITECTURE.md) for technical details or [CLAUDE.md](../CLAUDE.md) for development guidance.
