# sprite-ntfy

> One-command [ntfy](https://ntfy.sh) server on a [Sprites](https://sprites.dev) sandbox.

ntfy is a simple pub/sub notification service. This repo installs and configures it as a persistent service on your sprite, reachable at your sprite's public URL.

## Prerequisites

- A [Sprites](https://sprites.dev) account with a sprite created
- The `sprite` CLI installed and authenticated locally (`sprite org auth`)

## Install

Open a shell inside your sprite and run the installer:

```sh
sprite console          # opens a shell inside your sprite
```

Then, inside that shell:

```sh
curl -fsSL https://raw.githubusercontent.com/lubien/sprite-ntfy/main/install.sh | sh
```

The installer will:

1. Download the ntfy binary (v2.23.0, linux/amd64 or arm64)
2. Write a server config at `/etc/ntfy/server.yml`
3. Prompt you for an admin username and password
4. Register ntfy as a permanent sprite service on port `8080`
5. Clone this repo to `~/sprite-ntfy` for future reference

> **Non-interactive install** — pass credentials via environment variables to skip the prompts:
> ```sh
> NTFY_ADMIN_USER=admin NTFY_ADMIN_PASSWORD=yourpassword \
>   curl -fsSL https://raw.githubusercontent.com/lubien/sprite-ntfy/main/install.sh | sh
> ```

## Post-install: make the URL public

After installation, make your ntfy instance reachable without a sprite token by running this **on your local machine**:

```sh
sprite url update --auth public
```

Without this, only clients with a valid sprite bearer token can reach the URL. ntfy's own auth (username/password) handles access control once the URL is public.

## Usage

Your ntfy instance is available at your sprite URL (e.g. `https://ntfy-xavi.sprites.app`).

```sh
# Publish a notification
curl -u admin:yourpassword \
  -d "Hello from my sprite!" \
  https://ntfy-xavi.sprites.app/my-topic

# Subscribe (poll)
curl -u admin:yourpassword \
  https://ntfy-xavi.sprites.app/my-topic/json?poll=1
```

The [ntfy Android/iOS apps](https://ntfy.sh/#subscribe) and the [web app](https://ntfy.sh/app) all work with self-hosted servers — just point them at your sprite URL.

## Adding more users

```sh
sprite console   # get a shell inside the sprite
ntfy user add --config /etc/ntfy/server.yml username
```

## Service management

```sh
sprite exec -- sprite-env services list
sprite exec -- sprite-env services restart ntfy
sprite exec -- cat /.sprite/logs/services/ntfy.log
```

## Re-running the installer

The installer is fully idempotent — running it again will update the config, update the admin password, and restart the service. The ntfy message cache and user database are preserved.

## Uninstall

```sh
sprite exec -- sprite-env services delete ntfy
sprite exec -- sudo rm -rf /etc/ntfy /var/lib/ntfy /var/cache/ntfy /usr/local/bin/ntfy
```
