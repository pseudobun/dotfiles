#!/bin/bash
cd "/Users/pseudobun/GDrive/1-personal/1-kdbxs/kdbxs"
git add --all
git commit -aS -m "chore: backup $(date +"%d-%m-%Y %H:%M:%S")"
git push

if [ $? -eq 0 ]; then
    ntfy publish --title="KDBX backup" --priority=low --tags=partying_face kdbx-backup "KDBXs backed up successfully"
else
    ntfy publish --title="KDBX backup" --priority=high --tags=sob kdbx-backup "KDBXs failed to back up"
fi
