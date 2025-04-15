#!/usr/bin/env bash

# This script is used to clean up compiled files that are no longer needed.
# It checks for files in the 'compiled' directory that do not have a corresponding
# source file in the 'src' directory. If such files are found, they are deleted.

DRY_RUN=${DRY_RUN:-false}
find compiled -name '*.ps1' -type f -exec sh -c '
    no_prefix=${1#compiled/}
    if [ ! -f "src/${no_prefix}" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: Would delete $1"
        else
            echo "Deleting $1"
            rm "$1"
        fi
    fi
' sh {} \;
