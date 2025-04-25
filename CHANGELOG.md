# Changelog

## 2025-04-25 (v0.2.0)
### Fixed
- Added `--disable-gpu` flag to prevent hardware acceleration issues (fixes "libva error" message)
- Added preload script to increase EventEmitter max listeners limit (addresses "MaxListenersExceededWarning")

## 2025-04-24 (v0.1.0)
### Fixed
- Updated the installer.sh script to correctly use install-claude-desktop.sh from the emsi/claude-desktop repository instead of a non-existent build.sh script
- Added more robust package detection to handle variations in package naming
- Improved version extraction with fallback options
- Updated AppImage handling to work with the .deb format when necessary

### Added
- Better error handling for the installation process
- Additional logging for troubleshooting build issues
- Support for continuing even when version extraction fails
- Implemented improved MCP auto-approval script from the original emsi/claude-desktop repository, with support for a trusted tools list and cooldown mechanism

### Changed
- Modified the build process to avoid installing Claude Desktop globally during the build phase
- Enhanced sandbox script to ensure proper isolation between instances
