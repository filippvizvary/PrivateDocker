# HomeStack

A plug-and-play CLI for managing self-hosted Docker services.

## Quick Start

```bash
# Install HomeStack (as root)
sudo ./setup.sh

# Sync app catalog
homestack catalog update

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
| `homestack update [app]` | Update an app to the latest catalog version |
| `homestack backup [app]` | Backup AppData and config for one or all apps |
| `homestack restore <app>` | Restore an app from a backup |
| `homestack list` | List installed apps |
| `homestack search [query]` | Search the app catalog |
| `homestack catalog [update]` | Sync app catalog from remote repository |
| `homestack log [N]` | Show last N audit log entries |

## Available Apps

Apps are managed in a separate community repository: [homestack-apps](https://github.com/filippvizvary/homestack-apps)

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

## Architecture

```
/homestack/
├── bin/homestack          # CLI entrypoint
├── lib/                   # Core libraries & commands
│   ├── core.sh            # Shared functions & helpers
│   ├── yaml.sh            # YAML parser for app.yaml
│   ├── secrets.sh         # Secret generation & prompts
│   ├── registry.sh        # App catalog fetch & discovery
│   ├── db.sh              # SQLite database layer
│   └── commands/          # One file per CLI command
├── .cache/                # Cached app catalog (auto-fetched)
│   └── homestack-apps/    # Cloned from homestack-apps repo
│       └── apps/
├── installed/             # Live copies of installed apps
│   └── <app>/
│       ├── app.yaml
│       ├── compose.yaml
│       ├── config.env
│       └── secrets.env    # Generated at install (gitignored)
├── config/
│   └── homestack.env      # Global config (TZ, PUID, paths)
├── homestack.db           # SQLite state database
├── AppData/               # Persistent data per app
├── Backups/               # Backup archives
├── Media/                 # Shared media library
├── setup.sh               # One-line bootstrap
└── README.md
```

## How it works

1. **Catalog** — App definitions are stored in the [homestack-apps](https://github.com/filippvizvary/homestack-apps) repository. Run `homestack catalog update` to fetch/refresh them into `.cache/`.

2. **Install** — `homestack install <app>` copies app files to `installed/<app>/`, generates secrets, creates networks/directories, and starts containers.

3. **State** — A SQLite database (`homestack.db`) tracks installed versions, config overrides, backups, container health, and an audit log of all actions.

4. **Update** — `homestack update` compares installed vs catalog versions, performs a smart config merge (preserving user edits), handles new secrets, and recreates containers.

5. **Backup** — `homestack backup` stops containers for safe backup, archives both AppData and config files, and records backups in the database with rotation.

## Configuration

| File | Purpose |
|------|---------|
| `config/homestack.env` | Global paths, timezone, PUID/PGID, catalog repo URL |
| `installed/<app>/config.env` | Per-app image tags & defaults |
| `installed/<app>/secrets.env` | Per-app secrets (auto-generated, chmod 600) |
| `homestack.db` | SQLite state database |

## Dependencies

- Docker with Compose plugin
- `git` (for catalog sync)
- `sqlite3` (for state management)
- `bash` 4.0+

## Contributing

To contribute **apps**, see the [homestack-apps](https://github.com/filippvizvary/homestack-apps) repository.

To contribute to the **CLI**, open issues or PRs in this repository.

## License

MIT
