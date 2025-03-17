BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Utils.psm1" }
AfterAll { Remove-Module Utils -ErrorAction SilentlyContinue }

BeforeAll {
    $EncodingWithBom = @{
        UTF8     = [System.Text.UTF8Encoding]::new($True);
        UTF16_BE = [System.Text.UnicodeEncoding]::new($True, $True);
        UTF16_LE = [System.Text.UnicodeEncoding]::new($False, $True);
        UTF32_BE = [System.Text.UTF32Encoding]::new($True, $True);
        UTF32_LE = [System.Text.UTF32Encoding]::new($False, $True);
    }

    function Test-Bom {
        [CmdletBinding()]
        param(
            [ValidateNotNull()]
            [System.Text.Encoding]$Encoding
        )

        $Bom = $Encoding.GetPreamble();
        $Content = $Bom + $Encoding.GetBytes('Hello, World!');
        $ContentLength = $Content.Length;

        $Content[0..$($Bom.Length - 1)] | Should -BeExactly $Bom;
        $Content = Remove-EncodingBom $Content $Encoding;
        $Content[0..$($Bom.Length - 1)] | Should -Not -BeExactly $Bom;
        $Content.Length | Should -Be ($ContentLength - $Bom.Length);
        $Content | Should -BeExactly $Encoding.GetBytes('Hello, World!');
    }
}

Describe 'Remove-EncodingBom Tests' {
    It 'Should remove the BOM from UTF8' {
        Test-Bom $EncodingWithBom.UTF8;
    }

    It 'Should remove the BOM from UTF16_BE' {
        Test-Bom $EncodingWithBom.UTF16_BE;
    }

    It 'Should remove the BOM from UTF16_LE' {
        Test-Bom $EncodingWithBom.UTF16_LE;
    }

    It 'Should remove the BOM from UTF32_BE' {
        Test-Bom $EncodingWithBom.UTF32_BE;
    }

    It 'Should remove the BOM from UTF32_LE' {
        Test-Bom $EncodingWithBom.UTF32_LE;
    }

    It 'Should do nothing when no BOM' {
        $Content = [System.Text.Encoding]::UTF8.GetBytes('Hello, World!');
        $ContentLength = $Content.Length;

        $Content = Remove-EncodingBom $Content $EncodingWithBom.UTF8;
        $Content.Length | Should -Be $ContentLength;
        $Content | Should -BeExactly $EncodingWithBom.UTF8.GetBytes('Hello, World!');
    }
}
