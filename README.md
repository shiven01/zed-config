## macOS Locations
User Settings: ~/.config/zed/settings.json

## Setup

1. Copy `.env.example` to `.env` and set `SYMLINK_NAME` to the name of your symlink pointing at your real Zed settings file:
   ```
   cp .env.example .env
   ```
   Then edit `.env`:
   ```
   SYMLINK_NAME="symlink-zed"
   ```

2. Install [gitleaks](https://github.com/gitleaks/gitleaks):
   ```
   brew install gitleaks
   ```

3. Run the script to redact secrets and generate `settings.json`:
   ```
   ./generate-settings.sh
   ```
