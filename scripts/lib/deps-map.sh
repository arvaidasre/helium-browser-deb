#!/usr/bin/env bash
# ==============================================================================
# deps-map.sh — Dependency mapping for different distributions
# ==============================================================================
# Maps Helium browser dependencies to distro-specific package names
# ==============================================================================

# Get deps for a specific distro and release
get_deb_deps() {
  local distro="$1"  # ubuntu or debian
  local codename="$2" # noble, jammy, focal, bookworm, bullseye
  
  # Base dependencies that are common
  local common_deps=(
    "ca-certificates"
    "libgtk-3-0"
    "libnss3"
    "libxss1"
    "libgbm1"
    "xdg-utils"
  )
  
  # Distro-specific mappings
  case "$distro:$codename" in
    ubuntu:noble|ubuntu:oracular)
      # Ubuntu 24.04+
      echo "${common_deps[*]}" "libasound2t64" "libcurl4t64" "libegl1" "libgl1"
      ;;
    ubuntu:jammy|ubuntu:mantic)
      # Ubuntu 22.04-23.10
      echo "${common_deps[*]}" "libasound2" "libcurl4" "libegl1" "libgl1"
      ;;
    ubuntu:focal)
      # Ubuntu 20.04
      echo "${common_deps[*]}" "libasound2" "libcurl4" "libegl1-mesa" "libgl1-mesa-glx"
      ;;
    debian:bookworm|debian:trixie)
      # Debian 12+
      echo "${common_deps[*]}" "libasound2" "libcurl4" "libegl1" "libgl1"
      ;;
    debian:bullseye)
      # Debian 11
      echo "${common_deps[*]}" "libasound2" "libcurl4" "libegl1-mesa" "libgl1-mesa-glx"
      ;;
    *)
      # Default fallback
      echo "${common_deps[*]}" "libasound2" "libcurl4" "libegl1" "libgl1"
      ;;
  esac
}

get_rpm_deps() {
  local distro="$1"  # fedora, rhel, centos, opensuse
  local version="$2" # 39, 40, 9, 8, etc.
  
  # Common RPM deps
  local common_deps=(
    "ca-certificates"
    "gtk3"
    "nss"
    "libXScrnSaver"
    "alsa-lib"
    "mesa-libgbm"
    "libdrm"
    "xdg-utils"
    "libglvnd-glx"
    "libglvnd-egl"
  )
  
  case "$distro" in
    fedora)
      echo "${common_deps[*]}" "curl-minimal"
      ;;
    rhel|centos|almalinux|rocky)
      echo "${common_deps[*]}" "curl"
      ;;
    opensuse*)
      echo "${common_deps[*]}" "curl" "libgbm1"
      ;;
    *)
      echo "${common_deps[*]}" "curl"
      ;;
  esac
}

# Generate fpm --depends flags from dep list
generate_fpm_deps() {
  local deps="$1"
  for dep in $deps; do
    echo "--depends $dep"
  done
}

# Get recommended packages for DEB
get_deb_recommends() {
  echo "apparmor fonts-liberation libu2f-udev"
}

# Get suggested packages for DEB
get_deb_suggests() {
  echo "pulseaudio"
}
