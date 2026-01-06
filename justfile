encrypt:
    age -r age16td0lf6gaycxwef5ga3yhkjxrrcmptrcu25g4s9zg5wcm0qzf4uqdj94pf \
        -o backup.sh.enc \
        backup.sh

decrypt:
    age --decrypt -i "$HOME/Library/Application Support/sops/age/keys.txt" -o backup.sh backup.sh.enc