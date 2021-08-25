# Restic with rclone backend

This is a fantastic way of utalising (cheap) dropbox storage in a way that is helpful and deployable pretty much anywhere. The front-end UI web-ui for dropbox is generally terrible and the desktop application is even worse...

You can use Cyberduck, Mountain duck or even rclone itself to mount dropbox as a local filesystem and the R/W performance is alright. Keep in mind that each write/read is encapsulated in an API call for dropbox, even with batching for uploads this still means there is a significant overhead, so *don't expect to be editing 4k video off a drive anytime soon*.

The application that this repo explores is using restic with an rclone backend to do incremental encrypted offsite backups to backup the `$HOME` folder (or any other folder). The system used in this example is macOS, although this procedure is applicable on any supported OS (macOS, gnu/linux, RHEL, Windows).

## Procedure

1. Install rclone and restic. 

On macOS this can be done with brew:

```
brew install rclone restic
```

Brew should handle adding these to your path, but you may have to `/usr/local/Cellar` to `$PATH` if you have issues. You can check the installed path with `brew doctor`.

2. Setup a new rclone bookmark.

Instructions for doing this: https://rclone.org/dropbox/

TLDR;

```
> rclone config
```

```
n) New remote
d) Delete remote
q) Quit config
e/n/d/q> n
name> remote
Type of storage to configure.
Choose a number from below, or type in your own value
[snip]
XX / Dropbox
   \ "dropbox"
[snip]
Storage> dropbox
Dropbox App Key - leave blank normally.
app_key>
Dropbox App Secret - leave blank normally.
app_secret>
Remote config
Please visit:
https://www.dropbox.com/1/oauth2/authorize?client_id=XXXXXXXXXXXXXXX&response_type=code
Enter the code: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX_XXXXXXXXXX
--------------------
[remote]
app_key =
app_secret =
token = XXXXXXXXXXXXXXXXXXXXXXXXXXXXX_XXXX_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
--------------------
y) Yes this is OK
e) Edit this remote
d) Delete this remote
y/e/d> y
```

Note that, although rclone does support end-end encryption and we could do a double-layer end-end encrypted rclone bookmark ontop of restics encryption, for simplicities sake we will be using only restics rest encryption.

You will have to give rclone OAUTH_2 access to your dropbox account. Note that if you are using dropbox business, you may wish to create a second backup dropbox account to limit attacker access to your account.

Once you have setup the bookmark, you can use `rclone mount` to explore the filesystem, you will have to install macFUSE for this. **You cannot use the brew-installed binaries if you want to mount a FS**. Install this from the fuse releases page on GitHub:

https://github.com/osxfuse/osxfuse/releases/

Then you can mount a macFUSE volume with:

```bash
sudo mkdir /Volumes/Dropbox
sudo rclone mount dropbox:/ /Volumes/Dropbox --no-modtime --no-checksum --volname Dropbox --async-read 
```

Note the use of "--volname" which will generate a volume just like a regular network share. You can use a local directory for the mount location instead of `/Volumes/Dropbox`, however this can get in the way and cause errors when you are trying to replicate a directory (and thus, replicate something into itself), so I reccomend mounting it in a system directory.

3. Setup restic within the dropbox filesystem

The format for using the rclone backend within restic is `rclone:{bookmark}:{folder}`. For this example we will create a new restic backup location in `rclone:dropbox:backup`:

```bash
restic --repo rclone:dropbox:backup init
```

Once the restic repository has been setup (this will take a moment and you will have to choose a strong password). We can add the restic password as an environment variable.

**Security rationale:** macOS utilizing filevault is encrypted at rest. If an attacker has access to my filesystem and environment variables, then they also have access to the files themselves. Backups don't have to be more secure than the original FS, just as secure.

The way that the script implements this is using a password file `$HOME/.restic_password` which is read when the script is started and saved to the environment variable `RESTIC_PASSWORD`. `RESTIC_PASSWORD` is then read by restic when any commands are run. This is great for debugging and easy. 

You can just pass the password into restic when using shell pipes (e.g. `restic backup < 'password'`) but this has some bugs associated with it.

You can read more about this here: https://github.com/restic/restic/issues/278

When creating this file, apply permissions to stop other users from reading/writing/executing:

```bash 
echo "<restic repository password>" > $HOME/.restic_password
chmod 0400 $HOME/.restic_password
```

4. Backups from restic.

Finally we define a file with directories that we don't want to backup, in this repo this is called `.backup_excludes`.

There are some files that are generally not useful (e.g. most `Downloads` folders, `.DS_STORE` files) which we will choose to exclude from the backup.

What you include here depends on your context, but I want to use this as a smart backup solution so that I can restore from it in an emergency to a new laptop. Thus, I include most things. You wouldn't normally need to include this much.

Then we can run a backup from restic:

```bash
restic -r rclone:dropbox:backup backup $HOME --host <name> --tag [tags,...] --one-file-system --exclude-file=.backup_excludes --exclude-caches
```

Information about restic commands can be found with:

```bash
restic --help
restic [command] --help
```

## Speed

Speed is acceptable for an incremental backup solution that doesn't include significant amount of changes day-day. With a high density of very small files you will have to enable asyncronous backup batching through rclone. This can cause some data damage if uploads are not completed successfully, so you will want to periodically run `restic check` (perhaps on a launchd timer with some sort of logging).

You can enable this by manipulating environment variables:

```bash
# https://rclone.org/docs/#environment-variables
RCLONE_DROPBOX_BATCH_SIZE=async
```

I was able to upload a 45gb directory using async backup batching in around 3 hours, which is acceptable for my deployment. This also depends on your proximity to a Dropbox CDN server, so YMMV.

## Automating

You will want to use launchd for automating this process and do some checks that rsync is not already running and that you are on a trusted network (granted, the concern is that you will run up bandwidth costs, not that this isn't a secure solution).

This fantastic article goes over some examples of the process for automating a deployment on macOS: https://szymonkrajewski.pl/macos-backup-restic/ .

One of the advantages of restic is that you can start and stop your deployment on the fly with very little penalty, so if you could script a scheduler that only runs backups when its time and continutes them the same time next day if it runs out of time.

Once you have created some backups, you can use `restic snapshots` to look at all the backups on your system. You can explore the contents of the snapshots with `restic mount` and look at differences with `restic diff` (which can help show directories/files that you don't need to be backing up).

You can restore using `restic restore`. Keep in mind that restic will not overwrite files and is really designed for restoring to a fresh directory. To restore a directory, we reccomend you restore to a new directory first, then rsync the files across. Alternatively, you can restore certain directories with the `--path` argument.

Example:
```bash
mkdir /Users/<username>_restore
sudo restic restore <snapshot> --target /Users/<username>_restore
sudo rsync -<flags> /Users/<username>_restore /Users/<username>
```

or using restic mounts:
```bash
mkdir /Users/<username>_restore
sudo restic mount /Users/<username>_restore
sudo rsync -<flags> /Users/<username>_restore /Users/<username>
```

Keep in mind that you can install and run restic and rclone from macOS restore mode, which will stop any issues with overwriting session files when rsyncing to the currently active users directory.
