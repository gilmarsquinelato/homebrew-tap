# homebrew-tap

Releases and the Homebrew formula for the [Nscale CLI](https://docs.nscale.com/docs/cli/overview).

## Install

### Homebrew (macOS and Linux)

```bash
brew install nscaledev/tap/nscale
```

### Install script (macOS and Linux)

```bash
curl -fsSL https://docs.nscale.com/cli/install.sh | sh
```

Pass `-v` to install a specific version and `-b` to choose the directory:

```bash
curl -fsSL https://docs.nscale.com/cli/install.sh | sh -s -- -v 6.2.0 -b ~/.local/bin
```

The script installs to `/usr/local/bin` if it is writable, otherwise to `~/.local/bin`. It verifies the download against the release's SHA-256 checksums.

### PowerShell (Windows)

```powershell
irm https://docs.nscale.com/cli/install.ps1 | iex
```

To install a specific version or choose the directory:

```powershell
& ([scriptblock]::Create((irm https://docs.nscale.com/cli/install.ps1))) -Version 6.2.0 -InstallDir C:\Tools\nscale
```

The script installs to `%LOCALAPPDATA%\Programs\nscale` and adds it to your user `PATH`. Pass `-NoPathUpdate` to skip that.

Both scripts also read `NSCALE_VERSION` and `NSCALE_INSTALL_DIR`. `https://docs.nscale.com/cli/install.sh` and `https://docs.nscale.com/cli/install.ps1` redirect to the scripts in this repository.

### Manual download

Download the archive for your platform from [Releases](https://github.com/nscaledev/homebrew-tap/releases) and put `nscale` on your `PATH`.
