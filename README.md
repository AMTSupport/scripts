# AMTSupport Scripts Repository

## Introduction

Welcome to the AMTSupport's scripts repository. This repository contains a collection of scripts designed to support various tasks and operations. These scripts are maintained and regularly updated by our team to ensure reliability and efficiency.

---

## Table of Contents

- [AMTSupport Scripts Repository](#amtsupport-scripts-repository)
  - [Introduction](#introduction)
  - [Table of Contents](#table-of-contents)
  - [Folder Structure](#folder-structure)
  - [Getting Started](#getting-started)
  - [Maintainers](#maintainers)
  - [License](#license)

---

## Folder Structure

- [**compiled**](./compiled/): Contains compiled versions of the scripts for usage outside of the repository.
- [**src**](./src): Contains the source code for all the scripts.
  - [**Compiler**](./src/Compiler): Contains the C# Compiler which is used to compile the scripts.
  - [**Common**](./src/common): Contains common utility modules.
  - [**External**](./src/external): Contains scripts that are from external sources which are patched or modified.
  - [**Automation/Registry**](./src/automation/registry): Contains generated registry scripts.
- [**tests**](./tests): Test scripts and test data for ensuring script reliability.
- [**utils**](./utils): Utility scripts that assist in development and maintenance.

---

## Getting Started

### One-Liner usage

If you know which script you are trying to run, you can use this one-liner to download and execute it directly from the repository:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/AMTSupport/scripts/master/src/compiled/<script>.ps1'))
```

---

## Maintainers

- [**James Draycott**](https://github.com/DaRacci) - *Initial Work and Maintenance*

---

## License

This project is licensed under GPL3 - see the [LICENSE](LICENSE) file for details.

---
