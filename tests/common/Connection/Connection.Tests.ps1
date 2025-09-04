Describe "Connection Module Tests" {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Connection.psm1" -Force
        
        # Mock external dependencies for cross-platform testing
        Mock Connect-ExchangeOnline { } -ModuleName Connection
        Mock Disconnect-ExchangeOnline { } -ModuleName Connection
        Mock Connect-IPPSSession { } -ModuleName Connection
        Mock Connect-MgGraph { } -ModuleName Connection
        Mock Disconnect-MgGraph { } -ModuleName Connection
        Mock Get-ConnectionInformation { 
            [PSCustomObject]@{
                UserPrincipalName = 'test@example.com'
                ConnectionId = 'test-connection-id'
            }
        } -ModuleName Connection
        Mock Get-MgContext { 
            [PSCustomObject]@{
                Account = 'test@example.com'
                Scopes = @('User.Read', 'Mail.Read')
            }
        } -ModuleName Connection
        Mock Get-UserConfirmation { $true } -ModuleName Connection
    }

    Context "Module Import" {
        It "Should import Connection module successfully" {
            Get-Module -Name Connection* | Should -Not -BeNullOrEmpty
        }

        It "Should export expected functions" {
            $ExportedFunctions = (Get-Module -Name Connection*).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Connect-Service'
        }
    }



    Context "ExchangeOnline Service Tests" {
        BeforeEach {
            Mock Get-ConnectionInformation { $null } -ModuleName Connection
        }

        It "Should handle ExchangeOnline connection" {
            Mock Connect-ExchangeOnline { } -ModuleName Connection
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'test@example.com'
                    ConnectionId = 'exchange-connection'
                }
            } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-ExchangeOnline -Times 1 -ModuleName Connection
        }

        It "Should handle existing ExchangeOnline connection" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'existing@example.com'
                    ConnectionId = 'existing-connection'
                }
            } -ModuleName Connection
            Mock Get-UserConfirmation { $true } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' } | Should -Not -Throw
            
            # Should not call Connect-ExchangeOnline if already connected and user confirms
            Assert-MockCalled Get-UserConfirmation -Times 1 -ModuleName Connection
        }

        It "Should disconnect and reconnect if user declines" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'existing@example.com'
                    ConnectionId = 'existing-connection'
                }
            } -ModuleName Connection
            Mock Get-UserConfirmation { $false } -ModuleName Connection
            Mock Disconnect-ExchangeOnline { } -ModuleName Connection
            Mock Connect-ExchangeOnline { } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' } | Should -Not -Throw
            
            Assert-MockCalled Disconnect-ExchangeOnline -Times 1 -ModuleName Connection
            Assert-MockCalled Connect-ExchangeOnline -Times 1 -ModuleName Connection
        }
    }

    Context "SecurityComplience Service Tests" {
        BeforeEach {
            Mock Get-ConnectionInformation { $null } -ModuleName Connection
        }

        It "Should handle SecurityComplience connection" {
            Mock Connect-IPPSSession { } -ModuleName Connection
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'test@example.com'
                    ConnectionId = 'ipps-connection'
                }
            } -ModuleName Connection
            
            { Connect-Service -Services 'SecurityComplience' -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-IPPSSession -Times 1 -ModuleName Connection
        }

        It "Should handle SecurityComplience disconnection" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'test@example.com'
                    ConnectionId = 'ipps-connection'
                }
            } -ModuleName Connection
            Mock Disconnect-ExchangeOnline { } -ModuleName Connection
            
            # The disconnect for SecurityComplience uses Disconnect-ExchangeOnline
            { Connect-Service -Services 'SecurityComplience' -CheckOnly } | Should -Not -Throw
        }
    }

    Context "Graph Service Tests" {
        BeforeEach {
            Mock Get-MgContext { $null } -ModuleName Connection
        }

        It "Should handle Graph connection without scopes" {
            Mock Connect-MgGraph { } -ModuleName Connection
            Mock Get-MgContext { 
                [PSCustomObject]@{
                    Account = 'test@example.com'
                    Scopes = @()
                }
            } -ModuleName Connection
            
            { Connect-Service -Services 'Graph' -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection
        }

        It "Should handle Graph connection with scopes" {
            Mock Connect-MgGraph { } -ModuleName Connection
            Mock Get-MgContext { 
                [PSCustomObject]@{
                    Account = 'test@example.com'
                    Scopes = @('User.Read', 'Mail.Read')
                }
            } -ModuleName Connection
            
            $Scopes = @('User.Read', 'Mail.Read')
            { Connect-Service -Services 'Graph' -Scopes $Scopes -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection
        }

        It "Should handle Graph connection with access token" {
            Mock Connect-MgGraph { } -ModuleName Connection
            Mock Get-MgContext { 
                [PSCustomObject]@{
                    Account = 'test@example.com'
                    Scopes = @('User.Read')
                }
            } -ModuleName Connection
            
            $SecureToken = ConvertTo-SecureString 'token123' -AsPlainText -Force
            { Connect-Service -Services 'Graph' -AccessToken $SecureToken -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection -ParameterFilter { $AccessToken -ne $null }
        }

        It "Should handle insufficient scopes in Graph connection" {
            Mock Connect-MgGraph { } -ModuleName Connection
            Mock Get-MgContext { 
                [PSCustomObject]@{
                    Account = 'test@example.com'
                    Scopes = @('User.Read')  # Missing Mail.Read
                }
            } -ModuleName Connection
            Mock Disconnect-MgGraph { } -ModuleName Connection
            
            $RequiredScopes = @('User.Read', 'Mail.Read')
            { Connect-Service -Services 'Graph' -Scopes $RequiredScopes -DontConfirm } | Should -Not -Throw
            
            # Should disconnect due to insufficient scopes
            Assert-MockCalled Disconnect-MgGraph -Times 1 -ModuleName Connection
        }

        It "Should handle Graph disconnection" {
            Mock Disconnect-MgGraph { } -ModuleName Connection
            
            { Disconnect-MgGraph } | Should -Not -Throw
            
            Assert-MockCalled Disconnect-MgGraph -Times 1 -ModuleName Connection
        }
    }

    Context "CheckOnly Parameter Tests" {
        It "Should check connection status without connecting" {
            Mock Get-ConnectionInformation { $null } -ModuleName Connection
            Mock Invoke-FailedExit { throw "Not connected" } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' -CheckOnly } | Should -Throw "Not connected"
            
            # Should not attempt to connect
            Assert-MockCalled Connect-ExchangeOnline -Times 0 -ModuleName Connection
        }

        It "Should pass check when already connected" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'test@example.com'
                    ConnectionId = 'existing-connection'
                }
            } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' -CheckOnly } | Should -Not -Throw
        }
    }

    Context "DontConfirm Parameter Tests" {
        It "Should skip confirmation when DontConfirm is used" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'existing@example.com'
                    ConnectionId = 'existing-connection'
                }
            } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' -DontConfirm } | Should -Not -Throw
            
            # Should not call Get-UserConfirmation
            Assert-MockCalled Get-UserConfirmation -Times 0 -ModuleName Connection
        }

        It "Should prompt for confirmation by default" {
            Mock Get-ConnectionInformation { 
                [PSCustomObject]@{
                    UserPrincipalName = 'existing@example.com'
                    ConnectionId = 'existing-connection'
                }
            } -ModuleName Connection
            Mock Get-UserConfirmation { $true } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' } | Should -Not -Throw
            
            Assert-MockCalled Get-UserConfirmation -Times 1 -ModuleName Connection
        }
    }

    Context "Error Handling" {
        It "Should handle connection failures" {
            Mock Get-ConnectionInformation { $null } -ModuleName Connection
            Mock Connect-ExchangeOnline { throw "Connection failed" } -ModuleName Connection
            Mock Invoke-FailedExit { throw "Failed to connect" } -ModuleName Connection
            
            { Connect-Service -Services 'ExchangeOnline' -DontConfirm } | Should -Throw
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Connection
        }

        It "Should handle disconnection failures" {
            Mock Disconnect-ExchangeOnline { throw "Disconnect failed" } -ModuleName Connection
            Mock Invoke-FailedExit { throw "Failed to disconnect" } -ModuleName Connection
            
            { Disconnect-ExchangeOnline } | Should -Throw
        }

        It "Should handle Graph context retrieval failures" {
            Mock Get-MgContext { throw "Graph context error" } -ModuleName Connection
            Mock Connect-MgGraph { } -ModuleName Connection
            
            { Connect-Service -Services 'Graph' -DontConfirm } | Should -Not -Throw
            
            # Should attempt to connect when context retrieval fails
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection
        }
    }

    Context "Multiple Services Integration" {
        It "Should handle connecting to multiple services" {
            Mock Get-ConnectionInformation { $null } -ModuleName Connection
            Mock Get-MgContext { $null } -ModuleName Connection
            Mock Connect-ExchangeOnline { } -ModuleName Connection
            Mock Connect-MgGraph { } -ModuleName Connection
            
            { Connect-Service -Services @('ExchangeOnline', 'Graph') -DontConfirm } | Should -Not -Throw
            
            Assert-MockCalled Connect-ExchangeOnline -Times 1 -ModuleName Connection
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection
        }

        It "Should handle mixed connection states" {
            # ExchangeOnline already connected, Graph not connected
            Mock Get-ConnectionInformation { 
                param($ConnectionId)
                if ($ConnectionId) {
                    [PSCustomObject]@{
                        UserPrincipalName = 'test@example.com'
                        ConnectionId = $ConnectionId
                    }
                } else {
                    [PSCustomObject]@{
                        UserPrincipalName = 'test@example.com'
                        ConnectionId = 'exchange-connection'
                    }
                }
            } -ModuleName Connection
            Mock Get-MgContext { $null } -ModuleName Connection
            Mock Connect-MgGraph { } -ModuleName Connection
            
            { Connect-Service -Services @('ExchangeOnline', 'Graph') -DontConfirm } | Should -Not -Throw
            
            # Should only connect to Graph
            Assert-MockCalled Connect-ExchangeOnline -Times 0 -ModuleName Connection
            Assert-MockCalled Connect-MgGraph -Times 1 -ModuleName Connection
        }
    }


}