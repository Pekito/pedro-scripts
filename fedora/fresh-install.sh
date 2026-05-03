#!/usr/bin/env bash
# =============================================================================
# Fedora Fresh Install Setup Script
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}${BOLD}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo or as root."
    exit 1
  fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────
require_sudo

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~${REAL_USER}")

echo -e "${BOLD}"
echo "  ███████╗███████╗██████╗  ██████╗ ██████╗  █████╗ "
echo "  ██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗"
echo "  █████╗  █████╗  ██║  ██║██║   ██║██████╔╝███████║"
echo "  ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔══██╗██╔══██║"
echo "  ██║     ███████╗██████╔╝╚██████╔╝██║  ██║██║  ██║"
echo "  ╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝"
echo -e "          Fresh Install Setup Script${NC}\n"

log "Running as root on behalf of user: ${REAL_USER}"
log "Home directory: ${REAL_HOME}"

# ─────────────────────────────────────────────────────────────────────────────
section "System Update"
# ─────────────────────────────────────────────────────────────────────────────
log "Updating system packages..."
dnf update -y
success "System updated."

# ─────────────────────────────────────────────────────────────────────────────
section "Enable Flathub (Flatpak)"
# ─────────────────────────────────────────────────────────────────────────────
log "Adding Flathub remote..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flathub ready."
sudo dnf copr enable scottames/ghostty
# ─────────────────────────────────────────────────────────────────────────────
section "DNF Packages: jq, htop, fish, ghostty"
# ─────────────────────────────────────────────────────────────────────────────
log "Installing jq, htop, fish and ghostty..."
dnf install -y jq htop fish ghostty
success "jq $(jq --version) installed."
success "htop installed."
success "fish $(fish --version 2>&1) installed."
success "ghostty installed."

# ─────────────────────────────────────────────────────────────────────────────
section "Security Tools: rkhunter, ClamAV, lynis"
# ─────────────────────────────────────────────────────────────────────────────
log "Installing rkhunter, clamav, clamd, clamav-update, lynis..."
dnf install -y rkhunter clamav clamd clamav-update lynis
success "rkhunter installed."
success "ClamAV installed."
success "lynis installed."

log "Updating rkhunter database..."
rkhunter --update || true          # exit 1 when already current; not a real error
success "rkhunter database up-to-date."

log "Updating ClamAV signatures..."
freshclam || true                  # may exit non-zero when signatures are current
success "ClamAV signatures up-to-date."

CLAMD_CONF="/etc/clamd.d/scan.conf"
CLAMD_SOCKET_LINE="LocalSocket /run/clamd.scan/clamd.sock"

log "Configuring clamd LocalSocket..."
if grep -qE "^LocalSocket " "${CLAMD_CONF}"; then
  warn "clamd LocalSocket already configured — skipping."
elif grep -qE "^#LocalSocket /run/clamd.scan/clamd.sock" "${CLAMD_CONF}"; then
  sed -i 's|^#LocalSocket /run/clamd.scan/clamd.sock|LocalSocket /run/clamd.scan/clamd.sock|' \
    "${CLAMD_CONF}"
  success "clamd LocalSocket configured."
else
  warn "Expected LocalSocket line not found in ${CLAMD_CONF} — appending."
  echo "${CLAMD_SOCKET_LINE}" >> "${CLAMD_CONF}"
  success "clamd LocalSocket appended."
fi

log "Enabling and starting clamd..."
systemctl enable --now clamd@scan
success "clamd@scan enabled and running."

# ─────────────────────────────────────────────────────────────────────────────
section "Visual Studio Code"
# ─────────────────────────────────────────────────────────────────────────────
if command -v code &>/dev/null; then
  warn "VS Code is already installed — skipping."
else
  log "Adding Microsoft VS Code repository..."
  rpm --import https://packages.microsoft.com/keys/microsoft.asc

  cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

  log "Installing Visual Studio Code..."
  dnf install -y code
  success "VS Code $(code --version | head -1) installed."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Google Chrome"
# ─────────────────────────────────────────────────────────────────────────────
if command -v google-chrome-stable &>/dev/null; then
  warn "Google Chrome is already installed — skipping."
else
  log "Adding Google Chrome repository..."
  rpm --import https://dl.google.com/linux/linux_signing_key.pub

  cat > /etc/yum.repos.d/google-chrome.repo <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

  log "Installing Google Chrome..."
  dnf install -y google-chrome-stable
  success "Google Chrome $(google-chrome-stable --version) installed."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "OpenSnitch (application firewall)"
# ─────────────────────────────────────────────────────────────────────────────
OPENSNITCH_VER="1.8.0"
if command -v opensnitchd &>/dev/null; then
  warn "OpenSnitch is already installed — skipping."
else
  log "Downloading OpenSnitch v${OPENSNITCH_VER} packages..."
  OPENSNITCH_BASE="https://github.com/evilsocket/opensnitch/releases/download/v${OPENSNITCH_VER}"
  OPENSNITCH_TMP=$(mktemp -d)

  curl -fSL -o "${OPENSNITCH_TMP}/opensnitch-${OPENSNITCH_VER}-1.x86_64.rpm" \
    "${OPENSNITCH_BASE}/opensnitch-${OPENSNITCH_VER}-1.x86_64.rpm"
  curl -fSL -o "${OPENSNITCH_TMP}/opensnitch-ui-${OPENSNITCH_VER}-1.noarch.rpm" \
    "${OPENSNITCH_BASE}/opensnitch-ui-${OPENSNITCH_VER}-1.noarch.rpm"

  log "Installing OpenSnitch..."
  dnf install -y "${OPENSNITCH_TMP}"/opensnitch*.rpm

  rm -rf "${OPENSNITCH_TMP}"

  log "Enabling and starting OpenSnitch daemon..."
  systemctl enable --now opensnitch
  success "OpenSnitch v${OPENSNITCH_VER} installed and running."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "TLP (power management)"
# ─────────────────────────────────────────────────────────────────────────────
if command -v tlp &>/dev/null; then
  warn "TLP is already installed — skipping."
else
  log "Removing conflicting power management daemons..."
  dnf remove -y tuned tuned-ppd power-profiles-daemon 2>/dev/null || true

  log "Setting Up tlp repository"
  dnf install -y "https://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc$(rpm -E %fedora).noarch.rpm"

  log "Installing TLP, TLP-PD, and TLP-RDW..."
  dnf install -y tlp tlp-pd tlp-rdw

  log "Enabling and starting TLP services..."
  systemctl enable --now tlp.service
  systemctl enable --now tlp-pd.service

  log "Masking rfkill services to prevent conflicts..."
  systemctl mask systemd-rfkill.service systemd-rfkill.socket

  success "TLP installed and running."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "EasyEffects (Flatpak)"
# ─────────────────────────────────────────────────────────────────────────────
if flatpak list --app | grep -q "com.github.wwmm.easyeffects"; then
  warn "EasyEffects is already installed — skipping."
else
  log "Installing EasyEffects from Flathub..."
  flatpak install -y flathub com.github.wwmm.easyeffects
  success "EasyEffects installed."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Discord"
# ─────────────────────────────────────────────────────────────────────────────
if command -v discord &>/dev/null; then
  warn "Discord is already installed — skipping."
else
  log "Enabling RPM Fusion free and nonfree repositories..."
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

  log "Installing Discord..."
  dnf install -y discord
  success "Discord installed."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "mise (dev tools version manager)"
# ─────────────────────────────────────────────────────────────────────────────
if su - "${REAL_USER}" -c "command -v mise" &>/dev/null; then
  warn "mise is already installed for ${REAL_USER} — skipping."
else
  log "Installing mise for user ${REAL_USER}..."

  # Install mise as the real user (not root)
  su - "${REAL_USER}" -c \
    "curl -fsSL https://mise.run | sh"

  # Add mise activation to shell config files if not present
  MISE_INIT='eval "$(~/.local/bin/mise activate bash)"'
  MISE_INIT_ZSH='eval "$(~/.local/bin/mise activate zsh)"'

  for RC in "${REAL_HOME}/.bashrc" "${REAL_HOME}/.bash_profile"; do
    if [[ -f "$RC" ]] && ! grep -q "mise activate" "$RC"; then
      echo "" >> "$RC"
      echo "# mise - dev tools version manager" >> "$RC"
      echo "${MISE_INIT}" >> "$RC"
      log "Added mise activation to $RC"
    fi
  done

  if [[ -f "${REAL_HOME}/.zshrc" ]] && ! grep -q "mise activate" "${REAL_HOME}/.zshrc"; then
    echo "" >> "${REAL_HOME}/.zshrc"
    echo "# mise - dev tools version manager" >> "${REAL_HOME}/.zshrc"
    echo "${MISE_INIT_ZSH}" >> "${REAL_HOME}/.zshrc"
    log "Added mise activation to .zshrc"
  fi

  # Add mise activation to fish config
  FISH_CONFIG_DIR="${REAL_HOME}/.config/fish"
  FISH_CONFIG="${FISH_CONFIG_DIR}/config.fish"
  mkdir -p "$FISH_CONFIG_DIR"
  chown "${REAL_USER}:${REAL_USER}" "$FISH_CONFIG_DIR"
  if [[ ! -f "$FISH_CONFIG" ]] || ! grep -q "mise activate" "$FISH_CONFIG"; then
    echo "" >> "$FISH_CONFIG"
    echo "# mise - dev tools version manager" >> "$FISH_CONFIG"
    echo "~/.local/bin/mise activate fish | source" >> "$FISH_CONFIG"
    chown "${REAL_USER}:${REAL_USER}" "$FISH_CONFIG"
    log "Added mise activation to $FISH_CONFIG"
  fi

  success "mise installed. Restart your shell or run: eval \"\$(~/.local/bin/mise activate bash)\""
fi

# ─────────────────────────────────────────────────────────────────────────────
section "fish — Set as Default Shell"
# ─────────────────────────────────────────────────────────────────────────────
FISH_PATH="$(command -v fish)"

# Ensure fish is listed in /etc/shells
if ! grep -qxF "$FISH_PATH" /etc/shells; then
  log "Adding $FISH_PATH to /etc/shells..."
  echo "$FISH_PATH" >> /etc/shells
fi

CURRENT_SHELL=$(getent passwd "${REAL_USER}" | cut -d: -f7)
if [[ "$CURRENT_SHELL" == "$FISH_PATH" ]]; then
  warn "fish is already the default shell for ${REAL_USER} — skipping."
else
  log "Setting fish as the default shell for ${REAL_USER}..."
  chsh -s "$FISH_PATH" "${REAL_USER}"
  success "Default shell changed to fish ($FISH_PATH)."
fi

# Also wire up mise activation for fish (idempotent, in case mise was pre-installed)
FISH_CONFIG_DIR="${REAL_HOME}/.config/fish"
FISH_CONFIG="${FISH_CONFIG_DIR}/config.fish"
mkdir -p "$FISH_CONFIG_DIR"
chown "${REAL_USER}:${REAL_USER}" "$FISH_CONFIG_DIR"
if [[ ! -f "$FISH_CONFIG" ]] || ! grep -q "mise activate" "$FISH_CONFIG"; then
  log "Adding mise activation to fish config..."
  echo "" >> "$FISH_CONFIG"
  echo "# mise - dev tools version manager" >> "$FISH_CONFIG"
  echo "~/.local/bin/mise activate fish | source" >> "$FISH_CONFIG"
  chown "${REAL_USER}:${REAL_USER}" "$FISH_CONFIG"
  success "mise activation added to $FISH_CONFIG"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "ghostty — Set as Default Terminal (KDE Plasma)"
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v kwriteconfig6 &>/dev/null; then
  warn "kwriteconfig6 not found — skipping KDE terminal default setup."
  warn "You can set Ghostty manually in: System Settings → Keyboard → Shortcuts → Terminal."
else
  log "Setting Ghostty as the default KDE terminal application..."

  # Write to the real user's KDE config (must not be done as root)
  su - "${REAL_USER}" -c "
    kwriteconfig6 --file kdeglobals --group General \
      --key TerminalApplication ghostty
    kwriteconfig6 --file kdeglobals --group General \
      --key TerminalService ghostty.desktop
  "

  # Reload KDE globals so it takes effect without a full logout
  su - "${REAL_USER}" -c \
    "dbus-send --session --type=signal /KGlobalSettings \
     org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null || true"

  success "Ghostty set as the default KDE terminal."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Btrfs Snapshots & Rollback (snapper + grub-btrfs)"
# ─────────────────────────────────────────────────────────────────────────────
if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
  warn "Root filesystem is not Btrfs — skipping snapshot setup."
else
  log "Making GRUB menu always visible..."
  grub2-editenv - unset menu_auto_hide

  log "Installing snapper, btrfs-assistant, libdnf5-plugin-actions, inotify-tools..."
  dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools git make

  log "Creating snapper configurations for / and /home..."
  snapper -c root create-config / || true
  snapper -c home create-config /home || true

  log "Restoring SELinux contexts on snapshot directories..."
  restorecon -RFv /.snapshots
  restorecon -RFv /home/.snapshots

  log "Granting ${REAL_USER} access to snapper..."
  snapper -c root set-config "ALLOW_USERS=${REAL_USER}" SYNC_ACL=yes
  snapper -c home set-config "ALLOW_USERS=${REAL_USER}" SYNC_ACL=yes

  log "Disabling timeline snapshots for /home (snapshots on DNF only)..."
  snapper -c home set-config TIMELINE_CREATE=no

  log "Preventing updatedb from indexing .snapshots..."
  if ! grep -q '\.snapshots' /etc/updatedb.conf; then
    echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf
  fi

  log "Setting up DNF actions for automatic pre/post snapshots..."
  mkdir -p /etc/dnf/libdnf5-plugins/actions.d
  cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions <<'EOF'
# Capture the command that triggered the transaction
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"

# Create a pre-snapshot and store its number
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '${tmp.cmd}')"

# Create a post-snapshot paired with the pre-snapshot
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -c\ number\ -d\ "${tmp.cmd}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.cmd
EOF

  log "Installing grub-btrfs (boot into snapshots from GRUB)..."
  GRUB_BTRFS_TMP=$(mktemp -d)
  git clone https://github.com/Antynea/grub-btrfs "${GRUB_BTRFS_TMP}/grub-btrfs"
  pushd "${GRUB_BTRFS_TMP}/grub-btrfs" > /dev/null

  # Apply Fedora-specific settings to grub-btrfs config
  sed -i \
    -e '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=/a GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
    -e '/^#GRUB_BTRFS_GRUB_DIRNAME=/a GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"' \
    -e '/^#GRUB_BTRFS_MKCONFIG=/a GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig' \
    -e '/^#GRUB_BTRFS_SCRIPT_CHECK=/a GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check' \
    config

  make install
  popd > /dev/null
  rm -rf "${GRUB_BTRFS_TMP}"

  log "Enabling snapper and grub-btrfs services..."
  systemctl enable --now grub-btrfsd.service
  systemctl enable --now snapper-timeline.timer
  systemctl enable --now snapper-cleanup.timer

  success "Btrfs snapshot support configured (snapper + grub-btrfs)."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "All Done!"
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}"
echo "  ✔  jq"
echo "  ✔  htop"
echo "  ✔  rkhunter, ClamAV, lynis"
echo "  ✔  Visual Studio Code"
echo "  ✔  Google Chrome"
echo "  ✔  OpenSnitch"
echo "  ✔  TLP"
echo "  ✔  EasyEffects"
echo "  ✔  Discord"
echo "  ✔  mise"
echo "  ✔  fish  (default shell)"
echo "  ✔  ghostty  (default KDE terminal)"
echo "  ✔  Btrfs snapshots (snapper + grub-btrfs)"
echo -e "${NC}"
echo -e "${BOLD}Next steps:${NC}"
echo "  • Log out and back in for the fish default shell to take effect."
echo "  • Run 'mise doctor' inside a fish session to verify mise is set up correctly."
echo "  • Run 'flatpak update' periodically to keep Flatpak apps current."
echo "  • Use 'snapper ls' to list snapshots; 'btrfs-assistant' GUI for rollbacks."
echo ""
