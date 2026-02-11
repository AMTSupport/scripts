BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/PSStyle.psm1" }

Describe 'PSStyle Classes Tests' {
    Context 'Class Availability' {
        It 'Should load PSStyle classes successfully' {
            [ForegroundColor] | Should -Not -BeNullOrEmpty
            [BackgroundColor] | Should -Not -BeNullOrEmpty
            [FormatData] | Should -Not -BeNullOrEmpty
        }
    }
}