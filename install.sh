mkdir -p "$HOME/bin"
# (optional) tweak shebang for portability
sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' ./claspdeploy.sh
cp ./claspdeploy.sh "$HOME/bin/claspdeploy"
chmod +x "$HOME/bin/claspdeploy"

echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
exec zsh