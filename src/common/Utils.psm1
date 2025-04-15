Using module .\Logging.psm1
Using module .\Scope.psm1
Using module .\Exit.psm1

<#
.SYNOPSIS
    Get the value of an environment variable or save it if it does not exist.
.DESCRIPTION
    This function will get the value of an environment variable or save it if it does not exist.
    It will also validate the value if a test script block is provided.
    If the value does not exist, it will prompt the user for the value and save it as an environment variable,
    The value will be saved as a process environment variable.
.PARAMETER VariableName
    The name of the environment variable to get or save.
.PARAMETER LazyValue
    The script block to execute if the environment variable does not exist.
.PARAMETER Validate
    The script block to test the value of the environment variable or the lazy value.
.EXAMPLE
    Get-VarOrSave `
        -VariableName 'HUDU_KEY' `
        -LazyValue { Get-UserInput -Title 'Hudu API Key' -Question 'Please enter your Hudu API Key' };
.OUTPUTS
    System.String if the environment variable exists or the lazy value if it does not.
    null if the value didn't pass the validation.
#>
function Get-VarOrSave {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullorEmpty()]
        [String]$VariableName,

        [Parameter(Mandatory)]
        [ScriptBlock]$LazyValue,

        [Parameter()]
        [ScriptBlock]$Validate
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        $Local:EnvValue = [Environment]::GetEnvironmentVariable($VariableName);

        if ($Local:EnvValue) {
            if ($Validate) {
                try {
                    if ($Validate.InvokeReturnAsIs($Local:EnvValue)) {
                        Invoke-Debug "Validated environment variable ${VariableName}: $Local:EnvValue";
                        return $Local:EnvValue;
                    } else {
                        Invoke-Error "Failed to validate environment variable ${VariableName}: $Local:EnvValue";
                        [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
                    };
                } catch {
                    Invoke-Error "
                    Failed to validate environment variable ${VariableName}: $Local:EnvValue.
                    Due to reason ${$_.Exception.Message}".Trim();

                    [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
                }
            } else {
                Invoke-Debug "Found environment variable $VariableName with value $Local:EnvValue";
                return $Local:EnvValue;
            }
        }

        while ($True) {
            try {
                $Local:Value = $LazyValue.InvokeReturnAsIs();

                if ($Validate) {
                    if ($Validate.InvokeReturnAsIs($Local:Value)) {
                        Invoke-Debug "Validated lazy value for environment variable ${VariableName}: $Local:Value";
                        break;
                    } else {
                        Invoke-Error "Failed to validate lazy value for environment variable ${VariableName}: $Local:Value";
                    }
                } else {
                    break;
                }
            } catch {
                Invoke-Error "Encountered an error while evalutating LazyValue for ${VariableName}.";
                return $null;
            }
        };

        # TODO - Support saving in a more permanent location.
        [Environment]::SetEnvironmentVariable($VariableName, $Local:Value, 'Process');
        return $Local:Value;
    }
}

#region AST Helpers

<#
.DESCRIPTION
    Try to transform the input object into an AST Object.
#>
function Get-Ast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The input object to transform into an AST object.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject
    )

    process {
        $Local:Ast = switch ($InputObject) {
            { $_ -is [String] } {
                if (Test-Path -LiteralPath $_) {
                    $Local:Path = Resolve-Path -Path $_;
                    [System.Management.Automation.Language.Parser]::ParseFile($Local:Path.ProviderPath, [ref]$null, [ref]$null)
                } else {
                    [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
                }

                break
            }
            { $_ -is [System.Management.Automation.FunctionInfo] -or $_ -is [System.Management.Automation.ExternalScriptInfo] } {
                $InputObject.ScriptBlock.Ast
                break
            }
            { $_ -is [ScriptBlock] } {
                $_.Ast
                break
            }
            { $_ -is [System.Management.Automation.Language.Ast] } {
                $_
                break
            } Default {
                Invoke-Warn -Message "InputObject type not recognised: $($InputObject.gettype())";
                $null
            }
        }

        return $Local:Ast;
    }
}

<#
.SYNOPSIS
    Get the return type of an AST Object.
.OUTPUTS
    System.Reflection.TypeInfo[]
    The return types of the AST object.

    null
    If the AST object does not have any return statements.
#>
function Get-ReturnType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject
    )

    process {
        $Local:Ast = Get-Ast -InputObject $InputObject;
        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);

        if ($Local:AllReturnStatements.Count -eq 0) {
            Invoke-Debug -Message 'No return statements found in the AST Object.';
            return $null;
        }

        [System.Reflection.TypeInfo[]]$Local:ReturnTypes = @();
        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
            # Check if the return statement has any values or just an empty return statement.
            if ($Local:ReturnStatement.Pipeline.PipelineElements.Count -eq 0) {
                Invoke-Debug -Message 'No pipeline elements found in the return statement.';
                return $null;
            }

            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;

            # TODO - Better handling of the variable path.
            if ($Local:Expression.VariablePath) {
                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;

                if ($Local:VariableName -eq 'null') {
                    $Local:ReturnTypes += [Void];
                    continue;
                }

                if ($Local:VariableName -eq 'true' -or $Local:VariableName -eq 'false') {
                    $Local:ReturnTypes += [Boolean];
                    continue;
                }

                # Try to resolve the variable and check its type.
                $Local:Variable = $PSCmdlet.GetVariableValue($Local:VariableName);
                if ($Local:Variable) {
                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
                    $Local:ReturnTypes += $Local:ReturnType;
                } else {
                    Invoke-Debug -Message "Could not resolve the variable: $Local:VariableName.";
                    continue
                }
            } else {
                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
                $Local:ReturnTypes += $Local:ReturnType;
            }
        }

        return $Local:ReturnTypes | Sort-Object -Unique;
    }
}

<#
.DESCRIPTION
    Validate that this ast object has a return type that matches teh expected type.

.EXAMPLE
    [Boolean]$Local:HasCorrectReturnType = Test-ReturnType -Ast:$Ast -ValidTypes:'String','ScriptBlock';
#>
function Test-ReturnType {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject,

        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
        [ValidateNotNullOrEmpty()]
        [System.Reflection.TypeInfo[]]$ValidTypes,

        [Parameter(HelpMessage = 'Allow the return type to be null.')]
        [Switch]$AllowNull
    )

    process {
        $Local:Ast = Get-Ast -InputObject $InputObject;
        $Local:ReturnTypes = Get-ReturnType -InputObject $InputObject;

        if ($null -eq $Local:ReturnTypes) {
            Invoke-Debug -Message 'No return types found in the AST Object.';
            return $False;
        }

        foreach ($Local:ReturnType in $Local:ReturnTypes) {
            if ($ValidTypes -contains $Local:ReturnType) {
                continue;
            } elseif ($AllowNull -and $Local:ReturnType -eq [Void]) {
                continue;
            } else {
                Invoke-Warn -Message "The return type of the AST object is not valid. Expected: $($ValidTypes -join ', '); Actual: $($Local:ReturnType.Name)";
                return $False;
            }
        }

        return $True;

        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);

        if ($Local:AllReturnStatements.Count -eq 0) {
            Invoke-Debug -Message 'No return statements found in the script block.';
            return $False;
        }

        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
            # Check if the return statement has any values or just an empty return statement.
            if ($Local:ReturnStatement.Pipeline.PipelineElements.Count -eq 0) {
                Invoke-Debug -Message 'No pipeline elements found in the return statement.';
                return $False;
            }

            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;

            # TODO - Better handling of the variable path.
            if ($Local:Expression.VariablePath) {
                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;

                # Try to resolve the variable and check its type.
                $Local:Variable = Get-Variable -Name:$Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;

                if ($Local:Variable) {
                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
                    if ($ValidTypes -contains $Local:ReturnType) {
                        continue;
                    }
                } else {
                    Invoke-Debug -Message "Could not resolve the variable: $Local:VariableName.";
                    continue
                }
            } else {
                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
                [String]$Local:TypeName = $Local:ReturnType.Name;

                Invoke-Debug "Return type: $Local:TypeName";

                if ($ValidTypes -contains $Local:TypeName -or ($AllowNull -and $Local:Expression.Extent.Text -eq '$null' -and $Local:ReturnType.Name -eq 'Object')) {
                    continue;
                }
            }

            $Local:Region = $Local:Expression.Extent;
            Invoke-Warn -Message @"
The return type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName.
At: $($Local:Region.StartLineNumber):$($Local:Region.StartColumnNumber) - $($Local:Region.EndLineNumber):$($Local:Region.EndColumnNumber)
Text: $($Local:Region.Text)
"@;

            return $False;
        }

        return $True;
    }
}

<#
.DESCRIPTION
    Validate the parameters of a script block.
#>
function Test-Parameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject,

        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
        [ValidateNotNullOrEmpty()]
        [String[]]$ValidTypes
    )

    process {
        $Local:Ast = Get-Ast -InputObject $InputObject;
        $Local:AllParamStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true);
        foreach ($Local:ParamStatement in $Local:AllParamStatements) {
            [System.Management.Automation.Language.ParameterAst]$Local:Param = $Local:ParamStatement;
            [String]$Local:TypeName = $Local:Param.StaticType.Name;

            if ($ValidTypes -contains $Local:TypeName) {
                continue;
            }

            Invoke-Warn -Message "The parameter type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName";
            return $False;
        }

        return $True;
    }
}
#endregion

function Install-ModuleFromGitHub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$GitHubRepo,

        [Parameter(Mandatory)]
        [String]$Branch,

        [ValidateSet('CurrentUser', 'AllUsers')]
        [String]$Scope = 'CurrentUser'
    )

    process {
        Invoke-Verbose ("[$(Get-Date)] Retrieving {0} {1}" -f $GitHubRepo, $Branch);

        [String]$Local:ZipballUrl = "https://api.github.com/repos/$GithubRepo/zipball/$Branch";
        [String]$Local:ModuleName = $GitHubRepo.split('/')[-1]

        [String]$Local:TempDir = [System.IO.Path]::GetTempPath();
        [String]$Local:OutFile = Join-Path -Path $Local:TempDir -ChildPath "$($ModuleName).zip";

        if (-not ($IsLinux -or $IsMacOS)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
        }

        Invoke-Verbose "Downloading $Local:ModuleName from $Local:ZipballUrl to $Local:OutFile";
        try {
            $ErrorActionPreference = 'Stop';

            Invoke-RestMethod $Local:ZipballUrl -OutFile $Local:OutFile;
        } catch {
            Invoke-Error "Failed to download $Local:ModuleName from $Local:ZipballUrl to $Local:OutFile";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        if (-not ([System.Environment]::OSVersion.Platform -eq 'Unix')) {
            Unblock-File $Local:OutFile;
        }

        [String]$Local:FileHash = (Get-FileHash -Path $Local:OutFile).hash;
        [String]$Local:ExtractDir = Join-Path -Path $Local:TempDir -ChildPath $Local:FileHash;

        Invoke-Verbose "Extracting $Local:OutFile to $Local:ExtractDir";
        try {
            Expand-Archive -Path $Local:OutFile -DestinationPath $Local:ExtractDir -Force;
        } catch {
            Invoke-Error "Failed to extract $Local:OutFile to $Local:ExtractDir";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        [System.IO.DirectoryInfo]$Local:UnzippedArchive = Get-ChildItem -Path $Local:ExtractDir -Directory | Select-Object -First 1;

        switch ($Scope) {
            'CurrentUser' {
                [String]$Local:PSModulePath = ($PSGetPath).CurrentUserModules;
                break;
            }
            'AllUsers' {
                [String]$Local:PSModulePath = ($PSGetPath).AllUsersModules;
                break;
            }
        }

        if ([System.Environment]::OSVersion.Platform -eq 'Unix') {
            [System.IO.FileInfo[]]$Local:ManifestFiles = Get-ChildItem (Join-Path -Path $Local:UnzippedArchive -ChildPath *) -File | Where-Object { $_.Name -like '*.psd1' };
        } else {
            [System.IO.FileInfo[]]$Local:ManifestFiles = Get-ChildItem -Path $Local:UnzippedArchive.FullName -File | Where-Object { $_.Name -like '*.psd1' };
        }

        if ($Local:ManifestFiles.Count -eq 0) {
            Invoke-Error "No manifest file found in $($Local:UnzippedArchive.FullName)";
            Invoke-FailedExit -ExitCode 9999;
        } elseif ($Local:ManifestFiles.Count -gt 1) {
            Invoke-Debug "Multiple manifest files found in $($Local:UnzippedArchive.FullName)";
            Invoke-Debug "Manifest files: $($Local:ManifestFiles.FullName -join ', ')";

            [System.IO.FileInfo]$Local:ManifestFile = $Local:ManifestFiles | Where-Object { $_.Name -like "$Local:ModuleName*.psd1" } | Select-Object -First 1;
        } else {
            [System.IO.FileInfo]$Local:ManifestFile = $Local:ManifestFiles | Select-Object -First 1;
            Invoke-Debug "Manifest file: $($Local:ManifestFile.FullName)";
        }

        $Local:Manifest = Test-ModuleManifest -Path $Local:ManifestFile.FullName;
        [String]$Local:ModuleName = $Local:Manifest.Name;
        [String]$Local:ModuleVersion = $Local:Manifest.Version;

        [String]$Local:SourcePath = $Local:ManifestFile.DirectoryName;
        [String]$Local:TargetPath = (Join-Path -Path $Local:PSModulePath -ChildPath (Join-Path -Path $Local:ModuleName -ChildPath $Local:ModuleVersion));
        New-Item -ItemType directory -Path $Local:TargetPath -Force | Out-Null;

        Invoke-Debug "Copying $Local:SourcePath to $Local:TargetPath";

        if ([System.Environment]::OSVersion.Platform -eq 'Unix') {
            Copy-Item "$(Join-Path -Path $Local:UnzippedArchive -ChildPath *)" $Local:TargetPath -Force -Recurse | Out-Null;
        } else {
            Copy-Item "$Local:SourcePath\*" $Local:TargetPath -Force -Recurse | Out-Null;
        }

        return $Local:ModuleName;
    }
}

function Test-NetworkConnection {
    (Get-NetConnectionProfile | Where-Object {
        $Local:HasIPv4 = $_.IPv4Connectivity -eq 'Internet';
        $Local:HasIPv6 = $_.IPv6Connectivity -eq 'Internet';

        $Local:HasIPv4 -or $Local:HasIPv6
    } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;
}

#region Async Helpers
<#
.SYNOPSIS
    Waits for a task to complete.

.DESCRIPTION
    This function will wait for a task to complete before continuing.
    This is useful for waiting for a task to complete before continuing with the script.

.EXAMPLE
    Wait for a task to complete.
    ```
    $Task = async {
        Start-Sleep -Seconds 5;
    };

    # Do something else while waiting for the task to complete.

    # Wait for the task to complete before continuing.
    Wait-Task -Task $Task;

    # Do something after the task has completed.
    ```

.EXAMPLE
    Wait for multiple tasks to complete.
    ```
    $Tasks = @(
        async {
            Start-Sleep -Seconds 5;
        },
        async {
            Start-Sleep -Seconds 10;
        }
    );

    # Do something else while waiting for the tasks to complete.

    # Wait for the tasks to complete before continuing.
    Wait-Task -Task $Tasks;

    # Do something after the tasks have completed.
    ```

.EXAMPLE
    Wait for a task to complete using the alias.
    ```
    $Task = async {
        Start-Sleep -Seconds 5;
    };

    # Do something else while waiting for the task to complete.

    # Wait for the task to complete before continuing.
    await $Task;

    # Do something after the task has completed.
    ```

.EXAMPLE
    Wait for the task using the pipeline.
    ```
    $Task = async {
        Start-Sleep -Seconds 5;
    };

    # Do something else while waiting for the task to complete.

    # Wait for the task to complete before continuing.
    $Task | await;

    # Do something after the task has completed.
    ```

.EXAMPLE
    Wait for the task to complete and return the task object.
    ```
    $Task = async {
        Start-Sleep -Seconds 5;

        return 'Task completed';
    };

    # Do something else while waiting for the task to complete.

    # Wait for the task to complete before continuing.
    $Result = await $Task;

    # Do something with the result of the task.
    ```

.PARAMETER Task
    The task to wait for.

.PARAMETER PassThru
    If the task object should be returned after the task has completed.

.INPUTS
    A task object.
    An array of task objects.

.OUTPUTS
    The result of the task.

.EXTERNALHELP
    https://amtsupport.github.io/scripts/docs/modules/Utils/Wait-Task
#>
function Wait-Task {
    [CmdletBinding()]
    [Alias('await')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$Run,

        [Switch]$PassThru
    )

    Begin {
        $Running = @{};
        $Finished = { $_.IsCompleted -or ($_.JobStateInfo.State -gt 1 -and $_.JobStateInfo.State -ne 6 -and $_.JobStateInfo.State -ne 8) };
        $Handle = { $_.AsyncWaitHandle };
    }

    Process {
        if (-not ($Run.Job -and $Run.Job.Id)) {
            throw [System.InvalidOperationException]::new('The Run object must contain a Job with an Id.');
        }

        $Running.Add($Run.Job.Id, $Run) | Out-Null;
    }

    End {
        filter Complete-Job {
            $Local:Out = $Running.Item($_.Id);
            $Running.Remove($_.Id) | Out-Null;

            if (-not ($Local:Out | Get-Member -Name 'Result' -MemberType NoteProperty)) {
                $Local:Result = if ($_.PWSH) {
                    try {
                        $_.PWSH.EndInvoke($_)
                    } catch {
                        #[System.Management.Automation.MethodInvocationException]
                        $_.Exception.InnerException
                    } finally {
                        $_.PWSH.Dispose()
                    }
                } elseif ($_.IsFaulted) {
                    #[System.AggregateException]
                    $_.Exception.InnerException
                } else {
                    $_.Result
                }

                $Local:Out | Add-Member -MemberType NoteProperty -Name Result -Value $Local:Result;
            }

            if ($PassThru) {
                $Local:Out
            } else {
                $Local:Out.Result
            }
        }

        while ($Running.Count -gt 0) {
            function Get-Jobs {
                param($Filter)

                $Running.Values | ForEach-Object { $_.Job } | Where-Object $Filter;
            }

            [System.Threading.WaitHandle]::WaitAny((Get-Jobs -Filter $Handle | ForEach-Object $Handle)) | Out-Null;
            (Get-Jobs -Filter $Finished) | Complete-Job;
        }
    }
}

<#
.SYNOPSIS
    Starts a task asynchronously.

.DESCRIPTION
    This function will start a task asynchronously.
    This is useful for running a task in the background while continuing with the script.

.EXAMPLE
    Start a task asynchronously.
    ```
    Start-AsyncTask {
        Start-Sleep -Seconds 5;
    }

    # Do something else while the task is running.
    ```

.EXAMPLE
    Start a task asynchronously using the alias.
    ```
    async {
        Start-Sleep -Seconds 5;
    }

    # Do something else while the task is running.
    ```

.PARAMETER ScriptBlock
    The script block to run asynchronously.

.INPUTS
    None

.OUTPUTS
    The task that was started.

.FUNCTIONALITY
    Asynchronous Programming

.EXTERNALHELP
    https://amtsupport.github.io/scripts/docs/modules/Utils/Start-AsyncTask
#>
function Start-AsyncTask {
    [CmdletBinding()]
    [Alias('async')]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock
    )

    # Start-Job -ScriptBlock $ScriptBlock;

    process {
        [PSCustomObject]$Local:Run = [PSCustomObject]@{
            Input = $_;
            Job   = $null;
            # Args = $ArgumentList;
            # Parameters = $Parameters;
        };

        [Powershell]$PWSH = [Powershell]::Create();
        $PWSH.AddScript($ScriptBlock) | Out-Null;

        if ($null -ne $Local:Run.Input) {
            $Local:Run.Job = $PWSH.BeginInvoke([System.Management.Automation.PSDataCollection[PSObject]]::new([PSObject[]]($Local:Run.Input)));
        } else {
            $Local:Run.Job = $PWSH.BeginInvoke();
        }

        $Run.Job | Add-Member -MemberType NoteProperty -Name pwsh -Value $PWSH -PassThru | Add-Member -MemberType NoteProperty -Name Id -Value $Run.Job.AsyncWaitHandle.Handle.ToString();

        return $Local:Run;
    }
}
#endregion

#region Lazy Loading
function Add-LazyProperty {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [Parameter(Mandatory, Position = 1)]
        [String]$Name,

        [Parameter(Mandatory, Position = 2)]
        [ScriptBlock]$Value,

        [Switch]$PassThru
    )

    process {
        $Local:LazyValue = {
            $Local:Result = & $Value;
            Add-Member -InputObject $this -MemberType NoteProperty -Name $Name -Value $Local:Result -Force;
            $Local:Result;
        }.GetNewClosure();

        Add-Member -InputObject:$InputObject -MemberType:ScriptProperty -Name:$Name -Value:$Local:LazyValue -PassThru:$Local:PassThru;
    }
}

function Set-LazyVariable {
    [CmdletBinding()]
    [Alias('lazy')]
    param (
        [Parameter(Mandatory, Position = 1)]
        [String]$Name,

        [Parameter(Mandatory, Position = 2)]
        [ScriptBlock]$Value,

        [Switch]$PassThru
    )

    process {
        $Local:LazyValue = {
            $Local:Result = & $Value;
            Set-Variable -Name $Local:Name -Value $Local:Result -Scope Local -Option ReadOnly;
            $Local:Result;
        }.GetNewClosure();

        Set-Variable -Name:$Name -Value:$Local:LazyValue -Scope:Local -Option:ReadOnly -PassThru:$PassThru;
    }
}
#endregion

function Test-IsRunningAsSystem {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -eq 'NT AUTHORITY\SYSTEM';
}

function Get-BlobCompatableHash {
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    begin {
        Enter-Scope;
        $Private:Algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5');
    }
    end { Exit-Scope; }

    process {
        [Byte[]]$Private:ByteStream = [System.IO.File]::ReadAllBytes($Path);
        [Byte[]]$Private:HashBytes = $Private:Algorithm.ComputeHash($Private:ByteStream);

        return [System.Convert]::ToBase64String($Private:HashBytes);
    }
}

function Get-FactorOf1MB {
    param(
        [Parameter(Mandatory)]
        [Int]$Size,

        [Parameter(Mandatory)]
        [Int]$Parts
    )

    if ($Size -lt 1MB -and $Parts -le 1) {
        return $Size;
    }

    $ChunkSize = $Size / $Parts;
    $NumberOfChunks = $ChunkSize % 1MB;
    return $ChunkSize + 1MB - $NumberOfChunks;
}

function Get-ETag {
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [Int]$ChunkSize
    )

    begin {
        Enter-Scope;
        $Algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5');
    }

    process {
        $Digest = @();
        $OpenFile = [System.IO.File]::OpenRead($Path);
        try {
            do {
                $Bytes = New-Object byte[] $ChunkSize;
                $OpenFile.Read($Bytes, 0, $ChunkSize) | Out-Null;
                $Digest += $Algorithm.ComputeHash($Bytes);
            } while ($OpenFile.Position -lt $OpenFile.Length);

            $StringBuilder = [System.Text.StringBuilder]::new();
            $StringBuilder.Append([System.Convert]::ToHexString($Algorithm.ComputeHash($Digest)));

            if ($Digest.Count -gt 1) {
                $StringBuilder.Append('-');
                $StringBuilder.Append($Digest.Count);
            }

            return $StringBuilder.ToString();
        } finally {
            $OpenFile.Close();
        }
    }

    end { Exit-Scope; }
}

function Get-PossiblePartSizes {
    param(
        [Parameter(Mandatory)]
        [Int]$Size,

        [Parameter(Mandatory)]
        [Int]$Parts
    )

    $PartSizes = @(
        8388608, # aws_cli/boto3
        15728640, # s3cmd
        (Get-FactorOf1MB -Size $FileSize -Parts $Parts)
    ) | Where-Object { $_ -lt $FileSize -and ($FileSize / $_) -le $Parts };

    if ($PartSizes.Count -eq 0) {
        return $Size;
    }

    return $PartSizes;
}

function Compare-FileHashToS3ETag {
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$ETag
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $FileSize = (Get-Item $Path).Length;
        $Parts = $ETag.Split('-');
        if ($Parts.Count -lt 2) { $Parts = 1; }
        else { $Parts = $Parts[1]; }

        $PossiblePartSizes = Get-PossiblePartSizes -Size $FileSize -Parts $Parts;
        if ($PossiblePartSizes.Count -eq 0) {
            Invoke-Debug "No possible part sizes found for $Path with ETag $ETag";
            return $False;
        }
        foreach ($PossiblePartSize in $PossiblePartSizes) {
            $Local:OurETag = Get-ETag -Path $Path -ChunkSize $PossiblePartSize;
            Invoke-Debug "Comparing Our ETag $Local:OurETag to S3 ETag $ETag";
            if ($Local:OurETag -eq $ETag) {
                return $True;
            }
        }
    }
}

function Get-BlobCompatableHash {
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    begin {
        Enter-Scope;
        $Private:Algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5');
    }
    end { Exit-Scope; }

    process {
        [Byte[]]$Private:ByteStream = [System.IO.File]::ReadAllBytes($Path);
        [Byte[]]$Private:HashBytes = $Private:Algorithm.ComputeHash($Private:ByteStream);

        return [System.Convert]::ToBase64String($Private:HashBytes);
    }
}

function Get-FactorOf1MB {
    param(
        [Parameter(Mandatory)]
        [Int]$Size,

        [Parameter(Mandatory)]
        [Int]$Parts
    )

    if ($Size -lt 1MB -and $Parts -le 1) {
        return $Size;
    }

    $ChunkSize = $Size / $Parts;
    $NumberOfChunks = $ChunkSize % 1MB;
    return $ChunkSize + 1MB - $NumberOfChunks;
}

function Get-ETag {
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [Int]$ChunkSize
    )

    begin {
        Enter-Scope;
        $Algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5');
    }

    process {
        $Digest = @();
        $OpenFile = [System.IO.File]::OpenRead($Path);
        try {
            do {
                $Bytes = New-Object byte[] $ChunkSize;
                $OpenFile.Read($Bytes, 0, $ChunkSize) | Out-Null;
                $Digest += $Algorithm.ComputeHash($Bytes);
            } while ($OpenFile.Position -lt $OpenFile.Length);

            $StringBuilder = [System.Text.StringBuilder]::new();
            $StringBuilder.Append([System.Convert]::ToHexString($Algorithm.ComputeHash($Digest)));

            if ($Digest.Count -gt 1) {
                $StringBuilder.Append('-');
                $StringBuilder.Append($Digest.Count);
            }

            return $StringBuilder.ToString();
        } finally {
            $OpenFile.Close();
        }
    }

    end { Exit-Scope; }
}

function Get-PossiblePartSizes {
    param(
        [Parameter(Mandatory)]
        [Int]$Size,

        [Parameter(Mandatory)]
        [Int]$Parts
    )

    $PartSizes = @(
        8388608, # aws_cli/boto3
        15728640, # s3cmd
        (Get-FactorOf1MB -Size $FileSize -Parts $Parts)
    ) | Where-Object { $_ -lt $FileSize -and ($FileSize / $_) -le $Parts };

    if ($PartSizes.Count -eq 0) {
        return $Size;
    }

    return $PartSizes;
}

function Compare-FileHashToS3ETag {
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$ETag
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $FileSize = (Get-Item $Path).Length;
        $Parts = $ETag.Split('-');
        if ($Parts.Count -lt 2) { $Parts = 1; }
        else { $Parts = $Parts[1]; }

        $PossiblePartSizes = Get-PossiblePartSizes -Size $FileSize -Parts $Parts;
        if ($PossiblePartSizes.Count -eq 0) {
            Invoke-Debug "No possible part sizes found for $Path with ETag $ETag";
            return $False;
        }
        foreach ($PossiblePartSize in $PossiblePartSizes) {
            $Local:OurETag = Get-ETag -Path $Path -ChunkSize $PossiblePartSize;
            Invoke-Debug "Comparing Our ETag $Local:OurETag to S3 ETag $ETag";
            if ($Local:OurETag -eq $ETag) {
                return $True;
            }
        }
    }
}

function Test-IsWindows11 {
    [String]$Private:OSCaption = (Get-CimInstance -Query 'select caption from win32_operatingsystem' | Select-Object -Property Caption).Caption;
    return $Private:OSCaption -match 'Windows 11';
}

function Remove-EncodingBom {
[CmdletBinding()]
    [OutputType([Byte[]])]
    param(
        [Parameter(Mandatory)]
        [Byte[]]$Bytes,

        [Parameter(Mandatory)]
        [System.Text.Encoding]$Encoding
    )

    begin {
        $Bom = $Encoding.GetPreamble();
        $BomLength = $Bom.Length;
        $Comparer = [Collections.Generic.SortedSet[String]]::CreateSetComparer();
    }

    process {
        if ($Bytes.Length -ge $BomLength -and $Comparer.Equals($Bytes[0..($BomLength - 1)], $Bom)) {
            return $Bytes[$BomLength..($Bytes.Length - 1)];
        }

        return $Bytes;
    }
}

function Get-ContentEncoding {
[OutputType([System.Text.Encoder])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Bytes')]
        [byte[]]$ContentBytes,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [String]$Path
    )

    begin {
        $Bytes = switch ($PSCmdlet.ParameterSetName) {
            'Bytes' { $ContentBytes }
            'Path' {
                if (-not (Test-Path -LiteralPath $Path)) {
                    throw [System.IO.FileNotFoundException]::new("The file $Path does not exist.");
                }

                $Stream = [System.IO.File]::OpenRead($Path);
                $ReadLength = [System.Math]::Min($Stream.Length, 4);
                try {
                    $Bytes = New-Object byte[] $ReadLength;
                    $Stream.Read($Bytes, 0, $ReadLength) | Out-Null;
                    $Bytes;
                } finally {
                    $Stream.Close();
                }
            }
        }

        $Comparer = [Collections.Generic.SortedSet[String]]::CreateSetComparer();
        $Encoders = @(
            [System.Text.UTF8Encoding]::new($True),             # UTF-8 with BOM
            [System.Text.UnicodeEncoding]::new($True, $True),   # UTF-16 Unicode Big-Endian
            [System.Text.UnicodeEncoding]::new($False, $True),  # UTF-16 Unicode Little-Endian
            [System.Text.UTF32Encoding]::new($True, $True),     # UTF-32 Big-Endian
            [System.Text.UTF32Encoding]::new($False, $True)     # UTF-32 Little-Endian
        );
    }

    process {
        if ($Bytes.Length -lt 4) {
            return [System.Text.Encoding]::UTF8;
        }

        foreach ($Encoder in $Encoders) {
            $Bom = $Encoder.GetPreamble();
            $BomLength = $Bom.Length;
            if ($Bytes.Length -ge $BomLength -and $Comparer.Equals($Bytes[0..($BomLength - 1)], $Bom)) {
                return $Encoder;
            }
        }

        return [System.Text.Encoding]::UTF8;
    }
}

<#
.SYNOPSIS
    Converts a value into something that can be embedded into a string and will return the original value when evaluated.

.DESCRIPTION
    Functionally this uses ConvertTo-Json under the hood, except for the following types:
        - Boolean: Will be converted to $True or $False.
        - Null: Will be converted to $null.
        - Hashtable: Will be converted to @{ ... }.
        - Array: Will be converted to @(...).
        - PSCustomObject: Will be converted to [PSCustomObject]@{ ... }.
        - ScriptBlock: Will be converted to { ... }.

.OUTPUTS
    [String]
    The string representation of the value.

.EXAMPLE
    Convert a value to a string.
    ```powershell
    $Value = $False;
    $InvokableValue = ConvertTo-InvokableValue -Value $Value;
    (Invoke-Expression $InvokableValue) -eq $Value;
    ```
#>
function ConvertTo-InvokableValue {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]$Value
    )

    process {
        if ($null -eq $Value) { return '$null' };

        $Type = $Value.GetType();

        if ($Type -eq [Boolean]) {
            return "`$$Value";
        } elseif ($Type -eq [Object[]]) {
            $Array = @();
            foreach ($Element in $Value) {
                $Array += ConvertTo-InvokableValue -Value $Element;
            }

            return '@(' + ($Array -join ', ') + ')';
        } elseif ($Type -eq [Hashtable]) {
            $Hashtable = @();
            foreach ($Key in $Value.Keys) {
                $Hashtable += "$Key = $(ConvertTo-InvokableValue -Value $Value[$Key])";
            }

            return '@{' + ($Hashtable -join '; ') + '}';
        } elseif ($Type -eq [PSCustomObject]) {
            $Hashtable = @();
            foreach ($Property in $Value.PSObject.Properties) {
                $Hashtable += "$($Property.Name)=$(ConvertTo-InvokableValue -Value $Property.Value)";
            }

            return "[PSCustomObject]@{" + ($Hashtable -join '; ') + '}';
        }


        return ConvertTo-Json -InputObject $Value;
    }
}

Export-ModuleMember `
    -Function ConvertTo-InvokableValue, Test-IsWindows11, Get-ContentEncoding, Remove-EncodingBom, Get-VarOrSave, Get-Ast, Get-ReturnType, Test-ReturnType, Test-Parameters, Install-ModuleFromGitHub, Test-NetworkConnection, Wait-Task, Start-AsyncTask, Add-LazyProperty, Set-LazyVariable, Test-IsRunningAsSystem, Get-BlobCompatableHash, Compare-FileHashToS3ETag, Get-ETag `
    -Alias await, async, lazy;
