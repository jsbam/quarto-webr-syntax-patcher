#!/bin/bash

# Quarto WebR Syntax Highlighting Patcher
# This script patches the Quarto VS Code/Positron extension to add WebR syntax highlighting

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
            echo "  --positron    Patch only Positron IDE"
            echo "  --vscode      Patch only VS Code"
            echo "  --both        Patch both IDEs (default)"
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

# Find Quarto extension directory
find_quarto_extension() {
    local base_dir="$1"
    if [ -d "$base_dir" ]; then
        find "$base_dir" -maxdepth 1 -type d -name "quarto.quarto-*" 2>/dev/null | head -1
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
            EXT=$(find_quarto_extension "$POSITRON_WIN")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
        fi
        if [ -d "$POSITRON_HOME" ]; then
            EXT=$(find_quarto_extension "$POSITRON_HOME")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
        fi
    fi
    # Check VS Code locations
    if [[ "$TARGET_IDE" == "vscode" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$VSCODE_WIN" ]; then
            EXT=$(find_quarto_extension "$VSCODE_WIN")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
        fi
        if [ -d "$VSCODE_HOME" ]; then
            EXT=$(find_quarto_extension "$VSCODE_HOME")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
        fi
    fi
else
    # macOS/Linux paths
    if [[ "$TARGET_IDE" == "positron" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$HOME/.positron/extensions" ]; then
            EXT=$(find_quarto_extension "$HOME/.positron/extensions")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("Positron:$EXT")
        fi
    fi
    if [[ "$TARGET_IDE" == "vscode" || "$TARGET_IDE" == "both" ]]; then
        if [ -d "$HOME/.vscode/extensions" ]; then
            EXT=$(find_quarto_extension "$HOME/.vscode/extensions")
            [ -n "$EXT" ] && QUARTO_EXTENSIONS+=("VS Code:$EXT")
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

# Function to patch a single extension
patch_extension() {
    local IDE="$1"
    local QUARTO_EXT="$2"
    
    echo -e "${YELLOW}Processing $IDE extension...${NC}"
    
    GRAMMAR_FILE="$QUARTO_EXT/syntaxes/quarto.tmLanguage"
    PACKAGE_FILE="$QUARTO_EXT/package.json"

    # Check if files exist
    if [ ! -f "$GRAMMAR_FILE" ]; then
        echo -e "${RED}  Error: Grammar file not found at $GRAMMAR_FILE${NC}"
        return 1
    fi
    
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo -e "${RED}  Error: package.json not found at $PACKAGE_FILE${NC}"
        return 1
    fi
    
    # Check if already patched
    if grep -q "fenced_code_block_webr" "$GRAMMAR_FILE"; then
        echo -e "${GREEN}  ✓ WebR syntax highlighting already installed!${NC}"
        return 0
    fi

    # Backup original files
    echo "  Creating backups..."
    cp "$GRAMMAR_FILE" "$GRAMMAR_FILE.backup"
    cp "$PACKAGE_FILE" "$PACKAGE_FILE.backup"
    
    echo "  Patching grammar file..."

    # Find the line number for fenced_code_block_r definition
    R_BLOCK_START=$(grep -n '<key>fenced_code_block_r</key>' "$GRAMMAR_FILE" | head -1 | cut -d: -f1)
    
    if [ -z "$R_BLOCK_START" ]; then
        echo -e "${RED}  Error: Could not find R block definition${NC}"
        return 1
    fi
    
    # Find the closing </dict> for the R block by counting dict depth
    # We need to find the matching closing tag at the same indentation level
    R_BLOCK_END=$(awk -v start="$R_BLOCK_START" '
        NR < start { next }
        NR == start { depth = 0; next }
        /<dict>/ { depth++ }
        /<\/dict>/ { 
            depth--
            if (depth == 0 && /^      <\/dict>$/) {
                print NR
                exit
            }
        }
    ' "$GRAMMAR_FILE")
    
    if [ -z "$R_BLOCK_END" ]; then
        echo -e "${RED}  Error: Could not find R block closing tag${NC}"
        return 1
    fi

    # Create temporary file with the webr block definition
    TEMP_WEBR="$GRAMMAR_FILE.webr_block"
    cat > "$TEMP_WEBR" <<'EOF'
      <key>fenced_code_block_webr</key>
      <dict>
        <key>begin</key>
        <string>(^|\G)(\s*)(`{3,}|~{3,})\s*(?:\{(?:#[\w-]+\s+)?[\{\.=]?)?(?i:(webr|\{\.webr.+?\}|.+\-webr)(?:\}{1,2})?((\s+|:|,|\{|\?)[^`~]*)?$)</string>
        <key>name</key>
        <string>markup.fenced_code.block.markdown</string>
        <key>end</key>
        <string>(^|\G)(\2|\s{0,3})(\3)\s*$</string>
        <key>beginCaptures</key>
        <dict>
          <key>3</key>
          <dict>
            <key>name</key>
            <string>punctuation.definition.markdown</string>
          </dict>
          <key>4</key>
          <dict>
            <key>name</key>
            <string>fenced_code.block.language.markdown</string>
          </dict>
          <key>5</key>
          <dict>
            <key>name</key>
            <string>fenced_code.block.language.attributes.markdown</string>
          </dict>
        </dict>
        <key>endCaptures</key>
        <dict>
          <key>3</key>
          <dict>
            <key>name</key>
            <string>punctuation.definition.markdown</string>
          </dict>
        </dict>
        <key>patterns</key>
        <array>
          <dict>
            <key>begin</key>
            <string>(^|\G)(\s*)(.*)</string>
            <key>while</key>
            <string>(^|\G)(?!\s*([`~]{3,})\s*$)</string>
            <key>contentName</key>
            <string>meta.embedded.block.webr</string>
            <key>patterns</key>
            <array>
              <dict>
                <key>include</key>
                <string>source.r</string>
              </dict>
            </array>
          </dict>
        </array>
      </dict>
EOF
    
    # Insert webr block definition after R block
    head -n "$R_BLOCK_END" "$GRAMMAR_FILE" > "$GRAMMAR_FILE.tmp"
    cat "$TEMP_WEBR" >> "$GRAMMAR_FILE.tmp"
    tail -n +$((R_BLOCK_END + 1)) "$GRAMMAR_FILE" >> "$GRAMMAR_FILE.tmp"
    mv "$GRAMMAR_FILE.tmp" "$GRAMMAR_FILE"
    rm "$TEMP_WEBR"
    
    # Add webr to fenced_code_block patterns array
    # Find the line with #fenced_code_block_r in the patterns array
    PATTERN_START=$(grep -n "<string>#fenced_code_block_r</string>" "$GRAMMAR_FILE" | head -1 | cut -d: -f1)
    
    if [ -z "$PATTERN_START" ]; then
        echo -e "${RED}  Error: Could not find R block reference in patterns array${NC}"
        return 1
    fi
    
    # Find the closing </dict> after the pattern start (should be 2 lines down)
    PATTERN_END=$(tail -n +$PATTERN_START "$GRAMMAR_FILE" | grep -n '^          </dict>$' | head -1 | cut -d: -f1)
    PATTERN_END=$((PATTERN_START + PATTERN_END - 1))

    TEMP_PATTERN="$GRAMMAR_FILE.pattern_block"
    cat > "$TEMP_PATTERN" <<'EOF'
          <dict>
            <key>include</key>
            <string>#fenced_code_block_webr</string>
          </dict>
EOF
    
    head -n "$PATTERN_END" "$GRAMMAR_FILE" > "$GRAMMAR_FILE.tmp"
    cat "$TEMP_PATTERN" >> "$GRAMMAR_FILE.tmp"
    tail -n +$((PATTERN_END + 1)) "$GRAMMAR_FILE" >> "$GRAMMAR_FILE.tmp"
    mv "$GRAMMAR_FILE.tmp" "$GRAMMAR_FILE"
    rm "$TEMP_PATTERN"
    
    echo "  Patching package.json..."
    
    # Add webr to embeddedLanguages using awk (more portable)
    awk '
    /"meta\.embedded\.block\.r": "r",/ {
        print
        print "\t\t\t\t\t\"meta.embedded.block.webr\": \"r\","
        next
    }
    { print }
    ' "$PACKAGE_FILE" > "$PACKAGE_FILE.tmp" && mv "$PACKAGE_FILE.tmp" "$PACKAGE_FILE"
    
    echo -e "${GREEN}  ✓ Patching complete for $IDE!${NC}"
    echo "  Backups created:"
    echo "    $GRAMMAR_FILE.backup"
    echo "    $PACKAGE_FILE.backup"
    echo
}

# Patch all found extensions
for ext_info in "${QUARTO_EXTENSIONS[@]}"; do
    IDE="${ext_info%%:*}"
    EXT_PATH="${ext_info#*:}"
    patch_extension "$IDE" "$EXT_PATH"
done

echo -e "${GREEN}All extensions processed!${NC}"
echo -e "${YELLOW}Please restart VS Code and/or Positron for changes to take effect.${NC}"
