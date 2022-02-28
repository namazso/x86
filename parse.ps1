[void](mkdir -Force svg)

& mutool convert -o "svg/%d.svg" -F svg "325383-sdm-vol-2abcd.pdf"

$Files = Get-ChildItem "svg";
[void](mkdir -Force svg_trim)

$Namespace = @{ svg = "http://www.w3.org/2000/svg" }

$Files | ForEach-Object {
    $CopyName = "svg_trim/$($_.BaseName).svg";
    Copy-Item -Path $_.FullName -Destination $CopyName;
    $CopyItem = Get-Item -Path $CopyName;
    $Paths = (Select-Xml -Namespace $Namespace -Path $CopyItem.FullName -XPath "/svg:svg/svg:g/svg:path") | ForEach-Object { $_.Node }
    $SelectPath2 = "";
    if (($Paths.Count -gt 0) -and ($Paths[0].fill -eq "#ffffff")) {
        $SelectPath2 = "--select=path2";
    }
    $SelectPath12 = "";
    if (($Paths.Count -gt 1) -and ($Paths[1].fill -eq "#ffffff")) {
        $SelectPath12 = "--select=path12";
    }
    # make sure inkscape version is less than 1.0
    & $env:INKSCAPE_BIN `
        --select=text6 `
        --select=text10 `
        --select=text16 `
        $SelectPath2 `
        $SelectPath12 `
        --verb=EditDelete `
        --verb=FitCanvasToDrawing `
        --verb=FileSave `
        --verb=FileClose `
        --verb=FileQuit `
        $CopyItem.FullName
}

$Instructions = @{}
$Files | ForEach-Object {
    $HeaderNameObj = Select-Xml `
        -Namespace $Namespace `
        -Path $_.FullName `
        -XPath "(/svg:svg/svg:g/svg:text/svg:tspan/text())[1]";
    if ($HeaderNameObj.Length -eq 0) {
        return;
    }
    $HeaderNameParts = $HeaderNameObj[0].Node.Value.Replace(" - ", "—").Replace(" – ", "—").Split("—");
    if ($HeaderNameParts.Count -ne 2) {
        return;
    }
    $InstructionName = $HeaderNameParts[0].Trim();
    $InstructionDesc = ($HeaderNameParts[1] -replace "[^ -~]+","" -replace "\s+"," ").Trim();
    if (-not $Instructions.ContainsKey($InstructionName)) {
        $Instructions.Add($InstructionName, @{
            Pages = [System.Collections.ArrayList]@();
            Name = $InstructionName;
            FileName = ($InstructionName -replace "[^a-zA-Z0-9]","_") + ".html";
            Description = $InstructionDesc;
        });
    }
    $Ins = $Instructions.$InstructionName;
    [void]$Ins.Pages.Add([int]$_.BaseName);
    [void]$Ins.Pages.Sort();
}

[void](mkdir -Force html)

function SHA256 {
    param(
        [Parameter(Mandatory=$true)]
        [string] $ClearString
    )

    $Hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256');
    $Hash = $Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ClearString));

    $HashString = [System.BitConverter]::ToString($hash);
    $HashString.Replace('-', '');
}

$Styles = New-Object System.Collections.Generic.HashSet[string];
$Instructions.GetEnumerator() | ForEach-Object {
    $Ins = $_.Value;
    $Content = $Ins.Pages | ForEach-Object {
        $Svg = [Xml](Get-Content "svg_trim/$_.svg");
        $Svg.DocumentElement.SelectNodes("//*[@id]") | ForEach-Object {
            $_.RemoveAttribute("id");
        }
        $Svg.DocumentElement.SelectNodes("//*[@style]") | ForEach-Object {
            $Classes = $_.style.Split(";") | ForEach-Object {
                $Style = $_.Trim();
                $Parts = $Style.Split(":") | ForEach-Object { $_.Trim() };
                if ($Parts[0] -eq "font-size" -and $Parts[1].EndsWith("px")) {
                    $Style = "font-size:{0:0.#}px" -f [double]($Parts[1] -replace "px","");
                }
                [void]$Styles.Add($Style);
                "c" + (SHA256 $Style).Substring(0, 8);
            };
            $_.RemoveAttribute("style");
            $_.SetAttribute("class", [string]::Join(" ", $Classes));
        }
        ($Svg).svg.OuterXml;
    };
    $Html = (Get-Content -Path "instruction.template.html") -f `
        ([System.Net.WebUtility]::HtmlEncode($Ins.Name)), `
        ([string]::Join("<br/><br/>", $Content));
    Set-Content -Path "html/$($Ins.FileName)" -Value $Html;
}

$HexInvertMap = New-Object "System.Collections.Generic.Dictionary[char, char]";
$HexInvertMap.Add('0', 'F');
$HexInvertMap.Add('1', 'E');
$HexInvertMap.Add('2', 'D');
$HexInvertMap.Add('3', 'C');
$HexInvertMap.Add('4', 'B');
$HexInvertMap.Add('5', 'A');
$HexInvertMap.Add('6', '9');
$HexInvertMap.Add('7', '8');
$HexInvertMap.Add('8', '7');
$HexInvertMap.Add('9', '6');
$HexInvertMap.Add('A', '5');
$HexInvertMap.Add('B', '4');
$HexInvertMap.Add('C', '3');
$HexInvertMap.Add('D', '2');
$HexInvertMap.Add('E', '1');
$HexInvertMap.Add('F', '0');
$HexInvertMap.Add('a', '5');
$HexInvertMap.Add('b', '4');
$HexInvertMap.Add('c', '3');
$HexInvertMap.Add('d', '2');
$HexInvertMap.Add('e', '1');
$HexInvertMap.Add('f', '0');

$Styles | Sort-Object | ForEach-Object {
    $ClassName = "c" + (SHA256 $_).Substring(0, 8);
    ".$ClassName { $_ }"
    $Parts = $_.Split(":") | ForEach-Object { $_.Trim() };
    if ($Parts.Count -eq 2 -and $Parts[1].StartsWith("#")) {
        $Attribute = $Parts[0];
        $Inverted = [string]::Join("", ($Parts[1].ToCharArray() | ForEach-Object {
            if ($HexInvertMap.ContainsKey($_)) {
                $HexInvertMap[$_];
            } else {
                $_;
            }
        }));
        "@media (prefers-color-scheme: dark) { .$ClassName { $($Attribute):$Inverted }}";
    }
} > "html/styles.css"

$InstructionsSorted = ($Instructions.GetEnumerator() | Sort-Object -Property "Name");

$TableRows = $InstructionsSorted | ForEach-Object { 
    $NameEnc = $([System.Net.WebUtility]::HtmlEncode($_.Name));
    $DescEnc = $([System.Net.WebUtility]::HtmlEncode($_.Value.Description));
    $Link = "html/" + $_.Value.FileName;
    "<tr><td><a href=`"$Link`">$NameEnc</a></td><td>$DescEnc</td></tr>`n"; 
  };

$IndexHtml = (Get-Content -Path "index.template.html") -f ([string]::Join("", $TableRows));
Set-Content -Path "index.html" -Value $IndexHtml;

$InstructionList = $InstructionsSorted | ForEach-Object { 
    $NameEnc = $([System.Net.WebUtility]::HtmlEncode($_.Name));
    $Link = "html/" + $_.Value.FileName;
    "<a href=`"$Link`" target=`"main_frame`">$NameEnc</a>"; 
  };

$FrameLeftHtml = (Get-Content -Path "frame_left.template.html") -f ([string]::Join("<br/>`n", $InstructionList));
Set-Content -Path "frame_left.html" -Value $FrameLeftHtml;

