BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/PSStyle.psm1" }

Describe 'Get-ConsoleColour Tests' {
    Context 'Basic Functionality' {
        It 'Should return ANSI escape sequence for valid colors' {
            $Colors = @([System.ConsoleColor]::Red, [System.ConsoleColor]::Blue, [System.ConsoleColor]::Green)
            
            foreach ($Color in $Colors) {
                $Result = Get-ConsoleColour -Colour $Color
                $Result | Should -Not -BeNullOrEmpty
                $Result | Should -BeLike '*[0-9]m*'
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle invalid color values gracefully' {
            { Get-ConsoleColour -Colour 'InvalidColor' } | Should -Throw
        }
    }
}