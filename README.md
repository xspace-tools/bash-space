# XSpace

A modular, portable developer toolchain. One repository, one install command, every tool available from any directory on any machine.

```
git clone git@github.com:Sconl/xspace.git
cd xspace/_configure && ./install.sh
```

---

## What's inside

XSpace is a monorepo of focused tool spaces. Each space owns its own code, lives in its own directory, and adds its commands to your PATH automatically.

| Space | Commands | What it does |
|-------|----------|-------------|
| `animate-space/` | `animatex`, `animatex-text`, `animatex-svg` | Generate animated text assets (GIF, SVG, HTML) |
| `git-space/` | `commitx`, `git-prx` | Conventional commits, pull request creation |
| `sys-space/` | `refreshx`, `updatex` | Shell reload, system + repo updates |
| `backup-space/` | `backupx` | rclone / rsync / tar backup orchestrator |
| `code-space/` | *(planned)* | Code scaffolding tools |
| `_configure/` | `install.sh`, `uninstall.sh`, `update.sh` | Orchestrator — wires everything together |

---

## Requirements

| Dependency | Required by | Install |
|------------|-------------|---------|
| `bash` 4.0+ | everything | pre-installed on Linux |
| `python3` 3.8+ | `animatex` | `sudo dnf install python3` |
| `Pillow` | `animatex-text` (GIF mode) | auto-installed by `install.sh` |
| `git` | `updatex`, `commitx`, `git-prx` | pre-installed on Linux |
| `gh` CLI | `git-prx` | [cli.github.com](https://cli.github.com) |
| `rclone` | `backupx` (rclone jobs) | [rclone.org/install](https://rclone.org/install/) |
| `readlink -f` | all dispatchers | GNU coreutils (pre-installed on Linux) |

> **macOS:** `readlink -f` requires `brew install coreutils`. All else works as-is.

---

## Install

```bash
# 1. Clone
git clone git@github.com:Sconl/xspace.git
cd xspace

# 2. Install
cd _configure && ./install.sh

# 3. Activate (current terminal only — new terminals activate automatically)
source ~/.bashrc    # or: refreshx
```

The installer:
- Creates all space directories
- Adds each space's `bin/` to your `PATH`
- Symlinks all current scripts to `~/bin`
- Installs Pillow if not present
- Writes `backup-space/config/backups.conf` if none exists
- Registers gitspace tab completion

---

## Update

```bash
updatex            # system packages (dnf + flatpak) + git pull + re-install
updatex --system   # system packages only
updatex --xspace   # git pull + re-install only
```

Or directly:

```bash
cd xspace/_configure && ./update.sh
```

---

## Uninstall

```bash
cd xspace/_configure && ./uninstall.sh
```

Removes: `~/bin` symlinks, `PATH` entries from shell RC, completion lines.  
Keeps: the repo, all tool directories, fonts, exports, logs, `backups.conf`.

---

## animatex — animated text assets

```bash
animatex                         # interactive — asks GIF or SVG, then prompts
animatex --type text [options]   # skip menu, go straight to GIF
animatex --type svg  [options]   # skip menu, go straight to SVG
```

### animatex-text — gradient typing GIF

Generates a looping animated `.gif` with a typing effect and horizontal gradient text.

```bash
animatex-text                                              # interactive
animatex-text --brand "#FF6B00" --text "Launch|Live"      # direct
animatex-text --font "Barlow-BlackItalic.ttf" --fontsize 96 --brand "#5C3BFF"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--text` | `Hello world` | Pipe-separated lines: `"Line 1\|Line 2"` |
| `--brand` | — | Primary brand hex — auto-derives gradient |
| `--gradient1` | `#00C800` | Gradient start (overrides `--brand`) |
| `--gradient2` | `#B4FF00` | Gradient end (overrides `--brand`) |
| `--align` | `center` | `left` / `center` / `right` |
| `--width` | `1200` | Canvas width px |
| `--height` | `200` | Canvas height px |
| `--font` | `Poppins-Bold.ttf` | Filename in `fonts/` or absolute path |
| `--fontsize` | `64` | Font size px |
| `--fps` | `24` | Frames per second |
| `--project` | `project` | Output filename slug |
| `--version` | `0.0.0` | Semver string |

**Output:** `animate-space/animate-text/exports/YYYYMMDD_asset_animated_text_{project}_v{version}.gif`

> **Fonts:** Copy your `.ttf`/`.otf` files to `animate-space/animate-text/fonts/`. Poppins and Barlow are not committed to the repo — download them from [fonts.google.com](https://fonts.google.com).

### animatex-svg — animated SVG / HTML

Generates a `.html` (JS state machine, multi-line) or `.svg` (pure CSS, single-line) animated typing asset. No Pillow required — Python stdlib only.

```bash
animatex-svg                                               # interactive
animatex-svg --brand "#00CC66" --text "Hello|World"       # direct
animatex-svg --format svg --text "Hello" --brand "#5C3BFF"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--text` | `Hello world` | Pipe-separated lines |
| `--brand` | — | Primary brand hex |
| `--font-family` | `Poppins` | CSS `font-family` name |
| `--font-weight` | `700` | CSS `font-weight` |
| `--font-size` | `64px` | CSS font-size with unit |
| `--viewbox-width` | `1200` | SVG viewBox width |
| `--viewbox-height` | `200` | SVG viewBox height |
| `--char-delay` | `0.05` | Seconds between characters |
| `--pause` | `2.0` | Hold time after line completes |
| `--cursor` | `true` | Blinking cursor (`true`/`false`) |
| `--format` | `html` | `html` (JS, multi-line) or `svg` (CSS, single-line) |

**Output:** `animate-space/animate-svg/exports/YYYYMMDD_asset_animated_svg_{project}_v{version}.{html|svg}`

### GIF vs SVG — when to use which

| | GIF | SVG/HTML |
|--|-----|---------|
| Works in email | ✅ | ❌ |
| Works in GitHub README | ✅ | ✅ (`<img>`) |
| Transparent background | ✅ | ✅ |
| Infinitely scalable | ❌ | ✅ |
| Multi-line text | ✅ | ✅ (HTML mode) |
| No Pillow required | ❌ | ✅ |
| Embeddable in web page | `<img>` | inline or `<img>` |

---

## commitx — git commit helper

Interactive [Conventional Commits](https://www.conventionalcommits.org) helper. Stages everything, shows a status summary, prompts for type/scope/summary/body/footer, previews the message, then commits.

```bash
commitx                          # interactive
commitx --type feat --scope ui --summary "add dark mode" --yes
```

| Flag | Description |
|------|-------------|
| `--type` | `feat` / `fix` / `docs` / `style` / `refactor` / `test` / `chore` |
| `--scope` | Module or folder |
| `--summary` | ≤50 characters |
| `--body-file` | Read body from file |
| `--footer-file` | Read footer from file |
| `--amend` | Amend last commit |
| `--signoff` | Add `Signed-off-by` line |
| `--gpg` | GPG sign the commit |
| `-y / --yes` | Auto-confirm (no prompt) |
| `--non-interactive` | Fail if required fields missing — CI-safe |
| `--no-stage` | Skip `git add --all` |

Auto-detects **scope** from branch name (`feature/ui/...` → `ui`) and **ticket** from `JIRA-123` or `#123` patterns.

Logs every commit to `~/.gitspace/logs/commits.log`.

---

## git-prx — pull request helper

Creates GitHub PRs via the `gh` CLI with body templating, reviewer suggestions, and optional auto-merge.

```bash
git-prx                          # interactive
git-prx --push --base main --draft
```

| Flag | Description |
|------|-------------|
| `--template` | PR template from `git-space/templates/pr/<name>.md` |
| `--base` | Base branch (default: `main`) |
| `--from` | Head branch (default: current) |
| `--push` | Push head branch before creating PR |
| `--draft` | Create as draft |
| `--open` | Open in browser after creation |
| `--auto-merge` | Squash merge when checks pass |
| `--reviewers` | Comma-separated reviewer usernames |
| `--labels` | Comma-separated labels |
| `-y / --yes` | Auto-confirm |

Template placeholders: `{{COMMITS}}` (commit list) and `{{DIFFSTAT}}` (diff stats).

Logs every PR to `~/.gitspace/logs/prs.log`.

---

## backupx — backup orchestrator

Runs all backup jobs defined in `backup-space/config/backups.conf`.

```bash
backupx              # run all jobs
backupx --list       # list configured jobs (no execution)
backupx --dry-run    # show what would run
backupx --help
```

### Configuring backups

Edit `backup-space/config/backups.conf`. One job per line:

```
method|source|dest|options|mode
```

| Field | Values |
|-------|--------|
| `method` | `rclone`, `rsync`, `tar` |
| `source` | Absolute local path |
| `dest` | Local path, rclone remote, or archive path |
| `options` | Tool flags passed verbatim |
| `mode` | `copy` (additive) or `sync` (mirror — deletes extra) |

**Examples:**
```
rclone|/home/user/Documents|gdrive:Backups/Documents|--progress|sync
rsync|/home/user/Projects|server:/backups/projects|-avz --delete|sync
tar|/home/user/important|/mnt/usb/important.tar.gz|--exclude='.git'|copy
```

Logs are written to `backup-space/logs/` and are gitignored.

---

## refreshx — reload shell

```bash
refreshx
```

Sources `~/.bashrc` (bash) or `~/.zshrc` (zsh) and runs `hash -r`. Run this after installing or adding new scripts to any space's `bin/` directory while in an existing terminal session.

---

## updatex — system + repo updater

```bash
updatex                  # system packages + xspace repo update
updatex --system         # system packages only (dnf + flatpak)
updatex --xspace         # git pull + install.sh only
updatex --skip-pull      # install.sh only, no git pull
```

System update runs `dnf upgrade`, `flatpak update`, and `dnf autoremove`. XSpace update runs `git pull --ff-only origin main` then `_configure/install.sh`.

---

## Adding new commands

### To any existing space (zero reinstall)

```bash
# Create the script
cat > xspace/git-space/bin/mygitcmd <<'EOF'
#!/usr/bin/env bash
# git-space/bin/mygitcmd
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/../lib/ui.sh"
print_info "My new git command"
EOF
chmod +x xspace/git-space/bin/mygitcmd

# Open a new terminal (or: refreshx)
mygitcmd    # works immediately
```

This works because `install.sh` adds the entire `git-space/bin/` directory to `PATH`, not just individual symlinks.

### To a new space

```bash
# 1. Create the space
mkdir -p xspace/myspace/bin xspace/myspace/lib

# 2. Add to xspace.conf
# In XSPACE_ALL_BIN_DIRS, append: "myspace/bin"

# 3. Re-run install.sh once
cd xspace/_configure && ./install.sh

# After that: scripts added to myspace/bin/ are auto-discovered
```

---

## Repository structure

```
xspace/
│
├── xspace.conf                    Central path config + space registry
│
├── _configure/                    Orchestrator — install lifecycle only
│   ├── install.sh
│   ├── uninstall.sh
│   └── update.sh
│
├── animate-space/                 Animated text asset generation
│   ├── bin/
│   │   ├── animatex               Type-selection menu (GIF or SVG)
│   │   ├── animatex-text          Direct GIF shortcut
│   │   └── animatex-svg           Direct SVG shortcut
│   ├── lib/
│   │   ├── animatex.sh            Router
│   │   ├── animatex_text.sh       GIF logic
│   │   └── animatex_svg.sh        SVG/HTML logic
│   ├── animate-text/
│   │   ├── python/gradient_typing_effect.py
│   │   ├── fonts/                 .ttf/.otf (not committed — see below)
│   │   └── exports/               Generated GIFs (.gitignored)
│   └── animate-svg/
│       ├── python/svg_typing_effect.py
│       └── exports/               Generated SVG/HTML (.gitignored)
│
├── git-space/                     Git workflow utilities
│   ├── bin/
│   │   ├── commitx
│   │   └── git-prx
│   ├── lib/
│   │   ├── formatting.sh
│   │   ├── safety.sh
│   │   ├── ui.sh
│   │   └── validation.sh
│   ├── completion/gitspace-completion.sh
│   └── templates/pr/default.md
│
├── sys-space/                     Workstation system utilities
│   └── bin/
│       ├── refreshx
│       └── updatex
│
├── backup-space/                  Backup orchestrator
│   ├── bin/backupx
│   ├── config/backups.conf        Edit this to configure your backup jobs
│   └── logs/                      Job logs (.gitignored)
│
└── code-space/                    Codespace directives (tools planned)
```

---

## Design principles

**One install, every tool.** Running `_configure/install.sh` wires all spaces. No per-space install commands. No manual PATH editing.

**Auto-discovery.** Each space's `bin/` directory is added directly to `PATH`, not just individual symlinks. Drop a new script into any `bin/` — it's available on the next terminal open, no reinstall needed.

**No duplication.** Tool code lives in its own space directory. `_configure/` knows where things are (via `xspace.conf`) but never copies them.

**Single source of truth.** `xspace.conf` declares all paths and the list of spaces. Renaming a space folder means editing one variable in one file.

**Portable.** Works on any machine that has bash 4+, git, and python3. Clone the repo, run `install.sh`, done. No brew, no pip outside of Pillow, no node.

---

## Font files

Font files (Poppins, Barlow) are not committed to the repository — they are binary assets that would bloat the repo history. Copy your `.ttf`/`.otf` files to `animate-space/animate-text/fonts/` after cloning. Free downloads at [fonts.google.com](https://fonts.google.com). Without fonts, `animatex-text` falls back to PIL's built-in bitmap font.

---

## License

MIT — see `LICENSE` file.

---

*Built to travel. One clone, one install, every tool available, anywhere.*