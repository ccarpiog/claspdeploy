#!/usr/bin/env bash

# Create bin directory if it doesn't exist
mkdir -p "$HOME/bin"

# Create claspalt config directory if it doesn't exist
mkdir -p "$HOME/.config/claspalt"
chmod 700 "$HOME/.config/claspalt"

# Install claspalt script (must be installed first as claspdeploy depends on it)
echo "Installing claspalt..."
sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' ./claspalt.sh
cp ./claspalt.sh "$HOME/bin/claspalt"
chmod +x "$HOME/bin/claspalt"

# Install claspdeploy script
echo "Installing claspdeploy..."
sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' ./claspdeploy.sh
cp ./claspdeploy.sh "$HOME/bin/claspdeploy"
chmod +x "$HOME/bin/claspdeploy"

# Add bin to PATH if not already there
if ! grep -q 'export PATH="$HOME/bin:$PATH"' ~/.zshrc; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
    echo "Added $HOME/bin to PATH in ~/.zshrc"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Installed:"
echo "  - claspalt: Multi-account credential manager for clasp"
echo "  - claspdeploy: Deploy Google Apps Script projects"
echo ""
echo "Please restart your terminal or run 'source ~/.zshrc' to use these commands."
