'core', 'json', 'Helpers' | ForEach-Object {
    . (Join-Path $PSScriptRoot "$_.ps1")
}

function find_hash_in_rdf([String] $url, [String] $basename) {
    $data = $null
    try {
        # Download and parse RDF XML file
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $data = $wc.DownloadString($url)
    } catch [System.Net.WebException] {
        Write-UserMessage -Message $_, "URL $url is not valid" -Color DarkRed

        return $null
    }
    if (Test-ScoopDebugEnabled) { Join-Path $PWD 'checkver-hash-rdf.html' | Out-UTF8Content -Content $data }
    $data = [xml] $data

    # Find file content
    $digest = $data.RDF.Content | Where-Object { [String]$_.about -eq $basename }

    return format_hash $digest.sha256
}

function find_hash_in_textfile([String] $url, [Hashtable] $substitutions, [String] $regex) {
    $hashfile = $null

    $templates = @{
        '$md5'      = '([a-fA-F\d]{32})'
        '$sha1'     = '([a-fA-F\d]{40})'
        '$sha256'   = '([a-fA-F\d]{64})'
        '$sha512'   = '([a-fA-F\d]{128})'
        '$checksum' = '([a-fA-F\d]{32,128})'
        '$base64'   = '([a-zA-Z\d+\/=]{24,88})'
    }

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $hashfile = $wc.DownloadString($url)
    } catch [System.Net.WebException] {
        Write-UserMessage -Message $_, "URL $url is not valid" -Color DarkRed
        return
    }
    if (Test-ScoopDebugEnabled) { Join-Path $PWD 'checkver-hash-txt.html' | Out-UTF8Content -Content $hashfile }

    if ($regex.Length -eq 0) { $regex = '^([a-fA-F\d]+)$' }

    $regex = Invoke-VariableSubstitution -Entity $regex -Parameters $templates -EscapeRegularExpression:$false
    $regex = Invoke-VariableSubstitution -Entity $regex -Parameters $substitutions -EscapeRegularExpression:$true

    debug $regex

    if ($hashfile -match $regex) { $hash = $Matches[1] -replace '\s' }

    # Find hash with filename in $hashfile
    if ($hash.Length -eq 0) {
        $filenameRegex = "([a-fA-F\d]{32,128})[\x20\t]+.*`$basename(?:[\x20\t]+\d+)?"
        $filenameRegex = Invoke-VariableSubstitution -Entity $filenameRegex -Parameters $substitutions -EscapeRegularExpression:$true
        if ($hashfile -match $filenameRegex) {
            $hash = $Matches[1]
        }
        $metalinkRegex = '<hash[^>]+>([a-fA-F\d]{64})'
        if ($hashfile -match $metalinkRegex) {
            $hash = $Matches[1]
        }
    }

    return format_hash $hash
}

function find_hash_in_json([String] $url, [Hashtable] $substitutions, [String] $jsonpath) {
    $json = $null

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $json = $wc.DownloadString($url)
    } catch [System.Net.WebException] {
        Write-UserMessage -Message $_, "URL $url is not valid" -Color DarkRed
        return
    }
    if (Test-ScoopDebugEnabled) { Join-Path $PWD 'checkver-hash-json.html' | Out-UTF8Content -Content $json }

    $hash = json_path $json $jsonpath $substitutions
    if (!$hash) {
        $hash = json_path_legacy $json $jsonpath $substitutions
    }

    return format_hash $hash
}

function find_hash_in_xml([String] $url, [Hashtable] $substitutions, [String] $xpath) {
    $xml = $null

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Referer', (strip_filename $url))
        $wc.Headers.Add('User-Agent', (Get-UserAgent))
        $xml = $wc.DownloadString($url)
    } catch [System.Net.WebException] {
        Write-UserMessage -Message $_, "URL $url is not valid" -Color DarkRed
        return
    }

    if (Test-ScoopDebugEnabled) { Join-Path $PWD 'checkver-hash-xml.html' | Out-UTF8Content -Content $xml }
    $xml = [xml] $xml

    # Replace placeholders
    if ($substitutions) { $xpath = Invoke-VariableSubstitution -Entity $xpath -Parameters $substitutions }

    # Find all `significant namespace declarations` from the XML file
    $nsList = $xml.SelectNodes('//namespace::*[not(. = ../../namespace::*)]')
    # Then add them into the NamespaceManager
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsList | ForEach-Object {
        $nsmgr.AddNamespace($_.LocalName, $_.Value)
    }

    # Getting hash from XML, using XPath
    $hash = $xml.SelectSingleNode($xpath, $nsmgr).'#text'

    return format_hash $hash
}

function find_hash_in_headers([String] $url) {
    $hash = $null

    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Referer = (strip_filename $url)
        $req.AllowAutoRedirect = $false
        $req.UserAgent = (Get-UserAgent)
        $req.Timeout = 2000
        $req.Method = 'HEAD'
        $res = $req.GetResponse()
        if (([int]$response.StatusCode -ge 300) -and ([int]$response.StatusCode -lt 400)) {
            if ($res.Headers['Digest'] -match 'SHA-256=([^,]+)' -or $res.Headers['Digest'] -match 'SHA=([^,]+)' -or $res.Headers['Digest'] -match 'MD5=([^,]+)') {
                $hash = ([System.Convert]::FromBase64String($Matches[1]) | ForEach-Object { $_.ToString('x2') }) -join ''
                debug $hash
            }
        }
        $res.Close()
    } catch [System.Net.WebException] {
        Write-UserMessage -Message $_, "URL $url is not valid" -Color DarkRed
        return
    }

    return format_hash $hash
}

function get_hash_for_app([String] $app, $config, [String] $version, [String] $url, [Hashtable] $substitutions) {
    $hash = $null

    $hashmode = $config.mode
    $basename = [System.Web.HttpUtility]::UrlDecode((url_remote_filename($url)))

    $substitutions = $substitutions.Clone()
    $substitutions.Add('$url', (strip_fragment $url))
    $substitutions.Add('$urlNoExt', (strip_ext (strip_fragment $url)))
    $substitutions.Add('$baseurl', (strip_filename (strip_fragment $url)).TrimEnd('/'))
    $substitutions.Add('$basename', $basename)
    $substitutions.Add('$basenameNoExt', (strip_ext $basename))

    debug $substitutions

    $hashfile_url = Invoke-VariableSubstitution -Entity $config.url -Parameters $substitutions

    debug $hashfile_url

    if ($hashfile_url) {
        Write-Host 'Searching hash for ' -ForegroundColor DarkYellow -NoNewline
        Write-Host $basename -ForegroundColor Green -NoNewline
        Write-Host ' in ' -ForegroundColor DarkYellow -NoNewline
        Write-Host $hashfile_url -ForegroundColor Green
    }

    if ($hashmode.Length -eq 0 -and $config.url.Length -ne 0) {
        $hashmode = 'extract'
    }

    $jsonpath = ''
    if ($config.jp) {
        Write-UserMessage -Message '''jp'' property is deprecated. Use ''jsonpath'' instead.' -Err
        $jsonpath = $config.jp
        $hashmode = 'json'
    }
    if ($config.jsonpath) {
        $jsonpath = $config.jsonpath
        $hashmode = 'json'
    }
    $regex = ''
    if ($config.find) {
        Write-UserMessage -Message '''find'' property is deprecated. Use ''regex'' instead.' -Err
        $regex = $config.find
    }
    if ($config.regex) {
        $regex = $config.regex
    }

    $xpath = ''
    if ($config.xpath) {
        $xpath = $config.xpath
        $hashmode = 'xpath'
    }

    if (!$hashfile_url -and $url -match '^(?:.*fosshub.com\/).*(?:\/|\?dwl=)(?<filename>.*)$') {
        $hashmode = 'fosshub'
    }

    if (!$hashfile_url -and $url -match '(?:downloads\.)?sourceforge.net\/projects?\/(?<project>[^\/]+)\/(?:files\/)?(?<file>.*)') {
        $hashmode = 'sourceforge'
    }

    switch ($hashmode) {
        'extract' {
            $hash = find_hash_in_textfile $hashfile_url $substitutions $regex
        }
        'json' {
            $hash = find_hash_in_json $hashfile_url $substitutions $jsonpath
        }
        'xpath' {
            $hash = find_hash_in_xml $hashfile_url $substitutions $xpath
        }
        'rdf' {
            $hash = find_hash_in_rdf $hashfile_url $basename
        }
        'metalink' {
            $hash = find_hash_in_headers $url
            if (!$hash) {
                $hash = find_hash_in_textfile "$url.meta4" $substitutions
            }
        }
        'fosshub' {
            $hash = find_hash_in_textfile $url $substitutions ($Matches.filename + '.*?"sha256":"([a-fA-F\d]{64})"')
        }
        'sourceforge' {
            # Change the URL because downloads.sourceforge.net doesn't have checksums
            $hashfile_url = (strip_filename (strip_fragment "https://sourceforge.net/projects/$($Matches['project'])/files/$($Matches['file'])")).TrimEnd('/')
            $hash = find_hash_in_textfile $hashfile_url $substitutions '"$basename":.*?"sha1":\s"([a-fA-F\d]{40})"'
        }
    }

    if ($hash) {
        Write-Host 'Found: ' -ForegroundColor DarkYellow -NoNewline
        Write-Host $hash -ForegroundColor Green -NoNewline
        Write-Host ' using ' -ForegroundColor DarkYellow -NoNewline
        Write-Host "$((Get-Culture).TextInfo.ToTitleCase($hashmode)) Mode" -ForegroundColor Green

        return $hash
    } elseif ($hashfile_url) {
        Write-UserMessage -Message "Could not find hash in $hashfile_url" -Color DarkYellow
    }

    Write-Host 'Downloading ' -ForegroundColor DarkYellow -NoNewline
    Write-Host $basename -ForegroundColor Green -NoNewline
    Write-Host ' to compute hashes!' -ForegroundColor DarkYellow

    try {
        dl_with_cache $app $version $url $null $null $true
    } catch {
        Write-UserMessage -Message "URL $url is not valid" -Color DarkRed
        return $null
    }
    $file = cache_path $app $version $url
    $hash = compute_hash $file 'sha256'
    Write-Host 'Computed hash: ' -ForegroundColor DarkYellow -NoNewline
    Write-Host $hash -ForegroundColor Green

    return $hash
}

function update_manifest_with_new_version($json, [String] $version, [String] $url, [String] $hash, $architecture = $null) {
    $json.version = $version

    if ($null -eq $architecture) {
        if ($json.url -is [System.Array]) {
            $json.url[0] = $url
            $json.hash[0] = $hash
        } else {
            $json.url = $url
            $json.hash = $hash
        }
    } else {
        # If there are multiple urls we replace the first one
        if ($json.architecture.$architecture.url -is [System.Array]) {
            $json.architecture.$architecture.url[0] = $url
            $json.architecture.$architecture.hash[0] = $hash
        } else {
            $json.architecture.$architecture.url = $url
            $json.architecture.$architecture.hash = $hash
        }
    }
}

function update_manifest_prop([String] $prop, $json, [Hashtable] $substitutions) {
    # first try the global property
    if ($json.$prop -and $json.autoupdate.$prop) {
        $json.$prop = Invoke-VariableSubstitution -Entity $json.autoupdate.$prop -Parameters $substitutions
    }

    # check if there are architecture specific variants
    if ($json.architecture -and $json.autoupdate.architecture) {
        $json.architecture | Get-Member -MemberType NoteProperty | ForEach-Object {
            $architecture = $_.Name
            if ($json.architecture.$architecture.$prop -and $json.autoupdate.architecture.$architecture.$prop) {
                $json.architecture.$architecture.$prop = Invoke-VariableSubstitution -Entity (arch_specific $prop $json.autoupdate $architecture) -Parameters $substitutions
            }
        }
    }
}

function Get-VersionSubstitution ([String] $Version, [Hashtable] $CustomMatches = @{ }) {
    $firstPart = $Version -split '-' | Select-Object -First 1
    $lastPart = $Version -split '-' | Select-Object -Last 1
    $versionVariables = @{
        '$version'           = $Version
        '$underscoreVersion' = ($Version -replace '\.', '_')
        '$dashVersion'       = ($Version -replace '\.', '-')
        '$cleanVersion'      = ($Version -replace '\.')
        '$majorVersion'      = ($firstPart -split '\.' | Select-Object -First 1)
        '$minorVersion'      = ($firstPart -split '\.' | Select-Object -Skip 1 -First 1)
        '$patchVersion'      = ($firstPart -split '\.' | Select-Object -Skip 2 -First 1)
        '$buildVersion'      = ($firstPart -split '\.' | Select-Object -Skip 3 -First 1)
        '$preReleaseVersion' = $lastPart
    }
    if ($Version -match '(?<head>\d+\.\d+(?:\.\d+)?)(?<tail>.*)') {
        $versionVariables.Add('$matchHead', $Matches['head'])
        $versionVariables.Add('$headVersion', $Matches['head'])
        $versionVariables.Add('$matchTail', $Matches['tail'])
        $versionVariables.Add('$tailVersion', $Matches['tail'])
    }
    if ($CustomMatches) {
        $CustomMatches.GetEnumerator() | Where-Object -Property Name -NE -Value '0' | ForEach-Object {
            # .Add() cannot be used due to unskilled maintainers, who could use internal $matchHead or $matchTail variable and receive exception
            $versionVariables.set_Item('$match' + (Get-Culture).TextInfo.ToTitleCase($_.Name), $_.Value)
        }
    }

    return $versionVariables
}

function Update-ManifestProperty {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory)]
        [Alias('InputObject')]
        $Manifest,
        [Parameter(ValueFromPipeline)]
        [String[]] $Property,
        [String] $AppName,
        [String] $Version,
        [HashTable] $Substitutions
    )

    begin { $manifestChanged = $false }

    process {
        $AppName | Out-Null # PowerShell/PSScriptAnalyzer#1472

        foreach ($prop in $Property) {
            if ($prop -eq 'hash') {
                if ($Manifest.hash) {
                    # Substitute new value
                    $newURL = Invoke-VariableSubstitution -Entity $Manifest.autoupdate.url -Parameters $Substitutions
                    $newHash = _getHashesForUrls -AppName $AppName -Version $Version -HashExtraction $Manifest.autoupdate.hash -URL $newURL -Substitutions $Substitutions

                    # Update manifest
                    $Manifest.hash, $propertyChanged = _updateSpecificProperty -Property $Manifest.hash -Value $newHash
                    $manifestChanged = $manifestChanged -or $propertyChanged
                } else {
                    # Arch-spec
                    $Manifest.architecture | Get-Member -MemberType NoteProperty | ForEach-Object {
                        $arch = $_.Name
                        # Substitute new URLS
                        $newURL = Invoke-VariableSubstitution -Entity (arch_specific 'url' $Manifest.autoupdate $arch) -Parameters $Substitutions
                        # Calculate/extract hashes
                        $newHash = _getHashesForUrls -AppName $AppName -Version $Version -HashExtraction (arch_specific 'hash' $Manifest.autoupdate $arch) -URL $newURL -Substitutions $Substitutions

                        # Update manifest
                        $Manifest.architecture.$arch.hash, $propertyChanged = _updateSpecificProperty -Property $Manifest.architecture.$arch.hash -Value $newHash
                        $manifestChanged = $manifestChanged -or $propertyChanged
                    }
                }
                # Extract and update hash property
            } elseif ($Manifest.$prop -and $Manifest.autoupdate.$Prop) {
                # Substitute new value
                $newValue = Invoke-VariableSubstitution -Entity $Manifest.autoupdate.$prop -Parameters $Substitutions

                # Update manifest
                $Manifest.$prop, $propertyChanged = _updateSpecificProperty -Property $Manifest.$prop -Value $newValue
                $manifestChanged = $manifestChanged -or $propertyChanged
            } elseif ($Manifest.architecture) {
                # Substitute and update architecture specific property
                $Manifest.architecture | Get-Member -MemberType NoteProperty | ForEach-Object {
                    $arch = $_.Name
                    if ($Manifest.architecture.$arch.$prop -and ($Manifest.autoupdate.architecture.$arch.$prop -or $Manifest.autoupdate.$prop)) {
                        # Substitute new value
                        $newValue = Invoke-VariableSubstitution -Entity (arch_specific $prop $Manifest.autoupdate $arch) -Parameters $Substitutions

                        # Update manifest
                        $Manifest.architecture.$arch.$prop, $propertyChanged = _updateSpecificProperty -Property $Manifest.architecture.$arch.$prop -Value $newValue
                        $hasManifestChanged = $hasManifestChanged -or $propertyChanged
                    }
                }
            }
        }
    }

    end {
        if (($Version -ne '') -and ($Manifest.version -ne $Version)) {
            $Manifest.version = $Version
            $manifestChanged = $true
        }

        return $manifestChanged
    }
}

function Invoke-Autoupdate ([String] $app, $dir, $json, [String] $version, [Hashtable] $MatchesHashtable) {
    Write-Host "Autoupdating $app" -ForegroundColor DarkCyan
    $Manifest = $json
    $substitutions = Get-VersionSubstitution -Version $version -CustomMatches $MatchesHashtable

    # Get properties, which needs to be updated
    $updatedProperties = @(@($Manifest.autoupdate.PSObject.Properties.Name) -ne 'architecture')
    if ($Manifest.autoupdate.architecture) {
        $Manifest.autoupdate.architecture.PSObject.Properties | ForEach-Object {
            $updatedProperties += $_.Value.PSObject.Properties.Name
        }
    }

    # Hashes needs to be updated if not explicitly specified
    if ($updatedProperties -contains 'url') { $updatedProperties += 'hash' }

    $updatedProperties = $updatedProperties | Select-Object -Unique
    debug [$updatedProperties]

    $changed = Update-ManifestProperty -Manifest $Manifest -Property $updatedProperties -AppName $app -Version $version -Substitutions $substitutions

    if ($changed) {
        Write-UserMessage -Message "Writing updated $app manifest" -Color DarkGreen

        $path = Join-Path $dir "$app.json"
        $Manifest | ConvertToPrettyJson | Out-UTF8File -Path $path

        # Notes
        if ($json.autoupdate.note) {
            Write-UserMessage -Message '', $json.autoupdate.note -Color DarkYellow
        }
    } else {
        # This if-else branch may not be in use.
        Write-UserMessage -Message "No updates for $app" -Color DarkGray
    }
}

#region Helpers
function _updateSpecificProperty {
    <#
    .SYNOPSIS
        Helper for updating manifest's property
    .DESCRIPTION
        Updates manifest property (String, Array or PSCustomObject).
    .PARAMETER Property
        Specifies the name of property to be updated.
    .PARAMETER Value
        Specifies the new value of property.
        Update line by line.
    .OUTPUTS
        System.Object[]
            The first element is new value of property, the second element is change flag
    #>
    param (
        [ValidateNotNull()]
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Property,
        [Parameter(Mandatory)]
        [Object] $Value
    )
    begin {
        $result = $Property
        $hasChanged = $false
    }

    process {
        # Bind value into property in case the new value is "longer" than current.
        if (@($Property).Length -lt @($Value).Length) {
            $result = $Value
            $hasChanged = $true
        } else {
            switch ($Property.GetType().Name) {
                'String' {
                    $val = $Value -as [String]
                    if ($null -ne $val) {
                        $result = $val
                        $hasChanged = $true
                    }
                }
                'Object[]' {
                    $val = @($Value)
                    for ($i = 0; $i -lt $val.Length; $i++) {
                        $result[$i], $itemChanged = _updateSpecificProperty -Property $Property[$i] -Value $val[$i]
                        $hasChanged = $hasChanged -or $itemChanged
                    }
                }
                'PSCustomObject' {
                    if ($Value -is [PSObject]) {
                        foreach ($name in $Property.PSObject.Properties.Name) {
                            if ($Value.$name) {
                                $result.$name, $itemChanged = _updateSpecificProperty -Property $Property.$name -Value $Value.$name
                                $hasChanged = $hasChanged -or $itemChanged
                            }
                        }
                    }
                }
            }
        }
    }

    end { return $result, $hasChanged }
}

function _getHashesForUrls {
    <#
    .SYNOPSIS
        Helper for extracting hashes.
    .DESCRIPTION
        Extract or calculate hash(es) for provided URLs.
        If number of hash extraction templates is less then URLs, the last template will be reused for the rest URLs.
    .PARAMETER AppName
        Specifies the name of the application.
    .PARAMETER Version
        Specifies the version of the application.
    .PARAMETER HashExtraction
        Specifeis the extraction method.
    .PARAMETER URL
        Specifes the links to updated files.
    .PARAMETER Substitutions
        Specifes the hashtable with substitutions.
    #>
    param (
        [String] $AppName,
        [String] $Version,
        [PSObject[]] $HashExtraction,
        [String[]] $URL,
        [HashTable] $Substitutions
    )
    $hash = @()
    for ($i = 0; $i -lt $URL.Length; $i++) {
        if ($null -eq $HashExtraction) {
            $extract = $null
        } else {
            $extract = $HashExtraction[$i], $HashExtraction[-1] | Select-Object -First 1
        }
        $hash += get_hash_for_app $AppName $extract $Version $URL[$i] $Substitutions
        if ($null -eq $hash[$i]) {
            throw "Could not update $AppName, hash for $(url_remote_filename $URL[$i]) failed!"
        }
    }

    return $hash
}
#endregion Helpers
