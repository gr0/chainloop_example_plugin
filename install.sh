#!/usr/bin/env bash
set -euo pipefail

# Delivered through Cloudflare Worker
# Based on https://developer.fermyon.com/ install script thanks!
# Fancy colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color aka reset

# Version to install. Defaults to latest or set by --version or -v
VERSION=""
PLATFORM_PLUGIN_VERSION=""
FORCE_VERIFICATION=false
WITH_INSTALL_PLATFORM_PLUGIN=false
INSTALL_PATH=/usr/local/bin
PUBLIC_KEY_URL="https://raw.githubusercontent.com/chainloop-dev/chainloop/01ad13af08950b7bfbc83569bea207aeb4e1a285/docs/static/cosign-releases.pub"

# Constants
GITHUB_BASE_URL="https://github.com/chainloop-dev/chainloop/releases/download"
GITHUB_LATEST_RELEASE_URL="https://github.com/chainloop-dev/chainloop/releases/latest"
PLATFORM_PLUGIN_BASE_URL="https://chainloopplatform.blob.core.windows.net/public/chainloop-platform-plugin/"
PLATFORM_PLUGIN_BASE_FILENAME="chainloop-platform"
PLATFORM_PLUGIN_LATEST_FILE="latest.txt"

# Print in colors - 0=green, 1=red, 2=neutral
# e.g. fancy_print 0 "All is great"
fancy_print() {
    if [[ $1 == 0 ]]; then
        echo -e "${GREEN}${2}${NC}"
    elif [[ $1 == 1 ]]; then
        echo -e "${RED}${2}${NC}"
    else
        echo -e "${2}"
    fi
}


# Function to print the help message
print_help() {
    fancy_print 2 ""
    fancy_print 2 "---- Chainloop Installer Script ----"
    fancy_print 2 "This script installs Chainloop in the current directory."
    fancy_print 2 ""
    fancy_print 2 "Command line arguments"
    fancy_print 2 "--version or -v           Provide what version to install e.g. \"v0.5.0\"."
    fancy_print 2 "--path                    Installation path (default: /usr/local/bin)"
    fancy_print 2 "--force-verification      Force signature verification of the binary with cosign."
    fancy_print 2 "--with-platform-plugin    Install platform plugin."
    fancy_print 2 "--platform-plugin-version Provide what version of the platform plugin to install e.g. \"v0.5.0\"."
    fancy_print 2 "--help or -h              Shows this help message"
}

# Function used to check if utilities are available
require() {
    if ! hash "$1" &>/dev/null; then
        fancy_print 1 "'$1' not found in PATH. This is required for this script to work."
        exit 1
    fi
}

# check if a command exist
is_command() {
  command -v "$1" >/dev/null
}

# checksums.txt file validation
# example: check_sha256 "${TMP_DIR}" checksums.txt
validate_checksums_file() {
  cd "$1"
  grep "$FILENAME" "$2" > checksum.txt
  if is_command sha256sum; then
    sha256sum -c checksum.txt
  elif is_command shasum; then
    shasum -a 256 -q -c checksum.txt
  else
    fancy_print 1 "We were not able to verify checksums. Commands sha256sum, shasum are not found."
    return 1
  fi
  fancy_print 2 "Checksum OK\n"
}

# Check legacy installations downloads and inspects the checksum.txt file
# New Chainloop releases does not include the .tar.gz files for the CLI anymore
# and instead provides a single binary file for each OS and architecture that can be downloaded
# directly.
check_if_legacy_installation() {
    local TMP_DIR=$1
    local CHECKSUM_FILE="${TMP_DIR}/checksums.txt"
    local URL="${GITHUB_BASE_URL}/v${VERSION}/checksums.txt"

    CHECKSUM_FILENAME=checksums.txt
    CHECKSUM_FILE="$TMP_DIR/${CHECKSUM_FILENAME}"
    curl -fsL "$URL" -o "${CHECKSUM_FILE}" || (fancy_print 1 "The requested file does not exist: ${URL}"; exit 1)

    grep -q "chainloop-cli-${VERSION}-${OS}-${ARC}.tar.gz" "$CHECKSUM_FILE" && echo "true" || echo "false"
}

# Get the latest version from the GitHub releases page
get_latest_version() {
    curl -sI -o /dev/null -w '%{redirect_url}' "$GITHUB_LATEST_RELEASE_URL" | sed -n 's#.*/tag/\(v.*\)#\1#p'
}

# Download the checksum file and verify it
download_and_check_checksum() {
    local TMP_DIR=$1
    local BASE_URL=$2

    CHECKSUM_FILENAME=checksums.txt
    CHECKSUM_FILE="$TMP_DIR/${CHECKSUM_FILENAME}"
    URL="$BASE_URL/${CHECKSUM_FILENAME}"
    curl -fsL "$URL" -o "${CHECKSUM_FILE}" || (fancy_print 1 "The requested file does not exist: ${URL}"; exit 1)
    validate_checksums_file "${TMP_DIR}" checksums.txt

    # Verify checksum file signature
    if hash "cosign" &>/dev/null; then
        # Constructing download FILE and URL
        SIGNATURE_FILE="${CHECKSUM_FILENAME}.sig"
        URL="$BASE_URL/${SIGNATURE_FILE}"
        # Download file, exit if not found - e.g. version does not exist
        fancy_print 0 "Step 1.3: Verifying signature"
        curl -fsOL "$URL" || (fancy_print 1 "The requested file does not exist: ${SIGNATURE_FILE}"; exit 1)
        cosign verify-blob --key ${PUBLIC_KEY_URL} --signature ${SIGNATURE_FILE} "${CHECKSUM_FILE}"

        rm $SIGNATURE_FILE
    else
        fancy_print 2 "\nSignature verification skipped, cosign is not installed\n"
    fi
}

cleanup() {
    local tmp_dir=$1
    rm -rf "$tmp_dir"
    fancy_print 0 "Done...\n"
}

install_binary() {
    local binary_path=$1
    install "$binary_path" "${INSTALL_PATH}/" 2>/dev/null || sudo install "$binary_path" "${INSTALL_PATH}/"
}

post_install_message() {
    "${INSTALL_PATH}/chainloop" version
    fancy_print 2 "Check here for the next steps: https://docs.chainloop.dev\n"
    fancy_print 2 "Run 'chainloop auth login' to get started"
}

post_install_plugin_message() {
    fancy_print 2 "Platform plugin installed\n"
}

download_and_install_legacy() {
  local TMP_DIR=$1
  local VERSION=$2
  FILENAME="chainloop-cli-${VERSION}-${OS}-${ARC}.tar.gz"
  # Constructing download FILE and URL
  FILE="$TMP_DIR/${FILENAME}"

  BASE_URL="${GITHUB_BASE_URL}/v${VERSION}"

  URL="${BASE_URL}/${FILENAME}"
  # Download file, exit if not found - e.g. version does not exist
  fancy_print 0 "Step 1: Downloading: ${FILENAME}"
  curl -fsL "$URL" -o "$FILE" || (fancy_print 1 "The requested file does not exist: ${URL}"; exit 1)
  fancy_print 0 "Done...\n"

  # Get checksum file and check it
  fancy_print 0 "Step 1.2: Verifying checksum"
  download_and_check_checksum "$TMP_DIR" "$BASE_URL"

  # Decompress the file
  fancy_print 0 "Step 2: Decompressing: ${FILE}"
  (cd "${TMP_DIR}" && tar xf "$FILE")
  fancy_print 0 "Done...\n"

  # Install
  fancy_print 0 "Step 3: Installing: chainloop in path ${INSTALL_PATH}"
  install_binary "${TMP_DIR}/chainloop"

  # Remove the compressed file
  fancy_print 0 "Step 4: Cleanup"
  cleanup "$TMP_DIR"

  if [[ $WITH_INSTALL_PLATFORM_PLUGIN = false ]]; then
    post_install_message
  fi
}

download_and_install() {
    local TMP_DIR=$1
    local VERSION=$2
    BASE_URL="${GITHUB_BASE_URL}/v${VERSION}"

    FILENAME="chainloop-${OS}-${ARC}"
    # Constructing download FILE and URL
    FILE="$TMP_DIR/${FILENAME}"

    URL="${BASE_URL}/${FILENAME}"
    # Download file, exit if not found - e.g. version does not exist
    fancy_print 0 "Step 1: Downloading: ${FILENAME}, Version: ${VERSION}"
    curl -fsL "$URL" -o "$FILE" || (fancy_print 1 "The requested file does not exist: ${URL}"; exit 1)
    fancy_print 0 "Done...\n"

    # Get checksum file and check it
    fancy_print 0 "Step 1.2: Verifying checksum"
    download_and_check_checksum "$TMP_DIR" "$BASE_URL"

    # Modify the name of the binary
    # From chainloop-OS-ARCH to chainloop
    cp "${FILE}" "chainloop"

    # Install
    fancy_print 0 "Step 2: Installing: chainloop to ${INSTALL_PATH}"
    install_binary "${TMP_DIR}/chainloop"

    fancy_print 0 "Step 3: Cleanup"
    cleanup "$TMP_DIR"

    if [[ $WITH_INSTALL_PLATFORM_PLUGIN = false ]]; then
      post_install_message
    fi
}

download_and_install_platform_plugin() {
    local VERSION=$1
    local TMP_DIR=$(mktemp -d)
    local LATEST_FILE="${TMP_DIR}/${PLATFORM_PLUGIN_LATEST_FILE}"
    local LATEST_URL="${PLATFORM_PLUGIN_BASE_URL}${PLATFORM_PLUGIN_LATEST_FILE}"
    
    local PLUGIN_VERSION
    
    # If no version specified, download and read from latest.txt file
    if [[ -z "$VERSION" ]]; then
        fancy_print 0 "Step 1: Determining latest version"
        curl -fsL "${LATEST_URL}" -o "${LATEST_FILE}" || {
            fancy_print 1 "Failed to determine latest version"
            cleanup "$TMP_DIR"
            exit 1
        }
        
        # Read version from latest.txt file - we publish it to main folder
        PLUGIN_VERSION=$(cat "${LATEST_FILE}" | tr -d '\n\r' | xargs)
        if [[ -z "$PLUGIN_VERSION" ]]; then
            fancy_print 1 "Failed to determine latest version"
            cleanup "$TMP_DIR"
            exit 1
        fi
        fancy_print 0 "Using latest version: ${PLUGIN_VERSION}"
    else
        # Use the provided version, add 'v' prefix if not present. 
        # This is done so we are in line with Goreleaser and can use the same logic down the line.
        if [[ "$VERSION" =~ ^v ]]; then
            PLUGIN_VERSION="$VERSION"
        else
            PLUGIN_VERSION="v$VERSION"
        fi
        fancy_print 0 "Using specified version: ${PLUGIN_VERSION}"
    fi

    # Strip 'v' prefix from version for directory paths - this is how Goreleaser publishes it
    local VERSION_DIR="${PLUGIN_VERSION#v}"

    # Construct plugin filename using the version without 'v' prefix to match checksums file
    local PLUGIN_FILENAME="chainloop-plugin-${VERSION_DIR}-${OS}-${ARC}"
    
    # Download checksums file to get the SHA for verification
    local CHECKSUMS_FILE="${TMP_DIR}/checksums.txt"
    local CHECKSUMS_URL="${PLATFORM_PLUGIN_BASE_URL}${VERSION_DIR}/checksums.txt"
    
    fancy_print 0 "Step 2: Downloading checksums"
    curl -fsL "${CHECKSUMS_URL}" -o "${CHECKSUMS_FILE}" || {
        fancy_print 1 "Failed to download checksums"
        cleanup "$TMP_DIR"
        exit 1
    }
    
    # Extract SHA from checksums.txt for the specific plugin file
    local CHECKSUM_LINE
    CHECKSUM_LINE=$(grep "${PLUGIN_FILENAME}" "${CHECKSUMS_FILE}" | head -n1)
    if [[ -z "$CHECKSUM_LINE" ]]; then
        fancy_print 1 "Failed to find checksum for: ${PLUGIN_FILENAME}"
        cleanup "$TMP_DIR"
        exit 1
    fi
    
    local EXPECTED_SHA=$(echo "$CHECKSUM_LINE" | awk '{print $1}')
    if [[ -z "$EXPECTED_SHA" ]]; then
        fancy_print 1 "Failed to parse SHA for ${PLUGIN_FILENAME}"
        cleanup "$TMP_DIR"
        exit 1
    fi
        
    # Download the plugin for SHA verification
    local PLUGIN_DOWNLOAD_URL="${PLATFORM_PLUGIN_BASE_URL}${VERSION_DIR}/${PLUGIN_FILENAME}"
    local PLUGIN_FILE="${TMP_DIR}/${PLUGIN_FILENAME}"
    
    fancy_print 0 "Step 3: Downloading plugin: ${PLUGIN_FILENAME}"
    curl -fsL "${PLUGIN_DOWNLOAD_URL}" -o "${PLUGIN_FILE}" || {
        fancy_print 1 "Failed to download plugin: ${PLUGIN_DOWNLOAD_URL}"
        cleanup "$TMP_DIR"
        exit 1
    }
    
    fancy_print 0 "Step 4: Verifying SHA256 checksum"
    local ACTUAL_SHA
    if is_command sha256sum; then
        ACTUAL_SHA=$(sha256sum "${PLUGIN_FILE}" | awk '{print $1}')
    elif is_command shasum; then
        ACTUAL_SHA=$(shasum -a 256 "${PLUGIN_FILE}" | awk '{print $1}')
    else
        fancy_print 1 "Cannot verify checksum: sha256sum or shasum not found"
        cleanup "$TMP_DIR"
        exit 1
    fi
    
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        fancy_print 1 "SHA256 checksum verification failed!"
        fancy_print 1 "Expected: ${EXPECTED_SHA}"
        fancy_print 1 "Actual:   ${ACTUAL_SHA}"
        cleanup "$TMP_DIR"
        exit 1
    fi
    
    fancy_print 0 "Checksum verification passed!"
    
    fancy_print 0 "Step 5: Installing Chainloop platform plugin: ${PLUGIN_FILENAME}"
    chainloop config plugin install --file "${PLUGIN_FILE}"
    fancy_print 0 "Done...\n"
    
    cleanup "$TMP_DIR"

    post_install_message
}

# Parse input arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    '--version' | -v)
        shift
        if [[ $# -ne 0 ]]; then
            # Remove v prefix if provided
            VERSION="$(echo ${1} | sed -e 's/^v\(.*\)/\1/')"
        else
            fancy_print 1 "Please provide the desired version. e.g. --version v0.5.0"
            exit 0
        fi
        ;;
    '--help' | -h)
        shift
        print_help
        ;;
    '--force-verification')
        FORCE_VERIFICATION=true
        ;;
    '--with-platform-plugin')
        WITH_INSTALL_PLATFORM_PLUGIN=true
        ;;
    '--platform-plugin-version')
        shift
        if [[ $# -ne 0 ]]; then
            PLATFORM_PLUGIN_VERSION="$(echo ${1} | sed -e 's/^v\(.*\)/\1/')"
        else
            fancy_print 1 "Please provide the desired version. e.g. --platform-plugin-version v0.5.0"
            exit 0
        fi
        ;;
    '--path')
        shift
        INSTALL_PATH=$1
        ;;
    *)
        fancy_print 1 "Unknown argument ${1}."
        print_help
        exit 1
        ;;
    esac
    shift
done

# Check all required utilities are available
require curl
require tar
require uname

if ! hash "cosign" &>/dev/null; then
    if [[ $FORCE_VERIFICATION = true ]]; then
        fancy_print 1 "--force-verification was set but Cosign is not present. Please download it from here https://docs.sigstore.dev/cosign/installation"
        exit 1
    fi
fi

# Check if we're on a supported system and get OS and processor architecture to download the right version
UNAME_ARC=$(uname -m)

case $UNAME_ARC in
"x86_64")
    ARC="amd64"
    ;;
"arm64"|"aarch64")
    ARC="arm64"
    ;;
*)
    fancy_print 1 "The Processor type: ${UNAME_ARC} is not yet supported by Chainloop."
    exit 1
    ;;
esac

case $OSTYPE in
"linux-gnu"*)
    OS="linux"
    ;;
"darwin"*)
    OS="darwin"
    ;;
*)
    fancy_print 1 "The OSTYPE: ${OSTYPE} is not supported by this script."
    exit 1
    ;;
esac

# Check desired version. Default to latest if no desired version was requested
# Remove v prefix
VERSION="${VERSION:-$(get_latest_version | sed 's/^v//')}"

# Temporary directory, works on Linux and macOS
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')

# Decide which method to use to install Chainloop
if [[ $(check_if_legacy_installation "$TMP_DIR") == "true" ]]; then
    download_and_install_legacy "$TMP_DIR" "$VERSION"
else
    download_and_install "$TMP_DIR" "$VERSION"
fi

if [[ $WITH_INSTALL_PLATFORM_PLUGIN = true ]]; then
    download_and_install_platform_plugin "$PLATFORM_PLUGIN_VERSION"
fi
