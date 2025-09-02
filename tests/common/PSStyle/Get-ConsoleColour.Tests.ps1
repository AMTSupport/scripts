BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/PSStyle.psm1" }

Describe 'Get-ConsoleColour Tests' {
    Context 'Basic Functionality' {
        It 'Should return ANSI escape sequence for Red color' {
            $Result = Get-ConsoleColour -Colour Red
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*31m*'  # Red ANSI code
        }

        It 'Should return ANSI escape sequence for Blue color' {
            $Result = Get-ConsoleColour -Colour Blue
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*34m*'  # Blue ANSI code (dark) or *94m* (bright)
        }

        It 'Should return ANSI escape sequence for Green color' {
            $Result = Get-ConsoleColour -Colour Green
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*32m*'  # Green ANSI code
        }

        It 'Should return ANSI escape sequence for Yellow color' {
            $Result = Get-ConsoleColour -Colour Yellow
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*33m*'  # Yellow ANSI code
        }

        It 'Should return ANSI escape sequence for Magenta color' {
            $Result = Get-ConsoleColour -Colour Magenta
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*35m*'  # Magenta ANSI code
        }

        It 'Should return ANSI escape sequence for Cyan color' {
            $Result = Get-ConsoleColour -Colour Cyan
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*36m*'  # Cyan ANSI code
        }

        It 'Should return ANSI escape sequence for White color' {
            $Result = Get-ConsoleColour -Colour White
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*37m*'  # White ANSI code
        }

        It 'Should return ANSI escape sequence for Black color' {
            $Result = Get-ConsoleColour -Colour Black
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*30m*'  # Black ANSI code
        }
    }

    Context 'Bright Colors' {
        It 'Should handle DarkBlue color' {
            $Result = Get-ConsoleColour -Colour DarkBlue
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*34m*'
        }

        It 'Should handle DarkGreen color' {
            $Result = Get-ConsoleColour -Colour DarkGreen
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*32m*'
        }

        It 'Should handle DarkRed color' {
            $Result = Get-ConsoleColour -Colour DarkRed
            
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -BeLike '*31m*'
        }
    }

    Context 'PowerShell Version Compatibility' {
        It 'Should work across different PowerShell versions' {
            # Test that the function works regardless of PowerShell version
            $Colors = @([System.ConsoleColor]::Red, [System.ConsoleColor]::Blue, [System.ConsoleColor]::Green)
            
            foreach ($Color in $Colors) {
                $Result = Get-ConsoleColour -Colour $Color
                $Result | Should -Not -BeNullOrEmpty
                $Result | Should -BeLike '*[0-9]m*'  # Should contain ANSI escape sequence
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle invalid color values gracefully' {
            # This test depends on parameter validation, which should catch invalid values
            { Get-ConsoleColour -Colour 'InvalidColor' } | Should -Throw
        }
    }
}