#!/usr/bin/env bash

# Create bin directory if it doesn't exist
mkdir -p "$HOME/bin"

# Install claspdeploy script
echo "Installing claspdeploy..."
# (optional) tweak shebang for portability
sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' ./claspdeploy.sh
cp ./claspdeploy.sh "$HOME/bin/claspdeploy"
chmod +x "$HOME/bin/claspdeploy"

# Install deploy-webapp script
echo "Installing deploy-webapp..."
# Ensure shebang is portable
sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' ./deploy-webapp.sh
cp ./deploy-webapp.sh "$HOME/bin/deploy-webapp"
chmod +x "$HOME/bin/deploy-webapp"

# Add bin to PATH if not already there
if ! grep -q 'export PATH="$HOME/bin:$PATH"' ~/.zshrc; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
    echo "Added $HOME/bin to PATH in ~/.zshrc"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Installed scripts:"
echo "  - claspdeploy: General Apps Script deployment"
echo "  - deploy-webapp: Web app specific deployment"
echo ""
echo "Please restart your terminal or run 'source ~/.zshrc' to use the commands."