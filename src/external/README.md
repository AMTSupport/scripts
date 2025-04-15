# External Scripts

This directory contains scripts which are our own, but have been pulled from their sources and are integrated into the project.
These scripts are automatically updated by the `Update.ps1` script.

______________________________________________________________________

## Creating a new Patch

### Automatically

To create a new patch, you can run `Update.ps1` with the `-CreatePatches` parameter.
This will remove the `#!ignore` line from the script and make it ready for your changes to be applied.

When the script prompts you to make your changes you are free to do so, once you are done you can press `Enter` to continue.

This will then prompt you to supply a name to make a patch for each file you have modified, these patches are then automatically saved and applied to the definitions.

### Manually

To create a new patch, you should edit a raw version of the script.
This can be done by removing the first line of the script with `#!ignore`, then save and stage the file with only this modification.

Once you have done this, to create a patch file for your changes run

```sh
git diff {file} > {patchname}.patch
```

You will then need to add this to the scripts jsonc source file.
You'll need to add a relative path to the patch file in the `patches` array of the script definition.

Once completed, you should restore the file to its original state by running

```sh
git restore {file}
```

This will remove the changes you made to the script and restore it to its original state.

You should then apply the patch to ensure the patch is valid by running

```sh
git apply {patchname}.patch
```
