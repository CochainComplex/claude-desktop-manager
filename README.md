# Claude Desktop Manager

A utility for creating and managing multiple isolated instances of Claude Desktop on Linux systems.

## Overview

Claude Desktop Manager (`cmgr`) enables users to maintain different Claude Desktop environments with separate settings, conversations, and MCP configurations. Each instance is sandboxed using bubblewrap to ensure complete isolation.

This project extends [emsi/claude-desktop](https://github.com/emsi/claude-desktop), an unofficial Linux port of Anthropic's Claude Desktop application.

## Features

- Create isolated Claude Desktop instances using bubblewrap sandboxing
- Generate and manage quick-access aliases for each instance
- Launch, list, and remove instances with simple commands
- Support auto-approval of MCP (Machine-Computer Protocol) tools
- Configure custom MCP servers for different instances
- Generate desktop shortcuts for system integration

## Requirements

- Debian-based Linux system (Ubuntu, Pop!_OS, etc.)
- claude-desktop (base application)
- bubblewrap (for sandboxing)
- electron (for application runtime)

## Installation

```bash
# Installation instructions will be provided soon
```

## Usage

```bash
# Create a new Claude Desktop instance
cmgr create my-instance

# Launch an instance
cmgr launch my-instance

# List all instances
cmgr list

# Remove an instance
cmgr remove my-instance
```

## MCP Tool Integration

Claude Desktop Manager supports custom MCP tool configurations:

- Auto-approval of trusted tools
- Custom trusted tool lists per instance
- Support for custom MCP server configurations

## License

Claude Desktop Manager is dual-licensed under both the MIT license and the Apache License (Version 2.0).

This means you can choose either license, depending on which better suits your needs:

- **MIT License**: A permissive license with very few restrictions
- **Apache License 2.0**: A permissive license with patent grants and contribution terms

See [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE) for the full license texts.

### Copyright

Copyright (c) 2025 Alexander Warth - Claude Desktop Manager  
Portions Copyright (c) 2024 aaddrick (claude-desktop-debian)  
Portions Copyright (c) 2024 emsi (claude-desktop)  
Portions Copyright (c) 2024 Claude Desktop Linux Maintainers  
Portions Copyright (c) 2019 k3d3

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this work by you shall be dual-licensed as above, without any additional terms or conditions.

## Attribution

This project is derived from two key sources:

1. The original [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) project, which created the first Debian/Ubuntu build scripts for Claude Desktop

2. The [emsi/claude-desktop](https://github.com/emsi/claude-desktop) fork, which expanded on the original project with additional features

Both projects are unofficial Linux ports of Anthropic's Claude Desktop application and are dual-licensed under MIT and Apache 2.0.

## Disclaimer

This is an unofficial utility not affiliated with Anthropic. All code focuses on managing the Claude Desktop application, not modifying it.
