# Contributing to Claude Desktop Manager

Thank you for your interest in contributing to Claude Desktop Manager!

## License Headers

All source files must include the appropriate license header. A template for this header can be found in `.github/LICENSE-HEADER.txt`.

For shell scripts, add the header at the top of the file after the shebang line:

```bash
#!/bin/bash
#
# Claude Desktop Manager
# Copyright (c) 2025 Alexander Warth
# Portions Copyright (c) 2024 aaddrick (claude-desktop-debian)
# Portions Copyright (c) 2024 emsi (claude-desktop)
# Portions Copyright (c) 2024 Claude Desktop Linux Maintainers
# Portions Copyright (c) 2019 k3d3
#
# This software is derived from the following projects:
# - https://github.com/aaddrick/claude-desktop-debian (original)
# - https://github.com/emsi/claude-desktop (fork)
#
# Licensed under either of
#  - Apache License, Version 2.0
#  - MIT license
# at your option.
```

For JavaScript/TypeScript files:

```javascript
/*
 * Claude Desktop Manager
 * Copyright (c) 2025 Alexander Warth
 * Portions Copyright (c) 2024 aaddrick (claude-desktop-debian)
 * Portions Copyright (c) 2024 emsi (claude-desktop)
 * Portions Copyright (c) 2024 Claude Desktop Linux Maintainers
 * Portions Copyright (c) 2019 k3d3
 *
 * This software is derived from the following projects:
 * - https://github.com/aaddrick/claude-desktop-debian (original)
 * - https://github.com/emsi/claude-desktop (fork)
 *
 * Licensed under either of
 *  - Apache License, Version 2.0
 *  - MIT license
 * at your option.
 */
```

## Dual Licensing

This project is dual-licensed under both MIT and Apache 2.0 licenses. Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this work by you shall be dual-licensed as above, without any additional terms or conditions.

## Code Style

- **Shell Script Best Practices**:
  - Use shellcheck-compliant code
  - Include proper shebang lines and file permissions
  - Implement robust error handling with appropriate exit codes
  - Use functions for code organization
  - Quote all variables unless word splitting is intended
  - Use meaningful variable and function names

- **JavaScript Best Practices**:
  - Follow modern ES6+ syntax where appropriate
  - Use clear, descriptive variable and function names
  - Include appropriate comments for complex sections
  - Handle DOM interactions defensively
  - Implement proper error catching

## Pull Request Process

1. Ensure your code includes the proper license headers
2. Update the README.md if necessary with details of changes
3. Increase version numbers in any examples files and the README.md to the new version that this Pull Request would represent
4. Submit your pull request

## Attribution

Always maintain proper attribution to the original projects:
- [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) (original)
- [emsi/claude-desktop](https://github.com/emsi/claude-desktop) (fork)
