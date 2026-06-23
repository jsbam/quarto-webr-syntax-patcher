#!/bin/bash

# Quarto WebR Syntax Highlighting Unpatcher
# This script restores the original Quarto VS Code/Positron extension from backups

set -e

# Parse command line arguments
TARGET_IDE="both"
while [[ $# -gt 0 ]]; do
    case $1 in
        --positron)
            TARGET_IDE="positron"
            shift
            ;;
        --vscode)
            TARGET_IDE="vscode"
            shift
            ;;
        --both)
            TARGET_IDE="both"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--positron|--vscode|--both]"
            echo ""
            echo "Options:"
            echo "  --positron    Unpatch only Positron IDE"
            echo "  --vscode      Unpatch only VS Code"
            echo "  --both        Unpatch both IDEs (default)"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
    OS="Windows"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macOS"
else
    OS="Linux"
fi

# Find Quarto extension directories
find_quarto_extensions() {
    local base_dir="$1"
    if [ -d "$base_dir" ]; then
        find "$base_dir" -maxdepth 1 -type d -name "quarto.quarto-*" 2>/dev/null | sort -V
    fi
}

# Get Windows-style paths for extension directories
if [ "$OS" = "Windows" ]; then
    # Try multiple common Windows locations
    if [ -n "$APPDATA" ]; then
        VSCODE_WIN="$APPDATA/Code/extensions"
        POSITRON_WIN="$APPDATA/Positron/extensions"
    else
        VSCODE_WIN="$HOME/AppData/Roaming/Code/extensions"
        POSITRON_WIN="$HOME/AppData/Roaming/Positron/extensions"
    fi
    
    # Also check .vscode and .positron in home
    VSCODE_HOME="$HOME/.vscode/extensions"
    POSITRON_HOME="$HOME/.positron/extensions"
fi

# Find all Quarto extensions based on target IDE
QUARTO_EXTENSIONS=()
if [ "$OS" = "Windows" ]; then
    # Check Positron locations
    if [[ "$TARGET_IDE" == "positron" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$POSITRON_WIN" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
            done < <(find_quarto_extensions "$POSITRON_WIN")
        fi
        if [ -d "$POSITRON_HOME" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
            done < <(find_quarto_extensions "$POSITRON_HOME")
        fi
    fi
    # Check VS Code locations
    if [[ "$TARGET_IDE" == "vscode" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$VSCODE_WIN" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
            done < <(find_quarto_extensions "$VSCODE_WIN")
        fi
        if [ -d "$VSCODE_HOME" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
            done < <(find_quarto_extensions "$VSCODE_HOME")
        fi
    fi
else
    # macOS/Linux paths
    if [[ "$TARGET_IDE" == "positron" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$HOME/.positron/extensions" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
            done < <(find_quarto_extensions "$HOME/.positron/extensions")
        fi
    fi
    if [[ "$TARGET_IDE" == "vscode" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$HOME/.vscode/extensions" ]; then
            while IFS= read -r EXT; do
                [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
            done < <(find_quarto_extensions "$HOME/.vscode/extensions")
        fi
    fi
fi

if [ ${#QUARTO_EXTENSIONS[@]} -eq 0 ]; then
    if [ "$TARGET_IDE" = "both" ]; then
        echo -e "${RED}Error: No Quarto extensions found in VS Code or Positron${NC}"
    elif [ "$TARGET_IDE" = "positron" ]; then
        echo -e "${RED}Error: No Quarto extension found in Positron${NC}"
    else
        echo -e "${RED}Error: No Quarto extension found in VS Code${NC}"
    fi
    exit 1
fi

echo -e "${GREEN}Found ${#QUARTO_EXTENSIONS[@]} Quarto extension(s):${NC}"
for ext_info in "${QUARTO_EXTENSIONS[@]}"; do
    IDE="${ext_info%%:*}"
    EXT_PATH="${ext_info#*:}"
    echo "  - $IDE: $EXT_PATH"
done
echo

# Function to unpatch a single extension
unpatch_extension() {
    local IDE="$1"
    local QUARTO_EXT="$2"
    
    echo -e "${YELLOW}Processing $IDE extension...${NC}"
    
    GRAMMAR_FILE="$QUARTO_EXT/syntaxes/quarto.tmLanguage"
    PACKAGE_FILE="$QUARTO_EXT/package.json"
    GRAMMAR_BACKUP="$GRAMMAR_FILE.backup"
    PACKAGE_BACKUP="$PACKAGE_FILE.backup"
    
    # Check if backup files exist
    if [ ! -f "$GRAMMAR_BACKUP" ]; then
        echo -e "${YELLOW}  ⚠ No backup found for grammar file${NC}"
        echo -e "${YELLOW}  Extension may not have been patched or backups were deleted${NC}"
        return 0
    fi
    
    if [ ! -f "$PACKAGE_BACKUP" ]; then
        echo -e "${YELLOW}  ⚠ No backup found for package.json${NC}"
        echo -e "${YELLOW}  Extension may not have been patched or backups were deleted${NC}"
        return 0
    fi
    
    # Check if currently patched
    if ! grep -q "fenced_code_block_webr" "$GRAMMAR_FILE"; then
        echo -e "${GREEN}  ✓ Extension is not patched (nothing to do)${NC}"
        return 0
    fi
    
    # Restore from backups
    echo "  Restoring from backups..."
    cp "$GRAMMAR_BACKUP" "$GRAMMAR_FILE"
    cp "$PACKAGE_BACKUP" "$PACKAGE_FILE"
    
    # Verify restoration
    if grep -q "fenced_code_block_webr" "$GRAMMAR_FILE"; then
        echo -e "${RED}  ✗ Failed to restore (webr still present)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}  ✓ Successfully restored original files for $IDE!${NC}"
    echo "  You can now delete the backup files if desired:"
    echo "    $GRAMMAR_BACKUP"
    echo "    $PACKAGE_BACKUP"
    echo
}

# Unpatch all found extensions
for ext_info in "${QUARTO_EXTENSIONS[@]}"; do
    IDE="${ext_info%%:*}"
    EXT_PATH="${ext_info#*:}"
    unpatch_extension "$IDE" "$EXT_PATH"
done

echo -e "${GREEN}All extensions processed!${NC}"
echo -e "${YELLOW}Please restart VS Code and/or Positron for changes to take effect.${NC}"
