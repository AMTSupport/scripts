# Azure Functions Scripts

This folder contains PowerShell scripts that are deployed as Azure Functions.
Each script represents a separate Azure Function that can be triggered and executed independently.

## Prerequisites

Before deploying and running these scripts, make sure you have the following prerequisites:

- [Azure subscription](https://azure.microsoft.com/free/)
- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell)

## Getting Started

To get started with these scripts, follow these steps:

1. Clone or download this repository to your local machine.
2. Open a terminal or PowerShell window and navigate to the root folder of this repository.
3. Install the necessary dependencies by running the following command:
    ```shell
    npm install
    ```
4. Configure your Azure credentials by running the following command and following the prompts:
    ```shell
    az login
    ```
5. Deploy the Azure Functions by running the following command:
    ```shell
    func azure functionapp publish <function-app-name>
    ```
    Replace `<function-app-name>` with the name of your Azure Function App.
6. Once the deployment is complete, you can trigger and execute the individual functions using their respective triggers.

## Folder Structure

The folder structure of this repository is as follows:
