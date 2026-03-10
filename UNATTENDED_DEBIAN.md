# HomeStack Unattended Debian Install

This guide installs Debian automatically via preseed, then bootstraps HomeStack on first boot.

## 1) Prepare artifacts on your host

From the HomeStack repository:

```bash
cd deploy/unattended-debian
cp bootstrap.env.example bootstrap.env
```

Edit `bootstrap.env`:
- Set `HOMESTACK_REAL_USER` to the Debian installer-created admin login.
- Optionally set `TZ`, `PUID`, `PGID`, and `HOMESTACK_APPS_REPO`.
- Keep `NONINTERACTIVE=1`.

Then edit `preseed.cfg`:
- Replace `HOST_IP` with the IP of the machine serving these files.
- Replace `passwd/user-password-crypted` value with a real hash from:
  ```bash
  openssl passwd -6
  ```

Serve files over HTTP on your local network:

```bash
python3 -m http.server 8000
```

## 2) Boot Debian installer in unattended mode

At Debian installer boot menu, append:

```text
auto=true priority=critical preseed/url=http://HOST_IP:8000/preseed.cfg
```

The installer will:
- install Debian,
- fetch first-boot artifacts,
- enable `homestack-firstboot.service`.

## 3) First boot behavior

`homestack-firstboot.service` runs once and executes:

- `/usr/local/sbin/homestack-firstboot.sh`
- clones HomeStack into `/homestack` if missing,
- runs `setup.sh` with `NONINTERACTIVE=1`,
- creates sentinel file: `/var/lib/homestack-firstboot.done`,
- disables itself after success.

## 4) Validation commands

On the target VM after boot:

```bash
systemctl status homestack-firstboot.service
journalctl -u homestack-firstboot.service -b --no-pager
homestack doctor
homestack catalog update
```

Optional smoke test:

```bash
homestack install uptimekuma --defaults
homestack status uptimekuma
```

## 5) Security notes

- Use strong hashed passwords in preseed.
- Keep `bootstrap.env` mode `0600` (contains deployment settings).
- Serve preseed/bootstrap only on trusted network.
- Pin `HOMESTACK_REPO_URL` to your internal mirror or a vetted source for stricter supply-chain control.

## 6) Build a custom Debian ISO (optional)

If you want no network dependency for preseed delivery:

1. Extract official Debian netinst ISO.
2. Add `preseed.cfg` into ISO filesystem.
3. Update bootloader config to include `auto=true priority=critical preseed/file=/cdrom/preseed.cfg`.
4. Repack and sign/checksum ISO.

The first-boot flow can still use local files embedded in image build tooling, or continue using LAN HTTP for `bootstrap.env` rotation.
