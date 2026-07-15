# sprite-ntfy

Self-hosted [ntfy](https://ntfy.sh) on a [Sprite](https://sprites.dev).

## Install

```sh
sprite console
curl -fsSL https://raw.githubusercontent.com/lubien/sprite-ntfy/main/install.sh | sh
```

Then on your local machine, make the URL public:

```sh
sprite url update --auth public
```

## Publish

```sh
curl -u user:pass -d "your message" https://YOUR-SPRITE.sprites.app/topic-name
```

## Subscribe

```sh
# stream (stays open, prints messages as they arrive)
curl -u user:pass https://YOUR-SPRITE.sprites.app/topic-name/json

# poll (returns buffered messages and exits)
curl -u user:pass "https://YOUR-SPRITE.sprites.app/topic-name/json?poll=1"

# catch up from a specific message
curl -u user:pass "https://YOUR-SPRITE.sprites.app/topic-name/json?since=<message-id>"
```

## Users

```sh
sprite console

ntfy user add username                      # add user
ntfy user add --role=admin username         # add admin
ntfy user change-pass username              # change password
ntfy access username topic-name rw         # grant read+write on a topic
ntfy access username '*' ro                # grant read-only on all topics
ntfy user list                              # list all users
```

## Manage the service

```sh
sprite exec -- sprite-env services list
sprite exec -- sprite-env services restart ntfy
sprite exec -- cat /.sprite/logs/services/ntfy.log
```

## Uninstall

```sh
sprite exec -- sprite-env services delete ntfy
sprite exec -- sudo rm -rf /etc/ntfy /var/lib/ntfy /var/cache/ntfy /usr/local/bin/ntfy
```
