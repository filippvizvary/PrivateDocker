# HomeStack

A plug-and-play CLI for managing self-hosted Docker services.

## Quick Start

```bash
# Install HomeStack (as root)
sudo ./setup.sh

# Browse available apps
homestack search

# Install an app
homestack install immich

# Check status
homestack status
```

## Commands

| Command | Description |
|---------|-------------|
| `homestack install <app>` | Install and start an app |
| `homestack remove <app>` | Stop and uninstall an app |
| `homestack start [app]` | Start one or all installed apps |
| `homestack stop [app]` | Stop one or all installed apps |
| `homestack restart [app]` | Restart one or all installed apps |
| `homestack status` | Show status of all installed apps |
| `homestack update <app>` | Update an app to the latest catalog version |
| `homestack backup [app]` | Backup AppData for one or all apps |
| `homestack list` | List installed apps |
| `homestack search [query]` | Search the app catalog |

## Available Apps

| App | Category | Port | Description |
|-----|----------|------|-------------|
| immich | media | 2283 | Self-hosted photo & video backup |
| jellyfin | media | 8096 | Free media streaming server |
| n8n | automation | 5678 | Workflow automation platform |
| nextcloud | cloud | 4432 | Self-hosted productivity platform |
| jellyseerr | servarr | 5055 | Media request manager for Jellyfin |
| prowlarr | servarr | 9696 | Indexer manager for Servarr |
| qbittorrent | servarr | 8080 | BitTorrent client with web UI |
| radarr | servarr | 7878 | Movie collection manager |
| uptimekuma | monitoring | 3001 | Self-hosted uptime monitoring |
| vaultwarden | security | 8000 | Lightweight Bitwarden-compatible vault |

## Directory Structure

```
/homestack/
├── bin/homestack          # CLI entrypoint
├── lib/                   # Core libraries & commands
│   ├── core.sh            # Shared functions & helpers
│   ├── yaml.sh            # YAML parser for app.yaml
│   ├── secrets.sh         # Secret generation & prompts
│   ├── registry.sh        # App catalog discovery
│   └── commands/          # One file per CLI command
├── apps/                  # App catalog (app packages)
│   └── <app>/
│       ├── app.yaml       # Manifest (metadata, secrets spec)
│       ├── compose.yaml   # Docker Compose definition
│       └── config.env     # Image tags & default config
├── installed/             # Live copies of installed apps
│   └── <app>/
│       ├── app.yaml
│       ├── compose.yaml
│       ├── config.env
│       └── secrets.env    # Generated at install (gitignored)
├── config/
│   └── homestack.env      # Global config (TZ, PUID, paths)
├── AppData/               # Persistent data per app
├── Backups/               # Backup archives
├── Media/                 # Shared media library
├── setup.sh               # One-line bootstrap
└── README.md
```

## App Package Format

Each app is a self-contained package with three files:

**app.yaml** — Manifest defining metadata, requirements, and secrets:

```yaml
name: myapp
display_name: My App
description: What it does
version: 1.0.0
category: media
port: 8080
priority: 50
networks: [media-net]
appdata_dirs: [myapp]
media_dirs: [Downloads]
secrets:
  - key: DB_PASSWORD
    prompt: "Database password"
    generate: true
    length: 32
```

**compose.yaml** — Standard Docker Compose using `${VAR}` substitution.

**config.env** — Image tags and non-secret app config.

## Configuration

| File | Purpose |
|------|---------|
| `config/homestack.env` | Global paths, timezone, PUID/PGID |
| `apps/<app>/config.env` | Per-app image tags & defaults |
| `installed/<app>/secrets.env` | Per-app secrets (auto-generated) |

## Contributing Apps

1. Create a new directory under `apps/` with `app.yaml`, `compose.yaml`, and `config.env`
2. Follow the app package format above
3. Test with `homestack install <your-app>`
4. Submit a PR

## License

MIT
