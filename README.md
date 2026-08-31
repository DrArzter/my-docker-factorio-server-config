# Factorio server profiles

Authoring source for Factorio server configurations based on
[`factoriotools/factorio`](https://github.com/factoriotools/factorio-docker). A profile describes one playable server
runtime: Factorio version, Compose configuration and the source mod list. Runtime saves, downloaded mod zips and
secrets are deliberately not stored in Git.

The sibling repository for Minecraft is
[`my-docker-minecraft-server-config`](https://github.com/DrArzter/my-docker-minecraft-server-config). One repository
per game keeps each game's authoring contract honest — a Factorio profile pins an engine version and portal mods, a
Minecraft profile pins a loader and CurseForge mods, and neither schema has to stretch over the other.

## Profiles

| ID | Gameplay | Runtime |
| --- | --- | --- |
| `factorio-vanilla` | Vanilla | Factorio 2.0 (stable), no mods |

Each profile is self-contained below `profiles/<id>/`:

```text
profile.json    machine-readable identity and version/mod contract
compose.yaml    standalone local runtime
.env.example    names of cut-time secrets; the local runtime itself needs none
extras/         authoring inputs such as the mod pin list, when applicable
data/           generated saves and runtime data, ignored by Git
```

Every profile declares `"game": "factorio"`. Spawnpoint reads that field to pick the version field, the loader
contract and the resolver for a profile; a profile with no `game` is treated as Minecraft, which is why this
repository states it explicitly.

The image tag in `compose.yaml` is the profile's `factorio_version`: the engine carries its own version and there is
no separate loader, so the version lives in exactly two places and the validator keeps them in agreement.

## Run locally

```bash
cd profiles/factorio-vanilla
docker compose up -d
```

The first boot generates a map named `spawnpoint`; later boots load the newest save. RCON binds to localhost only,
with the password the server generates into `data/config/rconpw`.

Validate every profile without starting containers:

```bash
scripts/validate-profiles.sh
```

## Mod pins

A modded profile lists exact mods in `extras/mod-pins.txt`, one pin per line:

```text
# comments and blank lines are ignored
some-mod:1.2.3
```

Pins are exact versions, not ranges: the mod portal serves one file per version and Factorio clients auto-sync mods
from the server on join, so a pinned list reproduces the same session for everyone by construction.

## Source versus release

Pins are authoring inputs, not releases. Spawnpoint resolves a profile into an immutable release carrying the
portal's file names and SHA-1 hashes; those hashes remain the deployment truth. Resolution needs a factorio.com
username and token only to download files at cut time — the server itself never needs an account, because hidden
servers skip matchmaking authentication. Do not commit downloaded zips or put credentials in profile files.
