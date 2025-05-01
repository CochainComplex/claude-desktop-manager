#!/bin/bash
# validate-paths.sh - Verify path consistency in Claude Desktop Manager
# Run this script to check for path inconsistencies in the codebase

set -e

echo "===== Path Consistency Validator ====="
echo "Checking for path inconsistencies in the codebase..."

# Find the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Define the correct sandbox path
CORRECT_SANDBOX_PATH="/home/claude"

# Initialize counters
WARNINGS=0
ERRORS=0

# Function to check files for inconsistent paths
check_files() {
    local pattern="$1"
    local file_pattern="$2"
    local message="$3"
    local severity="$4" # "warning" or "error"
    
    echo "Checking for $message..."
    
    # Find files matching the pattern that contain the search pattern
    local matching_files=$(find "${PROJECT_ROOT}" -type f -name "${file_pattern}" -not -path "*/\.*" | xargs grep -l "${pattern}" 2>/dev/null || true)
    
    if [ -n "$matching_files" ]; then
        echo "Found potential ${severity}s:"
        echo "$matching_files" | while read -r file; do
            # Extract line numbers with context
            grep -n --color=always -A 1 -B 1 "${pattern}" "$file" | sed "s|^|  $file:|"
            
            if [ "$severity" = "warning" ]; then
                WARNINGS=$((WARNINGS + 1))
            else
                ERRORS=$((ERRORS + 1))
            fi
        done
        echo ""
    else
        echo "✓ No ${severity}s found for this check"
        echo ""
    fi
}

# Check for potential $HOME usage in template files
check_files "\$HOME" "*.sh" "potentially inconsistent \$HOME usage in shell scripts" "warning"
check_files "\$HOME" "*.template" "potentially inconsistent \$HOME usage in templates" "warning"
check_files "\$HOME" "*.js" "potentially inconsistent \$HOME usage in JavaScript files" "warning"
check_files "\$HOME" "*.json" "potentially inconsistent \$HOME usage in JSON files" "warning"

# Check for incorrect sandbox paths
check_files "home/[^c][^l][^a][^u][^d][^e]" "*.sh" "incorrect sandbox home paths" "error"
check_files "home/[^c][^l][^a][^u][^d][^e]" "*.template" "incorrect sandbox home paths" "error"
check_files "home/[^c][^l][^a][^u][^d][^e]" "*.json" "incorrect sandbox home paths" "error"

# Check for missing path conventions comment
MISSING_COMMENT=$(find "${PROJECT_ROOT}/lib" -name "*.sh" | xargs grep -L "path.*sandbox" 2>/dev/null || true)
if [ -n "$MISSING_COMMENT" ]; then
    echo "Files missing path convention documentation:"
    echo "$MISSING_COMMENT" | while read -r file; do
        echo "  $file"
        WARNINGS=$((WARNINGS + 1))
    done
    echo ""
else
    echo "✓ All library files have path convention documentation"
    echo ""
fi

# Summary
echo "===== Path Validation Summary ====="
echo "Warnings: $WARNINGS"
echo "Errors: $ERRORS"

if [ $ERRORS -gt 0 ]; then
    echo "❌ Path validation failed with $ERRORS errors"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo "⚠️ Path validation completed with $WARNINGS warnings"
    exit 0
else
    echo "✅ Path validation passed with no issues"
    exit 0
fi
