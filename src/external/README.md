# External Scripts

This directory contains scripts which are our own, but have been pulled from their sources and are integrated into the project.
These scripts are automatically updated by the `update_external.sh` script.

## Scripts

    - `update_external.sh`
        This script maintains the external scripts in this directory, this handles patching, updating and cleaning up the scripts.

## Creating a new Patch

When creating the patch, you should remove the `#!ignore` and hash from the first line if it was downloaded using the `update_external.sh` script.
