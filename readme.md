# LND auto backup service

This is a quick and dirty channel backup systemd service for a running LND node. 
It uploads `channel.backup` to a S3 bucket. It uses `inotifywait`
for monitoring changes and does a new time-stamped backup on each modification.

See [https://github.com/lightningnetwork/lnd/pull/2313](https://github.com/lightningnetwork/lnd/pull/2313) for details.

#### More reading

* [Alex Bosworth's exampe](https://twitter.com/alexbosworth/status/1114650312592072704)
* [Patrick Lemke's medium post](https://medium.com/@patricklemke95/how-to-backup-your-lightning-network-channels-170c995c157b)

### Prerequisites

* `apt install inotify-tools awscli`

### Setup

1. `git clone --depth=1 https://github.com/darwin/lnd-auto-backup.git` 
2. `cd lnd-auto-backup`
3. create a `.envrc` with content:

```
# note: S3 access must be configured via `aws configure`
export LNDAB_S3_BUCKET=your_bucket_name

# these are optional:
#
#   export LND_HOME=/root/.lnd # if differs from $HOME/.lnd
#   export LND_NETWORK=mainnet
#   export LND_CHAIN=bitcoin
#   export LND_BACKUP_SCRIPT=./backup-via-s3.sh
#   # or if you really need to force it explictly
#   export LNDAB_CHANNEL_BACKUP_PATH=/custom/path/to/channel.backup
```
4. `aws configure` and configure secrets for your AWS S3 account
5. modify `LNDAB_HOME` in `./service/lnd-auto-backup.service` to point to right directory
6. `./service/install.sh`
7. `./service/start.sh` - start it!
8. `./service/status.sh` - just to check the status 
9. `./service/enable.sh` - if it looks good, enable service launching after system restart

#### See logs

`./service/logs.sh`

#### Or just test it

1. source `.envrc` or better use `direnv`
2. `./monitor.sh`

---

Tested on my Ubuntu 18.10 server only.
