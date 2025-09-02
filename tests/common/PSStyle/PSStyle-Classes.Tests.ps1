BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/PSStyle.psm1" }

Describe 'PSStyle Classes Tests' {
    BeforeAll {
        $ESC = [char]0x1b
    }

    Context 'ForegroundColor Class' {
        It 'Should provide correct ANSI codes for basic colors' {
            $FgColor = [ForegroundColor]::new()
            
            $FgColor.Black | Should -Be "${ESC}[30m"
            $FgColor.Red | Should -Be "${ESC}[31m"
            $FgColor.Green | Should -Be "${ESC}[32m"
            $FgColor.Yellow | Should -Be "${ESC}[33m"
            $FgColor.Blue | Should -Be "${ESC}[34m"
            $FgColor.Magenta | Should -Be "${ESC}[35m"
            $FgColor.Cyan | Should -Be "${ESC}[36m"
            $FgColor.White | Should -Be "${ESC}[37m"
        }

        It 'Should provide correct ANSI codes for bright colors' {
            $FgColor = [ForegroundColor]::new()
            
            $FgColor.BrightBlack | Should -Be "${ESC}[90m"
            $FgColor.BrightRed | Should -Be "${ESC}[91m"
            $FgColor.BrightGreen | Should -Be "${ESC}[92m"
            $FgColor.BrightYellow | Should -Be "${ESC}[93m"
            $FgColor.BrightBlue | Should -Be "${ESC}[94m"
            $FgColor.BrightMagenta | Should -Be "${ESC}[95m"
            $FgColor.BrightCyan | Should -Be "${ESC}[96m"
            $FgColor.BrightWhite | Should -Be "${ESC}[97m"
        }

        It 'Should generate RGB color codes from byte values' {
            $FgColor = [ForegroundColor]::new()
            
            $Result = $FgColor.FromRGB(255, 0, 0)  # Red
            $Result | Should -Be "${ESC}[38;2;255;0;0m"
            
            $Result = $FgColor.FromRGB(0, 255, 0)  # Green
            $Result | Should -Be "${ESC}[38;2;0;255;0m"
            
            $Result = $FgColor.FromRGB(0, 0, 255)  # Blue
            $Result | Should -Be "${ESC}[38;2;0;0;255m"
        }

        It 'Should generate RGB color codes from uint32 values' {
            $FgColor = [ForegroundColor]::new()
            
            $Result = $FgColor.FromRGB(0xFF0000)  # Red
            $Result | Should -Be "${ESC}[38;2;255;0;0m"
            
            $Result = $FgColor.FromRGB(0x00FF00)  # Green
            $Result | Should -Be "${ESC}[38;2;0;255;0m"
            
            $Result = $FgColor.FromRGB(0x0000FF)  # Blue
            $Result | Should -Be "${ESC}[38;2;0;0;255m"
        }
    }

    Context 'BackgroundColor Class' {
        It 'Should provide correct ANSI codes for basic background colors' {
            $BgColor = [BackgroundColor]::new()
            
            $BgColor.Black | Should -Be "${ESC}[40m"
            $BgColor.Red | Should -Be "${ESC}[41m"
            $BgColor.Green | Should -Be "${ESC}[42m"
            $BgColor.Yellow | Should -Be "${ESC}[43m"
            $BgColor.Blue | Should -Be "${ESC}[44m"
            $BgColor.Magenta | Should -Be "${ESC}[45m"
            $BgColor.Cyan | Should -Be "${ESC}[46m"
            $BgColor.White | Should -Be "${ESC}[47m"
        }

        It 'Should provide correct ANSI codes for bright background colors' {
            $BgColor = [BackgroundColor]::new()
            
            $BgColor.BrightBlack | Should -Be "${ESC}[100m"
            $BgColor.BrightRed | Should -Be "${ESC}[101m"
            $BgColor.BrightGreen | Should -Be "${ESC}[102m"
            $BgColor.BrightYellow | Should -Be "${ESC}[103m"
            $BgColor.BrightBlue | Should -Be "${ESC}[104m"
            $BgColor.BrightMagenta | Should -Be "${ESC}[105m"
            $BgColor.BrightCyan | Should -Be "${ESC}[106m"
            $BgColor.BrightWhite | Should -Be "${ESC}[107m"
        }

        It 'Should generate RGB background color codes from byte values' {
            $BgColor = [BackgroundColor]::new()
            
            $Result = $BgColor.FromRGB(255, 128, 64)
            $Result | Should -Be "${ESC}[48;2;255;128;64m"
        }

        It 'Should generate RGB background color codes from uint32 values' {
            $BgColor = [BackgroundColor]::new()
            
            $Result = $BgColor.FromRGB(0xFF8040)
            $Result | Should -Be "${ESC}[48;2;255;128;64m"
        }
    }

    Context 'FormattingData Class' {
        It 'Should provide correct formatting ANSI codes' {
            $Formatting = [FormattingData]::new()
            
            $Formatting.FormatAccent | Should -Be "${ESC}[32;1m"
            $Formatting.ErrorAccent | Should -Be "${ESC}[36;1m"
            $Formatting.Error | Should -Be "${ESC}[31;1m"
            $Formatting.Warning | Should -Be "${ESC}[33;1m"
            $Formatting.Verbose | Should -Be "${ESC}[33;1m"
            $Formatting.Debug | Should -Be "${ESC}[33;1m"
            $Formatting.TableHeader | Should -Be "${ESC}[32;1m"
            $Formatting.CustomTableHeaderLabel | Should -Be "${ESC}[32;1;3m"
            $Formatting.FeedbackProvider | Should -Be "${ESC}[33m"
            $Formatting.FeedbackText | Should -Be "${ESC}[96m"
        }
    }

    Context 'ProgressConfiguration Class' {
        It 'Should have default values' {
            $Progress = [ProgressConfiguration]::new()
            
            $Progress.Style | Should -Be "${ESC}[33;1m"
            $Progress.MaxWidth | Should -Be 120
            $Progress.View | Should -Be ([ProgressView]::Minimal)
            $Progress.UseOSCIndicator | Should -Be $false
        }
    }

    Context 'PSStyle Main Class' {
        It 'Should provide text formatting codes' {
            $Style = [PSStyle]::new()
            
            $Style.Reset | Should -Be "${ESC}[0m"
            $Style.Bold | Should -Be "${ESC}[1m"
            $Style.BoldOff | Should -Be "${ESC}[22m"
            $Style.Dim | Should -Be "${ESC}[2m"
            $Style.DimOff | Should -Be "${ESC}[22m"
            $Style.Italic | Should -Be "${ESC}[3m"
            $Style.ItalicOff | Should -Be "${ESC}[23m"
            $Style.Underline | Should -Be "${ESC}[4m"
            $Style.UnderlineOff | Should -Be "${ESC}[24m"
            $Style.Strikethrough | Should -Be "${ESC}[9m"
            $Style.StrikethroughOff | Should -Be "${ESC}[29m"
            $Style.Reverse | Should -Be "${ESC}[7m"
            $Style.ReverseOff | Should -Be "${ESC}[27m"
            $Style.Blink | Should -Be "${ESC}[5m"
            $Style.BlinkOff | Should -Be "${ESC}[25m"
            $Style.Hidden | Should -Be "${ESC}[8m"
            $Style.HiddenOff | Should -Be "${ESC}[28m"
        }

        It 'Should have nested color objects' {
            $Style = [PSStyle]::new()
            
            $Style.Foreground | Should -BeOfType [ForegroundColor]
            $Style.Background | Should -BeOfType [BackgroundColor]
            $Style.Formatting | Should -BeOfType [FormattingData]
            $Style.Progress | Should -BeOfType [ProgressConfiguration]
            $Style.FileInfo | Should -BeOfType [FileInfoFormatting]
        }

        It 'Should format hyperlinks correctly' {
            $Style = [PSStyle]::new()
            $Uri = [Uri]'https://example.com'
            
            $Result = $Style.FormatHyperlink('Example Link', $Uri)
            $Result | Should -Be "${ESC}]8;;https://example.com${ESC}\Example Link${ESC}]8;;${ESC}\"
        }
    }

    Context 'Static Color Mapping Methods' {
        It 'Should map foreground colors correctly' {
            $RedSequence = [PSStyle]::MapForegroundColorToEscapeSequence([ConsoleColor]::Red)
            $RedSequence | Should -Be "${ESC}[31m"
            
            $BlueSequence = [PSStyle]::MapForegroundColorToEscapeSequence([ConsoleColor]::Blue)
            $BlueSequence | Should -Be "${ESC}[94m"
        }

        It 'Should map background colors correctly' {
            $RedBgSequence = [PSStyle]::MapBackgroundColorToEscapeSequence([ConsoleColor]::Red)
            $RedBgSequence | Should -Be "${ESC}[41m"
            
            $BlueBgSequence = [PSStyle]::MapBackgroundColorToEscapeSequence([ConsoleColor]::Blue)
            $BlueBgSequence | Should -Be "${ESC}[104m"
        }

        It 'Should map color pairs correctly' {
            $PairSequence = [PSStyle]::MapColorPairToEscapeSequence([ConsoleColor]::Red, [ConsoleColor]::Blue)
            $PairSequence | Should -BeLike "*${ESC}[31m*${ESC}[44m*"
        }

        It 'Should throw for invalid color values' {
            { [PSStyle]::MapForegroundColorToEscapeSequence(999) } | Should -Throw
            { [PSStyle]::MapBackgroundColorToEscapeSequence(-1) } | Should -Throw
        }
    }

    Context 'FileInfoFormatting Class' {
        It 'Should provide file extension formatting' {
            $FileInfo = [FileInfoFormatting]::new()
            
            $FileInfo.Directory | Should -Be "${ESC}[44;1m"
            $FileInfo.SymbolicLink | Should -Be "${ESC}[36;1m"
            $FileInfo.Executable | Should -Be "${ESC}[32;1m"
            $FileInfo.Extension | Should -BeOfType [hashtable[]]
            $FileInfo.Extension.Count | Should -BeGreaterThan 0
        }
    }
}