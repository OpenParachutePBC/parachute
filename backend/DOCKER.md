# Quick Docker Deployment

Deploy Parachute backend with your Obsidian vault in 3 minutes.

## 1. Set Your Vault Path

```bash
export VAULT_PATH=~/Obsidian/Parachute
# Or wherever your vault lives
```

## 2. Start the Server

```bash
docker-compose up -d
```

## 3. Verify

```bash
curl http://localhost:8080/health
```

## 4. Configure Your Phone

In the Parachute app:
- Settings → Backend URL
- Enter your server's IP: `http://192.168.1.100:8080`
- Make a test recording

## What Just Happened?

- Server is running at `http://localhost:8080`
- Your vault is mounted at `/vault` inside the container
- Recordings will appear in `$VAULT_PATH/captures/`
- Database is persisted in a Docker volume
- Obsidian Sync will propagate recordings to other devices

## Next Steps

- **Remote Access**: See [docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md) for VPS/Tailscale setup
- **HTTPS**: Use Caddy or nginx for SSL (see deployment docs)
- **Monitoring**: `docker-compose logs -f` to watch activity

## Common Issues

**Port 8080 in use?**
```bash
export SERVER_PORT=8081
docker-compose up -d
```

**Can't connect from phone?**
- Use your server's local IP (not `localhost`)
- Check firewall allows port 8080
- Test with: `curl http://YOUR_SERVER_IP:8080/health`

**Recordings not appearing?**
- Check vault path is correct
- Ensure server has write permissions
- View logs: `docker-compose logs`

---

**Full Documentation**: [../docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md)
