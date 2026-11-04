# Install the Nscale CLI on Windows.
#
#   irm https://docs.nscale.com/cli/install.ps1 | iex
#
# Pin a version or choose the install directory:
#
#   & ([scriptblock]::Create((irm https://docs.nscale.com/cli/install.ps1))) -Version 6.2.0
#   $env:NSCALE_VERSION = '6.2.0'; irm https://docs.nscale.com/cli/install.ps1 | iex
#
# Parameters:
#   -Version     Version to install, for example 7.0.0 or v7.0.0 (default: latest).
#   -InstallDir  Directory to install nscale.exe into
#                (default: $env:LOCALAPPDATA\Programs\nscale).
#   -NoPathUpdate  Do not add the install directory to the user PATH.
#
# NSCALE_VERSION and NSCALE_INSTALL_DIR are read when the parameters are not given.

# `irm | iex` evaluates this script in the caller's scope, so everything runs in a
# script block to keep its parameters, variables, functions and preferences out of
# the caller's session. `@args` forwards -Version and the other parameters when
# the script is invoked as a script block.
& {
	[CmdletBinding()]
	param(
		[string]$Version = $env:NSCALE_VERSION,
		[string]$InstallDir = $env:NSCALE_INSTALL_DIR,
		[switch]$NoPathUpdate
	)

	$Repo = 'nscaledev/homebrew-tap'

	# Windows PowerShell 5.1 may default to TLS 1.0, which GitHub refuses.
	if ($PSVersionTable.PSVersion.Major -lt 6) {
		[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	}

	function Get-Arch {
		$arch = $null
		try {
			$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
		} catch {
			# Windows PowerShell on older .NET Framework has no RuntimeInformation.
			$arch = $env:PROCESSOR_ARCHITEW6432
			if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
		}
		switch ($arch) {
			{ $_ -in 'X64', 'AMD64' } { return 'x86_64' }
			{ $_ -in 'Arm64', 'ARM64' } { return 'arm64' }
			{ $_ -in 'X86', 'x86' } { return 'i386' }
			default { throw "Unsupported architecture: $arch" }
		}
	}

	# Follow the "latest release" redirect to find the tag, avoiding the GitHub API
	# and its rate limit.
	function Get-LatestTag {
		$url = "https://github.com/$Repo/releases/latest"
		$request = [System.Net.WebRequest]::Create($url)
		$request.Method = 'HEAD'
		$response = $request.GetResponse()
		try {
			$tag = $response.ResponseUri.Segments[-1]
		} finally {
			$response.Close()
		}
		if ($tag -notmatch '^v\d') {
			throw "Could not determine the latest version from $url"
		}
		return $tag
	}

	# Add Dir to the user PATH unless it is already there. Returns whether it was added.
	function Add-UserPath([string]$Dir) {
		# Read and write the registry value itself: the Environment API returns the
		# expanded value and, on Windows PowerShell, writes it back as REG_SZ, which
		# would turn entries like %USERPROFILE%\... into fixed paths.
		$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
		try {
			$raw = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
			$entries = @($raw -split ';' | Where-Object { $_ })
			foreach ($entry in $entries) {
				if ([Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\') -eq $Dir) {
					return $false
				}
			}
			$key.SetValue('Path', (($entries + $Dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
		} finally {
			$key.Close()
		}
		# Writing the registry doesn't notify running programs. Setting and clearing a
		# variable through the Environment API broadcasts WM_SETTINGCHANGE, so new
		# terminals opened from Explorer see the updated PATH.
		$name = 'NSCALE_INSTALL_' + [Guid]::NewGuid().ToString('N')
		[Environment]::SetEnvironmentVariable($name, '1', 'User')
		[Environment]::SetEnvironmentVariable($name, $null, 'User')
		return $true
	}

	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue'

	$arch = Get-Arch

	if (-not $Version -or $Version -eq 'latest') {
		$tag = Get-LatestTag
	} else {
		$tag = 'v' + $Version.TrimStart('v')
	}
	$plain = $tag.TrimStart('v')

	$archive = "nscale-cli_Windows_$arch.zip"
	$base = "https://github.com/$Repo/releases/download/$tag"

	if (-not $InstallDir) {
		$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\nscale'
	}
	# Resolve a relative path against the PowerShell location, since the PATH entry
	# must be absolute, and drop a trailing separator so it matches existing entries.
	$InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
	if ($InstallDir.Length -gt 3) {
		$InstallDir = $InstallDir.TrimEnd('\', '/')
	}

	$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nscale-" + [System.Guid]::NewGuid())
	New-Item -ItemType Directory -Path $tmp | Out-Null

	try {
		Write-Host "Installing nscale $tag (Windows $arch)"

		$archivePath = Join-Path $tmp $archive
		$checksumsPath = Join-Path $tmp 'checksums.txt'
		try {
			Invoke-WebRequest -UseBasicParsing -Uri "$base/$archive" -OutFile $archivePath
		} catch {
			throw "Could not download $base/${archive}: $($_.Exception.Message) If the version is wrong, the available versions are at https://github.com/$Repo/releases"
		}
		Invoke-WebRequest -UseBasicParsing -Uri "$base/nscale-cli-$plain-checksums.txt" -OutFile $checksumsPath

		$expected = $null
		foreach ($line in Get-Content $checksumsPath) {
			$fields = $line -split '\s+'
			if ($fields.Count -ge 2 -and $fields[1] -eq $archive) {
				$expected = $fields[0]
				break
			}
		}
		if (-not $expected) {
			throw "No checksum listed for $archive"
		}
		$actual = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash
		if ($actual -ne $expected) {
			throw "Checksum mismatch for ${archive}: expected $expected, got $actual"
		}

		$extractDir = Join-Path $tmp 'extract'
		Expand-Archive -Path $archivePath -DestinationPath $extractDir

		New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
		$target = Join-Path $InstallDir 'nscale.exe'
		Copy-Item -Force -Path (Join-Path $extractDir 'nscale.exe') -Destination $target
		Write-Host "Installed $target"
	} finally {
		Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
	}

	if (-not $NoPathUpdate -and [Environment]::OSVersion.Platform -eq 'Win32NT') {
		if (Add-UserPath $InstallDir) {
			Write-Host "Added $InstallDir to your user PATH. Open a new terminal to run nscale."
		}
		if (($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $InstallDir) {
			$env:Path = "$env:Path;$InstallDir"
		}
	}
} @args
