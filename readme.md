# LND auto backup service

This is a channel backup script for LND node (prepared to be installed as a systemd service). 

The script uses `inotifywait` to monitor for file changes and triggers a new time-stamped backup when needed.
The backup script can do anything. As an example, we provide optional backup to Amazon S3 or via rsync. 
Or you can specify your own custom script.

See [https://github.com/lightningnetwork/lnd/pull/2313](https://github.com/lightningnetwork/lnd/pull/2313) for details.

#### More reading

* [Alex Bosworth's example](https://twitter.com/alexbosworth/status/1114650312592072704)
* [Patrick Lemke's medium post](https://medium.com/@patricklemke95/how-to-backup-your-lightning-network-channels-170c995c157b)

### Prerequisites

* `apt install inotify-tools`

### Setup

1. `git clone --depth=1 https://github.com/darwin/lnd-auto-backup.git` 
2. `cd lnd-auto-backup`
3. create a `.envrc` with content:

```
# for S3 backup (optional)
# also don't forget to `apt install awscli`
# note: S3 secrets can be configured via `aws configure`
export LNDAB_S3_BUCKET=your_bucket_name 

# for rsync backup (optional)
# note: ssh access keys must be configured on the machine
export LNDAB_RSYNC_TARGET=user@server:/remote/path/to/backup/dir

# for custom backup (optional)
export LNDAB_CUSTOM_BACKUP_SCRIPT=path/to/your/script.sh 

# these are optional:
#
#   export LND_HOME=/root/.lnd # if differs from $HOME/.lnd
#   export LND_NETWORK=mainnet
#   export LND_CHAIN=bitcoin
#   export LNDAB_CHANNEL_BACKUP_PATH=/custom/path/to/channel.backup
#   export LNDAB_VERBOSE=1
#   export LNDAB_S3_BACKUP_SCRIPT=./backup-via-s3.sh
#   export LNDAB_RSYNC_BACKUP_SCRIPT=./backup-via-rsync.sh
```
4. modify `LNDAB_HOME` in `./service/lnd-auto-backup.service` to point to right directory
5. `./service/install.sh`
6. `./service/start.sh` - start it!
7. `./service/status.sh` - just to check the status 
8. `./service/enable.sh` - if it looks good, enable service launching after system restart

#### See logs

`./service/logs.sh`

#### Or just test it

1. source `.envrc` or better use `direnv`
2. `./monitor.sh`

---

Tested on Ubuntu 18.10 server. My lnd node runs in a docker container and I use this service to monitor changes of 
`channel.backup` file mapped to host machine via a docker volume.
