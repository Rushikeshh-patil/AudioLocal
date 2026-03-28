[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StableId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    }
    finally {
        $sha1.Dispose()
    }
    $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
    return "{0}_{1}" -f $Prefix, $hex.Substring(0, 16).ToUpperInvariant()
}

function Escape-Xml {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [System.Security.SecurityElement]::Escape($Value)
}

function Write-DirectoryNode {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Directory,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$Builder,

        [Parameter(Mandatory = $true)]
        [ref]$ComponentIds,

        [Parameter(Mandatory = $true)]
        [int]$IndentLevel
    )

    $indent = ("  " * $IndentLevel)
    $directoryId = if ([string]::IsNullOrEmpty($RelativePath)) { "INSTALLFOLDER" } else { Get-StableId -Prefix "DIR" -Value $RelativePath }

    if (-not [string]::IsNullOrEmpty($RelativePath)) {
        [void]$Builder.AppendLine(('{0}<Directory Id="{1}" Name="{2}">' -f $indent, $directoryId, (Escape-Xml $Directory.Name)))
    }

    $childrenIndentLevel = if ([string]::IsNullOrEmpty($RelativePath)) { $IndentLevel } else { $IndentLevel + 1 }
    $childrenIndent = ("  " * $childrenIndentLevel)

    foreach ($file in ($Directory.GetFiles() | Sort-Object Name)) {
        $relativeFilePath = if ([string]::IsNullOrEmpty($RelativePath)) { $file.Name } else { [IO.Path]::Combine($RelativePath, $file.Name) }
        $componentId = Get-StableId -Prefix "CMP" -Value $relativeFilePath
        $fileId = Get-StableId -Prefix "FIL" -Value $relativeFilePath
        $wixSource = $file.FullName

        [void]$ComponentIds.Value.Add($componentId)
        [void]$Builder.AppendLine(('{0}<Component Id="{1}" Guid="*">' -f $childrenIndent, $componentId))
        [void]$Builder.AppendLine(('{0}  <File Id="{1}" Source="{2}" KeyPath="yes" />' -f $childrenIndent, $fileId, (Escape-Xml $wixSource)))
        [void]$Builder.AppendLine(('{0}</Component>' -f $childrenIndent))
    }

    foreach ($child in ($Directory.GetDirectories() | Sort-Object Name)) {
        $childRelativePath = if ([string]::IsNullOrEmpty($RelativePath)) { $child.Name } else { [IO.Path]::Combine($RelativePath, $child.Name) }
        Write-DirectoryNode -Directory $child -RelativePath $childRelativePath -Builder $Builder -ComponentIds $ComponentIds -IndentLevel $childrenIndentLevel
    }

    if (-not [string]::IsNullOrEmpty($RelativePath)) {
        [void]$Builder.AppendLine(('{0}</Directory>' -f $indent))
    }
}

$publishRoot = [System.IO.DirectoryInfo](Get-Item -LiteralPath (Resolve-Path -LiteralPath $PublishDir).Path)
$outputFile = [System.IO.FileInfo]$OutputPath
[System.IO.Directory]::CreateDirectory($outputFile.DirectoryName) | Out-Null

$builder = [System.Text.StringBuilder]::new()
$componentIds = [System.Collections.Generic.List[string]]::new()

[void]$builder.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
[void]$builder.AppendLine('  <Fragment>')
[void]$builder.AppendLine('    <StandardDirectory Id="ProgramFiles64Folder">')
[void]$builder.AppendLine('      <Directory Id="INSTALLFOLDER" Name="AudioLocal">')
Write-DirectoryNode -Directory $publishRoot -RelativePath '' -Builder $builder -ComponentIds ([ref]$componentIds) -IndentLevel 4
[void]$builder.AppendLine('      </Directory>')
[void]$builder.AppendLine('    </StandardDirectory>')
[void]$builder.AppendLine('  </Fragment>')
[void]$builder.AppendLine()
[void]$builder.AppendLine('  <Fragment>')
[void]$builder.AppendLine('    <ComponentGroup Id="PublishedApplicationFiles">')
foreach ($componentId in $componentIds) {
    [void]$builder.AppendLine(('      <ComponentRef Id="{0}" />' -f $componentId))
}
[void]$builder.AppendLine('    </ComponentGroup>')
[void]$builder.AppendLine('  </Fragment>')
[void]$builder.AppendLine('</Wix>')

[System.IO.File]::WriteAllText($outputFile.FullName, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
