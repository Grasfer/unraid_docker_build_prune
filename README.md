# unraid_docker_build_prune
Removes unused Docker build cache older than 7 days to prevent docker.img from filling up.

Logs will look like:

  /tmp/docker-build-prune-2026-07-17_14-30-00.log

  /tmp is cleared when Unraid reboots. For the GitHub description:

  > Unraid User Scripts helper that prunes unused Docker BuildKit cache older than seven days and writes timestamped before-and-after logs.
