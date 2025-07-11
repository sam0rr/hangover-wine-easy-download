#!/usr/bin/env bash
set -euo pipefail

# kill any running Wine processes
pkill -9 wine 2>/dev/null || true
command -v wineserver >/dev/null && wineserver -k 2>/dev/null || true

# remove the helper
echo -n "Removing terminal commands... "
sudo rm -f /usr/local/bin/generate-hangover-prefix
echo "Done"

# clear Wine mime/app entries
echo -n "Removing mimetypes... "
# see: https://askubuntu.com/a/400430
rm -f ~/.local/share/mime/packages/x-wine*
rm -f ~/.local/share/applications/wine-extension*
rm -f ~/.local/share/icons/hicolor/*/*/application-x-wine-extension*
rm -f ~/.local/share/mime/application/x-wine-extension*
echo "Done"

# purge the Hangover packages
echo -n "Purging Hangover packages... "
sudo apt purge -y \
  hangover-libarm64ecfex \
  hangover-libwow64fex \
  hangover-wine \
  hangover-wowbox64 \
  || exit 1
echo "Done"

# warn about remaining Wine prefix
if [ -d "$HOME/.wine" ]; then
  echo -e "\n\nYou just uninstalled the Hangover app, but it's not completely gone yet.
To prevent data loss, your Wine configuration is still located in:
  $HOME/.wine

Feel free to delete or rename that folder to free up space or troubleshoot.\n"
fi

true
