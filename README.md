# Unraid Docker Build Cache Prune

A small [Unraid User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/) helper that removes unused Docker build cache older than a configurable age.

This is useful on Unraid systems that run Docker builds, such as Gitea or Forgejo Actions runners. BuildKit cache is normally stored under Docker's data root and can consume space inside `docker.img` over time.

The script:

- Shows Docker and `docker.img` usage before cleanup.
- Removes unused build cache older than 7 days by default.
- Shows usage again after cleanup.
- Writes the complete output to a timestamped log.
- Returns a nonzero exit status if a command fails.

> [!CAUTION]
> The script runs `docker builder prune --all --force`. The age filter limits cleanup to unused build cache older than the configured retention period. It does not prune containers, images, networks, or volumes, but deleted build cache will need to be rebuilt during a future Docker build.

## Requirements

- Unraid with Docker enabled.
- Bash and the Docker CLI at `/usr/bin/docker` (standard on Unraid).
- Root privileges. The User Scripts plugin runs scripts as root.
- The [User Scripts plugin](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/) for GUI installation and scheduling.

## Install with Unraid User Scripts

1. Install **User Scripts** from the Unraid Apps tab if it is not already installed.
2. Open **Settings > User Scripts**.
3. Select **Add New Script** and name it `docker_build_prune`.
4. Select the script's settings icon, choose **Edit Script**, and replace its contents with [`docker_build_prune.sh`](docker_build_prune.sh).
5. Save the script.
6. Run it manually once and review the output and log.
7. Set a schedule. Weekly is a reasonable starting point; for example, Sunday at 04:00 with custom cron:

   ```cron
   0 4 * * 0
   ```

Schedule it when Docker builds are unlikely to be running. Adjust the retention period if builds run less frequently than once a week.

## Manual installation

Download and inspect the script before running it:

```bash
curl --fail --silent --show-error \
    --output /tmp/docker_build_prune.sh \
    https://raw.githubusercontent.com/Grasfer/unraid_docker_build_prune/main/docker_build_prune.sh

less /tmp/docker_build_prune.sh
bash /tmp/docker_build_prune.sh
```

## Configuration

The defaults can be overridden with environment variables when starting the script from a shell:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CACHE_MAX_AGE` | `168h` | Removes unused cache older than this duration. |
| `LOG_DIR` | `/tmp` | Directory in which timestamped logs are written. |

Example: retain 14 days of cache and keep logs on persistent storage:

```bash
CACHE_MAX_AGE=336h \
LOG_DIR=/mnt/user/appdata/docker-build-prune/logs \
bash /tmp/docker_build_prune.sh
```

When using the User Scripts editor, either change the defaults near the top of the script or add these lines immediately after `set -Eeuo pipefail`:

```bash
export CACHE_MAX_AGE=336h
export LOG_DIR=/mnt/user/appdata/docker-build-prune/logs
```

Docker duration values use units such as `h`, `m`, and `s`. For example, `72h` is 3 days and `336h` is 14 days.

## Logs

By default, each run creates a log like:

```text
/tmp/docker-build-prune-2026-07-17_14-30-00.log
```

Unraid stores `/tmp` in RAM, so these logs are cleared at reboot. Set `LOG_DIR` to a persistent pool or share path if logs must survive a reboot. Persistent logs are not automatically rotated by this script.

## Verify Docker storage usage

Check Docker's object usage and the filesystem that contains Docker's data root:

```bash
docker system df
df -h /var/lib/docker
```

To confirm whether `/var/lib/docker` is backed by an Unraid `docker.img` loop device:

```bash
findmnt -T /var/lib/docker
losetup -l | grep docker.img
```

Do not manually delete files under `/var/lib/docker`. Let Docker manage its own storage.

## Frequently asked questions

### Why did the script reclaim `0B` while Docker reports reclaimable build cache?

`docker system df` reports cache that is unused and potentially reclaimable. The script only removes unused records older than `CACHE_MAX_AGE`. Newer records remain available to speed up future builds.

### Does this remove Docker images or containers?

No. It only invokes `docker builder prune`. It does not run `docker system prune`, `docker image prune`, `docker container prune`, or `docker volume prune`.

### Why does build cache remain after cleanup?

Cache newer than the retention period remains. Cache actively used by a build is not removed either.

### Will this clean every Buildx builder?

Not necessarily. The script cleans the cache managed by `docker builder prune` on the host Docker daemon. A separate named Buildx builder, a remote builder, or a Docker-in-Docker runner can maintain a different cache. List builders with:

```bash
docker buildx ls
```

Those builders may require a separate, builder-specific cleanup policy.

## Troubleshooting

- **Docker command fails:** confirm Docker is enabled in Unraid and `/usr/bin/docker info` succeeds.
- **No log after reboot:** `/tmp` is intentionally temporary; configure a persistent `LOG_DIR`.
- **Cache grows quickly:** shorten `CACHE_MAX_AGE`, run the script more often, and check whether CI jobs use additional Buildx builders or Docker-in-Docker.
- **Builds are slower after cleanup:** this is expected until the deleted layers are rebuilt.

## Safety and scope

This is a community script and is not affiliated with or supported by Unraid. Review the source and test it manually before scheduling it. Keep backups of important application data; build cache is not a backup.

## License

No license has been selected yet. Add a license before encouraging redistribution or contributions.

## References

- [Docker: `docker builder prune`](https://docs.docker.com/reference/cli/docker/builder/prune/)
- [Docker: prune unused objects](https://docs.docker.com/engine/manage-resources/pruning/)

