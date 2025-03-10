#!/bin/sh

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2025, Timo Pallach (timo@pallach.de).

#######################################################################
# SSH Config Analyzer - Code Quality Check Script
#
# This script runs various static analysis and code quality tools on the
# codebase to ensure it meets quality standards, follows consistent
# formatting, and is free from security issues.
#
# The script performs the following checks:
# 1. Secret/credential leaks using gitleaks
# 2. Shell script formatting using shfmt
# 3. Shell script static analysis using shellcheck
#
# Usage:
#   ./check_sources.sh
#
# Exit Codes:
#   0: All checks passed successfully
#   1: Gitleaks found potential credential leaks
#   2: Shell script formatting issues found
#   3: Shell script static analysis issues found
#
# Requirements:
#   - gitleaks: For detecting credential leaks
#   - shfmt: For shell script formatting
#   - shellcheck: For shell script static analysis
#######################################################################

# Set script name for logging
# This extracts the script name from the path for consistent log formatting
script_name="$(basename "${0}")"

#######################################################################
# SECTION 1: Check for credential leaks using gitleaks
#######################################################################
# Gitleaks scans the repository for potential secrets, API keys,
# passwords, and other sensitive information that should not be
# committed to version control.
printf "%b %b INFO:  Run gitleaks:\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
pwd
if ! gitleaks dir --no-banner --verbose .; then
    printf "%b %b ERROR: ==>> FAILED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
    exit 1
fi
printf "%b %b INFO:  ==>> SUCCEDED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"

#######################################################################
# SECTION 2: Check shell script formatting using shfmt
#######################################################################
# shfmt formats shell scripts according to a consistent style.
# Options used:
#   --diff: Show diff instead of rewriting files
#   --posix: Enable POSIX compliance
#   --indent 4: Use 4 spaces for indentation
printf "%b %b INFO:  Run shfmt:\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
if ! shfmt --diff --posix --indent 4 ./*.sh; then
    printf "%b %b ERROR: ==>> FAILED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
    exit 2
fi
printf "%b %b INFO:  ==>> SUCCEDED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"

#######################################################################
# SECTION 3: Run shell script static analysis using shell-check
#######################################################################
# The shell-check tool is a static analysis tool for shell scripts that identifies
# potential bugs, stylistic issues, and unsafe practices.
# Options used:
#   --norc: Don't look for or read a config file
#   --shell=sh: Specify shell dialect (POSIX shell)
printf "%b %b INFO:  Run shellcheck:\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
if ! shellcheck --norc --shell=sh ./*.sh; then
    printf "%b %b ERROR: ==>> FAILED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"
    exit 3
fi
printf "%b %b INFO:  ==>> SUCCEDED\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${script_name}"

# Exit with success code if all checks passed
exit 0
