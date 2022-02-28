[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Path
)

[void](mkdir -Force $Path);

Copy-Item -Path @(
    "html",
    "font",
    "index.html",
    "frame.html",
    "frame_left.html",
    "intel.css",
    "favicon.ico"
    ) -Recurse -Destination $Path;
