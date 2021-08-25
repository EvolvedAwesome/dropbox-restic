#!/bin/zsh

# These are the credentials used by restic
RESTIC_PASSWORD=$(<$HOME/.restic_password)

# Configure RCLONE to use async for dropbox uploads.
# Documentation on this is avaliable here: https://rclone.org/dropbox/
# This enables max speed, but does mean that we can't check that each block was accepted, so
# we run rclone check after to double check
# Rclone backend options for restic are set using environment variables:
# https://rclone.org/docs/#environment-variables
RCLONE_DROPBOX_BATCH_SIZE=async

echo "Beginning backup of user directory to rclone:dropbox:backup"
restic -r rclone:dropbox:backup backup $HOME --host <name> --tag [tags,...] --one-file-system --exclude-file=.backup_excludes --exclude-caches

echo "Checking the integrity of the upload"
