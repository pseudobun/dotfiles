# pseudobun's dotfiles

This repository contains dotfiles and images for my workspace (fish, Ghostty, sketchybar, paw and hop configs, desktop wallpapers). Wallpaper assets used have been downloaded from [Ethereum's official Assets site](https://ethereum.org/en/assets/).

## Bootstrapping:

Run this command to bootstrap your machine:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/pseudobun/dotfiles/main/bootstrap.sh)"
```

> Note: 
> Some of the commands in the script require `sudo` access. You will be prompted for your password. 

Currently, [Go](https://go.dev/) needs to be installed [manually](https://go.dev/doc/install).

## TODOs

* [ ] Add option to generate new GPG key pair/import it from file and set it to default for git.
* [ ] Add option to generate new SSH key pair/import it from file and add it to SSH agent.
* [ ] Installing Go

## Some of the tools I use:

* [Ghostty](https://ghostty.org/)
* [fish](https://github.com/fish-shell/fish-shell)
* hop — my native launcher (private repo `pseudobun/hop`)
* paw — my tiling window manager with virtual workspaces (private repo `pseudobun/paw`)
* [sketchybar](https://github.com/FelixKratz/SketchyBar)
* [modern UNIX tools](https://github.com/ibraheemdev/modern-unix)
* [pyenv](https://github.com/pyenv/pyenv)

## hop and paw

`bootstrap.sh` clones both into `~/repos/personal` and builds them once GitHub is logged in
(`gh auth login` or the SSH key from `just secrets-import`); hop also needs Xcode from the App Store.
Re-run just that part with `~/.dotfiles/bootstrap.sh --only apps`, then grant both Accessibility.

Their configs are linked from here: `paw/` → `~/.config/paw`, `hop/` → `~/.config/hop`.
`hop/config.json5` uses `${NAME}` placeholders for hosts and paths; hop fills them from `hop/.env`.

## Secrets

`.env` files are never committed — only their sops-encrypted copies (`hop/.env.enc`,
`sketchybar/env.local.sh.enc`, age recipient in `.sops.yaml`).

* `just decrypt` / `just encrypt` — `.enc` ↔ plain file (needs the age key)
* `just edit-env hop/.env` — edit the encrypted file in place
* `just secrets-export` / `just secrets-import <file>` — GPG, SSH and the age key between Macs; import also decrypts the `.env` files


## Fonts

All fonts are Nerd Fonts from the `Brewfile` (`brew bundle`, automatic in `bootstrap.sh`):
JetBrains Mono, Roboto Mono, Ubuntu, Geist Mono, Hack and Liga SFMono.

## Exporting public and private GPG keys with `gpg`

1. Export public key using `gpg --export --armor your@email.com > public_key.asc`.
2. List privaye keys using `gpg --list-secret-keys`.
3. Find the key by ID (e.g. 12345678) and export it using `gpg --export-secret-keys -a 12345678 > private_key.asc`.

## Importing public and private GPG keys with `gpg`

1. Import public key using `gpg --import public_key.asc`.
2. Import private key using `gpg --import private_key.asc`.

## Inspiration:

* [martines3000/dotfiles](https://github.com/martines3000/dotfiles)
* [br3ndonland/dotfiles](https://github.com/br3ndonland/dotfiles)
* [eieioxyz/Beyond-Dotfiles-in-100-Seconds](https://github.com/eieioxyz/Beyond-Dotfiles-in-100-Seconds)
* [crissNb/dotfiles](https://github.com/crissNb/dotfiles)
* [FelixKratz/dotfiles](https://github.com/FelixKratz/dotfiles)
