# HomeStack

A plug-and-play CLI for managing self-hosted Docker services.

## Installation

### Standard Installation (Ubuntu/Debian with sudo)

One command to install everything (Docker, Compose, SQLite, HomeStack):

```bash
curl -fsSL https://raw.githubusercontent.com/filippvizvary/homestack/main/setup.sh | sudo bash
```

Or clone and run manually:

```bash
git clone https://github.com/filippvizvary/homestack.git /homestack
cd /homestack
sudo ./setup.sh
```

The setup script automatically installs all dependencies (Docker, Docker Compose plugin, sqlite3, git) on Ubuntu, Debian, Fedora, CentOS, and RHEL.

### Minimal Debian Installation (without sudo)

For minimal Debian installs that don't have `sudo` installed or have PATH issues:

```bash
# Switch to root
su -

# Download and run the minimal Debian setup script
curl -fsSL https://raw.githubusercontent.com/filippvizvary/homestack/main/setup-minimal-debian.sh -o setup-minimal-debian.sh
bash setup-minimal-debian.sh
```

This script will:
- Install `sudo` and fix PATH configuration
- Install Docker and required dependencies
- Create a `homestack` system user with proper permissions
- Set up HomeStack and make it globally accessible

After installation, switch to the homestack user:

```bash
su - homestack
homestack search
```

## Quick Start

```bash
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
| `homestack config show <app>` | Display current configuration for an app |
| `homestack config edit <app> <key> <value>` | Modify a config value and optionally restart |
| `homestack config reset <app> <key>` | Reset a config key to catalog default |
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

## Branching Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable, released code. Tagged with version numbers (e.g., `v0.3.0`). |
| `dev` | Integration branch for the next release. All feature/fix branches merge here first. |
| `feat/*` | New features (e.g., `feat/config-edit`, `feat/dependency-resolution`) |
| `fix/*` | Bug fixes (e.g., `fix/lock-race-condition`) |
| `test/*` | Test additions or refactors |

### Workflow

```
feat/my-feature ──► dev ──► main (tagged release)
fix/my-bugfix   ──► dev ──► main
```

1. Create a branch from `dev` using the appropriate prefix
2. Make your changes and push
3. Open a PR targeting `dev`
4. Once `dev` is stable and tested, PR `dev` → `main` and tag a release

## Contributing

To contribute **apps**, see the [homestack-apps](https://github.com/filippvizvary/homestack-apps) repository.

To contribute to the **CLI**:

1. Fork this repository
2. Create a branch from `dev` (e.g., `feat/my-feature` or `fix/my-bugfix`)
3. Make your changes and add tests where applicable
4. Open a pull request targeting the `dev` branch

Do **not** open PRs directly against `main` — all changes flow through `dev`.

## License

MIT
