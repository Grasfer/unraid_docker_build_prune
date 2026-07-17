# Docker Build Cache Prune for Unraid and Linux

Scheduled Bash helpers that remove old, unused Docker build cache before it fills Docker's storage.

Docker build cache can accumulate on any host that performs image builds, including self-hosted Gitea and Forgejo Actions runners. On Unraid it commonly consumes space inside `docker.img`; on a typical Linux host it consumes space on the filesystem containing Docker's data root.

## Included scripts

| Script | Intended system | Storage reporting |
| --- | --- | --- |
| [`unraid_docker_build_prune.sh`](unraid_docker_build_prune.sh) | Unraid with its standard Docker layout | Checks `/var/lib/docker`, which is commonly backed by `docker.img` |
| [`linux_docker_build_prune.sh`](linux_docker_build_prune.sh) | Linux Docker hosts, including rootful and rootless installations | Discovers Docker's data root and reports its filesystem when the daemon is local |

Both scripts:

- Show Docker storage usage before cleanup.
- Remove unused build cache older than 7 days by default.
- Show usage again after cleanup.
- Write complete output to a timestamped log.
- Return a nonzero exit status when a required command fails.

> [!CAUTION]
> Both scripts run `docker builder prune --all --force` with an age filter. Docker defines `--all` here as all **unused build cache**, not all Docker objects. Containers, images, networks, and volumes are not pruned. Deleted cache must be rebuilt during a future Docker build, which can make that build slower.

## Choose a script

Use the Unraid script when installing through the Unraid User Scripts plugin. It intentionally retains the known-working Unraid paths:

```text
/usr/bin/docker
/var/lib/docker
```

Use the Linux script on Ubuntu, Debian, Fedora, Rocky Linux, or another Linux distribution. It discovers:

- The Docker CLI from `PATH` or `DOCKER_BIN`.
- Docker's data root and storage driver from `docker info`.
- The selected Docker context and endpoint.

The Linux version is not intended for macOS, Windows, or Docker Desktop. It can prune a remote Docker daemon selected by a Docker context, but it skips the host filesystem report because the remote path is not locally accessible.

## Unraid installation

### Requirements

- Unraid with Docker enabled.
- Bash and `/usr/bin/docker`, which are standard on Unraid.
- The [User Scripts plugin](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/).
- Root privileges. User Scripts runs scripts as root.

### Install with User Scripts

1. Install **User Scripts** from the Unraid Apps tab if it is not already installed.
2. Open **Settings > User Scripts**.
3. Select **Add New Script** and name it `docker_build_prune`.
4. Open its settings, select **Edit Script**, and replace the contents with [`unraid_docker_build_prune.sh`](unraid_docker_build_prune.sh).
5. Save the script.
6. Run it manually once and review its output and log.
7. Open the schedule dropdown and select **Weekly**. The entry will then show **Scheduled Weekly**.

The built-in weekly schedule is a reasonable starting point and requires no custom cron expression.

### Unraid configuration

The User Scripts editor does not provide fields for these environment variables. To change the defaults, add the desired exports immediately after `set -Eeuo pipefail`:

```bash
export CACHE_MAX_AGE=336h
export LOG_DIR=/mnt/user/appdata/docker-build-prune/logs
```

That example retains 14 days of cache and stores persistent logs in the appdata share.

## Linux installation

### Requirements

- Linux with Bash.
- A working Docker CLI and reachable Docker Engine.
- Permission to use the selected Docker daemon.
- Standard Linux utilities including `df`, `tee`, `date`, and `hostname`.

The script does not require root when the current user already has permission to access Docker. Rootless Docker should be cleaned by the user who owns that Docker daemon.

### Download and inspect

Download the Linux script without executing it automatically:

```bash
curl --fail --silent --show-error \
    --output /tmp/linux_docker_build_prune.sh \
    https://raw.githubusercontent.com/Grasfer/unraid_docker_build_prune/main/linux_docker_build_prune.sh

less /tmp/linux_docker_build_prune.sh
bash -n /tmp/linux_docker_build_prune.sh
```

Install it system-wide after reviewing it:

```bash
sudo install -m 0755 \
    /tmp/linux_docker_build_prune.sh \
    /usr/local/sbin/docker-build-prune
```

Run it manually once:

```bash
sudo /usr/local/sbin/docker-build-prune
```

Do not use `sudo` for a rootless Docker daemon. Run it as the owning user instead.

### Schedule with systemd

Example unit files are included in [`systemd/`](systemd/):

```bash
sudo install -m 0644 \
    systemd/docker-build-prune.service \
    systemd/docker-build-prune.timer \
    /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now docker-build-prune.timer
systemctl list-timers docker-build-prune.timer
```

The included timer runs weekly, persists across downtime, and adds a randomized delay of up to 15 minutes.

The system service targets the root-owned Docker daemon. For rootless Docker, create equivalent user units under `~/.config/systemd/user/` and manage them with `systemctl --user`.

### Schedule with cron

As an alternative, open root's crontab:

```bash
sudo crontab -e
```

Example weekly entry for Sunday at 04:00:

```cron
0 4 * * 0 /usr/local/sbin/docker-build-prune
```

Use the owning user's crontab instead of root's for a rootless Docker daemon.

## Configuration reference

| Variable | Script | Default | Purpose |
| --- | --- | --- | --- |
| `CACHE_MAX_AGE` | Both | `168h` | Remove unused cache older than this duration. |
| `LOG_DIR` | Both | `/tmp` | Directory for timestamped logs. |
| `DOCKER_BIN` | Linux | `docker` from `PATH` | Docker executable name or absolute path. |
| `DOCKER_HOST` | Linux/Docker CLI | Current context | Optionally select a Docker endpoint using Docker's standard environment variable. |

Docker duration values use units such as `h`, `m`, and `s`. Examples:

```text
72h   = 3 days
168h  = 7 days
336h  = 14 days
```

Run the Linux version with custom settings:

```bash
CACHE_MAX_AGE=336h \
LOG_DIR=/var/log/docker-build-prune \
DOCKER_BIN=/usr/bin/docker \
sudo --preserve-env=CACHE_MAX_AGE,LOG_DIR,DOCKER_BIN \
    /usr/local/sbin/docker-build-prune
```

For scheduled Linux use, edit the `Environment=` values in the provided systemd service.

## Logs

The default log name is:

```text
/tmp/docker-build-prune-2026-07-17_14-30-00.log
```

`/tmp` is temporary and logs there may disappear at reboot. Choose a persistent `LOG_DIR` if logs must survive reboot:

- Unraid example: `/mnt/user/appdata/docker-build-prune/logs`
- Linux example: `/var/log/docker-build-prune`

Persistent logs are not automatically rotated. One weekly text log is normally small, but administrators should add a retention policy if they keep logs indefinitely.

## What is removed

The cleanup command is:

```bash
docker builder prune \
    --all \
    --force \
    --filter "until=168h"
```

It removes build-cache records that are both:

1. Unused by an active build.
2. Older than the configured age.

It does not run any of these broader commands:

```text
docker system prune
docker image prune
docker container prune
docker volume prune
```

Do not manually delete Docker-managed files from `/var/lib/docker` or another Docker data root.

## Verify storage usage

Docker object usage:

```bash
docker system df
```

Docker's configured data root and storage driver:

```bash
docker info --format 'Root={{.DockerRootDir}} Driver={{.Driver}}'
```

Filesystem usage for a local daemon:

```bash
docker_root="$(docker info --format '{{.DockerRootDir}}')"
df -h -- "$docker_root"
```

On Unraid, confirm whether the Docker data root is backed by `docker.img`:

```bash
findmnt -T /var/lib/docker
losetup -l | grep docker.img
```

## Frequently asked questions

### Why did the script reclaim `0B` while `docker system df` reports reclaimable cache?

`docker system df` reports unused cache that is potentially reclaimable. The script only removes unused records older than `CACHE_MAX_AGE`. Newer records remain available to speed up future builds.

### Why does some build cache remain after cleanup?

Cache newer than the retention period remains. Cache actively used by a build cannot be removed.

### Does this remove images, containers, or volumes?

No. The scripts only invoke `docker builder prune`; they do not use the broader prune commands listed above.

### Will this clean every Buildx builder?

Not necessarily. `docker builder prune` cleans the cache associated with the selected Docker builder on the selected daemon. Named Buildx builders, remote builders, and Docker-in-Docker runners can maintain separate cache stores.

List available builders with:

```bash
docker buildx ls
```

Those builders may need an explicit, builder-specific cleanup policy. The scripts deliberately do not discover and prune every builder automatically because that would broaden their deletion scope.

### Why are builds slower after cleanup?

Docker must rebuild deleted layers the next time they are needed. Increase `CACHE_MAX_AGE` if keeping more cache is worth the additional disk usage.

## Troubleshooting

- **Docker was not found:** install the Docker CLI, fix `PATH`, or set `DOCKER_BIN` when using the Linux script.
- **Permission denied connecting to Docker:** run the script as an authorized user. Use root for the system Docker daemon, or the owning user for rootless Docker.
- **Docker daemon is unreachable:** verify `docker info` succeeds with the same user and environment used by the schedule.
- **No log after reboot:** `/tmp` is temporary; configure a persistent `LOG_DIR`.
- **Cache grows quickly:** shorten `CACHE_MAX_AGE`, schedule cleanup more often, and check for additional Buildx or Docker-in-Docker caches.
- **Filesystem usage is skipped:** the Linux script detected a remote or unknown Docker endpoint. `docker system df` still reports Docker object usage from the selected daemon.

## Safety and support

These are community scripts and are not affiliated with or supported by Unraid or Docker. Review the source, run it manually, and verify the result before scheduling it. Build cache is disposable acceleration data, not a backup.

## License

No license has been selected yet. Add a license before encouraging redistribution or accepting contributions.

## References

- [Docker: `docker builder prune`](https://docs.docker.com/reference/cli/docker/builder/prune/)
- [Docker: prune unused objects](https://docs.docker.com/engine/manage-resources/pruning/)
- [Docker: CLI environment variables](https://docs.docker.com/engine/reference/commandline/cli/)
