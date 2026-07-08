# svg-to-omnigraffle — convert Mermaid SVG exports for OmniGraffle import without loosing labels

# The CommandLineTools SwiftPM install on this machine is corrupted (stale
# PackageDescription from Feb 2024); build with the full Xcode toolchain.
export DEVELOPER_DIR := "/Applications/Xcode.app/Contents/Developer"

version := `cat .version | tr -d '\n'`

prefix := "/usr/local"

# List available recipes
default:
    @just --list

# Verify the Swift toolchain works; point out fixes if it doesn't
setup:
    @swift --version || { echo "Swift not found — install Xcode from the App Store"; exit 1; }
    @[ -d "$DEVELOPER_DIR" ] || { echo "Xcode not found at $DEVELOPER_DIR — install it, or fix CommandLineTools with: sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"; exit 1; }
    @echo "Toolchain OK: $(swift --version 2>&1 | head -1)"

lint-markdown:
    /usr/bin/find . -type f -name '*.md' | xargs mdformat --wrap no 

# Build debug binary
build:
    swift build

# Build optimized release binary
release:
    swift build -c release

# Run the test suite
test:
    swift test

# Convert an SVG: just run Resources/html-labels.svg [args...]
run +args:
    swift run svg2og {{args}}

# Install release binary into {{prefix}}/bin (may need sudo)
install: release
    install -d "{{prefix}}/bin"
    install .build/release/svg2og "{{prefix}}/bin/svg2og"
    @echo "Installed {{prefix}}/bin/svg2og"

# Remove build artifacts
clean:
    swift package clean
    rm -rf .build
    /usr/bin/find . -name '.DS_Store' -delete

# Tag v{{ version }}, publish the GH release, & refresh the Homebrew tap.
release:
    git fetch --tags
    git tag -f "v{{ version }}"
    git push -f --tags
    gh release delete -y "v{{ version }}" --repo {{ repo }} 2>/dev/null || true
    gh release create "v{{ version }}" --generate-notes --repo {{ repo }}
