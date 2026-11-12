# pseudobun's dotfiles

This repository contains dotfiles and images for my workspace (fish, Ghostty, tip, paw and hop configs, desktop wallpapers). Wallpaper assets used have been downloaded from [Ethereum's official Assets site](https://ethereum.org/en/assets/).

## Bootstrapping:

Run this command to bootstrap your machine:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/pseudobun/dotfiles/main/bootstrap.sh)"
```

> Note: 
> Some of the commands in the script require `sudo` access. You will be prompted for your password. 

### Hosts

Two Macs share everything except what sits in `hosts/<host>/`:

| | sanctum (laptop) | olympus (Mac mini, runs the agents) |
|---|---|---|
| Brewfile | `hosts/sanctum/Brewfile` | `hosts/olympus/Brewfile` |
| repos | `~/repos/personal`, `~/repos/lutra` | flat `~/repos` |
| overrides | — | `hop/config.json5` (KeePass off) |
| extra | — | step `server`: pmset, `repos.txt`, LaunchAgents, cron, Docker; step `vault`: vault kept downloaded, its git dir `~/git/bunny-os.git`, qmd |

The bootstrap asks which Mac it is (or `--host sanctum|olympus`) and remembers it in
`~/.config/dotfiles/host`; `just brew-dump|brew-check|brew-extra` use that host's Brewfile.
A file in `hosts/<host>/<dir>/` replaces the shared one in `~/.config/<dir>/`.

Step `agents` checks out the synced agent config (`pseudobun/claude-config`) and links
`~/.codex/AGENTS.md` and `~/.config/opencode/AGENTS.md` to `~/.claude/CLAUDE.md`.
Step `debloat` takes News, Books, Chess, Photo Booth, Podcasts, Tips and Games off the Dock;
they are on the sealed system volume, so macOS does not let them be deleted.

## Some of the tools I use:

* [Ghostty](https://ghostty.org/)
* [fish](https://github.com/fish-shell/fish-shell)
* [hop](https://github.com/pseudobun/hop) — my native launcher
* [paw](https://github.com/pseudobun/paw) — my tiling window manager with virtual workspaces
* [tip](https://github.com/pseudobun/tip) — my native menu bar with islands and plugins
* [modern UNIX tools](https://github.com/ibraheemdev/modern-unix)

## hop and paw

Both are signed, notarized releases from [`pseudobun/tap`](https://github.com/pseudobun/homebrew-tap):
the host Brewfiles list `cask "pseudobun/tap/hop@beta"` and `cask "pseudobun/tap/paw@beta"` (the
plain casks lag behind the betas until a stable release exists), and they update
themselves (Sparkle, in the background). The `apps` step (`~/.dotfiles/bootstrap.sh --only apps`)
installs them if the Brewfile step didn't, moves an old build from source out of `/Applications`
to the Trash, and walks through the first start (confirm macOS's "downloaded from the Internet"
dialog) and the Accessibility grant. No clone and no Xcode needed.

To work on one, clone it and `just dev`: that builds "hop Dev" / "paw Dev" (`com.pseudobun.*.dev`,
own data and grants) into `~/Applications` and runs it instead of the release; `just undev` goes back.

Their configs are linked from here: `paw/` → `~/.config/paw`, `hop/` → `~/.config/hop`.
`hop/config.json5` uses `${NAME}` placeholders for hosts and paths; hop fills them from `hop/.env`.

## Secrets

`.env` files are never committed — only their sops-encrypted copies (`hop/.env.enc`,
`tip/.env.enc`, age recipient in `.sops.yaml`).

* `just decrypt` / `just encrypt` — `.enc` ↔ plain file (needs the age key)
* `just edit-env hop/.env` — edit the encrypted file in place
* `just secrets-export` / `just secrets-import <file>` — GPG, SSH, the age key and the login keychain certificates (.p12: e-ID, Apple Development, Developer ID) between Macs; import also decrypts the `.env` files


## Fonts

All fonts are Nerd Fonts from the `Brewfile` (`brew bundle`, automatic in `bootstrap.sh`):
JetBrains Mono, Roboto Mono, Ubuntu, Geist Mono, Hack and Liga SFMono.

## Inspiration:

* [martines3000/dotfiles](https://github.com/martines3000/dotfiles)
* [br3ndonland/dotfiles](https://github.com/br3ndonland/dotfiles)
* [eieioxyz/Beyond-Dotfiles-in-100-Seconds](https://github.com/eieioxyz/Beyond-Dotfiles-in-100-Seconds)
* [crissNb/dotfiles](https://github.com/crissNb/dotfiles)
* [FelixKratz/dotfiles](https://github.com/FelixKratz/dotfiles)
