#!/usr/bin/env bash
set -euo pipefail

version=10.11

# List of Hangover packages (update as needed)
PACKAGES=(
  hangover-libarm64ecfex
  hangover-libwow64fex
  hangover-wowbox64
  hangover-wine
)

# Define functions as variables for reuse
ERROR_FUNC='error() {
  echo -e "\033[31mERROR: $1\033[0m" >&2
  exit 1
}'

INFO_FUNC='info() {
  echo -e "\033[32mINFO: $1\033[0m"
}'

# Helper functions
eval "${ERROR_FUNC}"

eval "${INFO_FUNC}"

# Detect OS codename
if [ -f /etc/os-release ]; then
  . /etc/os-release
  __os_codename="$VERSION_CODENAME"
else
  error "Cannot detect OS codename"
fi

# https://github.com/raspberrypi/bookworm-feedback/issues/107
PAGE_SIZE="$(getconf PAGE_SIZE)"
if [[ "$PAGE_SIZE" == "16384" ]]; then
  info "Raspberry Pi 5 detected with 16K PageSize Linux Kernel."
  info "This kernel causes incompatibilities with Wine. You need to switch to a 4K PageSize kernel."
  info "To fix this manually, add 'kernel=kernel8.img' under '[pi5]' section in /boot/config.txt or /boot/firmware/config.txt"
  info "Then reboot and run this script again."
  exit 0
fi

# Remove existing Wine installations that might conflict
info "Checking for existing Wine installations..."
if dpkg -l fonts-wine 2>/dev/null | grep -q "^ii"; then
  sudo apt purge fonts-wine -y || exit 1
fi
if dpkg -l libwine 2>/dev/null | grep -q "^ii"; then
  sudo apt purge libwine -y || exit 1
fi

if [ "$__os_codename" == "bullseye" ]; then
  ho_distro="debian11"
elif [ "$__os_codename" == "bookworm" ]; then
  ho_distro="debian12"
elif [ "$__os_codename" == "trixie" ]; then
  ho_distro="debian13"
elif [ "$__os_codename" == "focal" ]; then
  ho_distro="ubuntu2004"
elif [ "$__os_codename" == "jammy" ]; then
  ho_distro="ubuntu2204"
elif [ "$__os_codename" == "noble" ]; then
  ho_distro="ubuntu2404"
elif [ "$__os_codename" == "plucky" ]; then
  ho_distro="ubuntu2504"
else
  error "You are not using a supported distribution."
fi

cd /tmp || error "Could not move to /tmp folder"
wget https://github.com/AndreRH/hangover/releases/download/hangover-${version}/hangover_${version}_${ho_distro}_${__os_codename}_arm64.tar || error "Failed to download Hangover!"
tar -xf hangover_${version}_${ho_distro}_${__os_codename}_arm64.tar || error "Failed to extract Hangover!"
rm -f hangover_${version}_${ho_distro}_${__os_codename}_arm64.tar

# install .deb files using PACKAGES list
info "Installing Hangover packages..."
for pkg in "${PACKAGES[@]}"; do
  if [ "$pkg" = "hangover-wine" ]; then
    deb="/tmp/${pkg}_${version}~${__os_codename}_arm64.deb"
  else
    deb="/tmp/${pkg}_${version}_arm64.deb"
  fi
  sudo apt install -y "$deb" || exit 1
done
info "Done"

# cleanup .deb files using PACKAGES list
info "Cleanup Hangover packages..."
for pkg in "${PACKAGES[@]}"; do
  if [ "$pkg" = "hangover-wine" ]; then
    deb="/tmp/${pkg}_${version}~${__os_codename}_arm64.deb"
  else
    deb="/tmp/${pkg}_${version}_arm64.deb"
  fi
  rm -f "$deb"
done
info "Done"

cat << EOF | sudo tee /usr/local/bin/generate-hangover-prefix >/dev/null
#!/usr/bin/env bash

${ERROR_FUNC}

${INFO_FUNC}

if [ "\$(id -u)" == 0 ];then
  error "Please don't run this script with sudo."
fi

if [ -z "\$WINEPREFIX" ];then
  WINEPREFIX="\$HOME/.wine"
fi
export WINEPREFIX

if [ -f "\$WINEPREFIX/system.reg" ];then
  registry_exists=true
else
  registry_exists=false
fi

export WINEDEBUG=-virtual #hide harmless memory errors

if [ -e "\$WINEPREFIX" ];then
  info "Checking Wine prefix at \$WINEPREFIX..."
  info "To choose another prefix, set the WINEPREFIX variable."
  echo -n "Waiting 5 seconds... "
  sleep 5
  echo
  # check for existance of incompatible prefix (see server_init_process https://github.com/wine-mirror/wine/blob/884cff821481b4819f9bdba455217bd5a3f97744/dlls/ntdll/unix/server.c#L1544-L1670)
  # Boot wine and check for errors (make fresh wineprefix)
  output="\$(set -o pipefail; wine wineboot 2>&1 | tee /dev/stderr; )" #this won't display any dialog boxes that require a button to be clicked
  if [ "\$?" != 0 ]; then
    echo "Your previously existing Wine prefix failed with an error (see terminal log)."
    echo "Removing and regenerating Wine prefix..."
    rm -rf "\$WINEPREFIX"
    registry_exists=false
    wine wineboot #this won't display any dialog boxes that require a button to be clicked
  fi
  #wait until above process exits
  sleep 2
  while [ ! -z "\$(pgrep -i 'wine C:')" ];do
    sleep 1
  done
else
  info "Generating Wine prefix at \$WINEPREFIX..."
  info "To choose another prefix, set the WINEPREFIX variable."
  info "Waiting 5 seconds..."
  sleep 5
  # Boot wine (make fresh wineprefix)
  wine wineboot #this won't display any dialog boxes that require a button to be clicked
  #wait until above process exits
  sleep 2
  while [ ! -z "\$(pgrep -i 'wine C:')" ];do
    sleep 1
  done
fi

if [ "\$registry_exists" == false ];then
info "Making registry changes..."
TMPFILE="\$(mktemp)" || exit 1
echo 'REGEDIT4' > \$TMPFILE

info "  - Disabling Wine mime associations" #see https://askubuntu.com/a/400430

echo '
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunServices]
"winemenubuilder"="C:\\windows\\system32\\winemenubuilder.exe -r"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunServices]
"winemenubuilder"="C:\\windows\\system32\\winemenubuilder.exe -r"' >> \$TMPFILE

wine regedit \$TMPFILE

# Make sure HKCU also gets added even on existing prefixes
wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunServices" \\
  /v winemenubuilder /t REG_SZ \\
  /d "C:\\windows\\system32\\winemenubuilder.exe -r" /f

rm -f \$TMPFILE
fi #end of if statement that only runs if this script was started when there was no wine registry
true
EOF

sudo chmod +x /usr/local/bin/generate-hangover-prefix
/usr/local/bin/generate-hangover-prefix || exit 1