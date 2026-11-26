<#
.SYNOPSIS
    Verifica los shaders del repo en un solo paso / Checks the repo's shaders in one step.

.DESCRIPTION
    1. Compila cada shader con fxc (ps_5_0), con una cabecera que imita lo que obs-shaderfilter
       declara antes del shader (image, uv_size, elapsed_time...). Así se detectan errores de sintaxis
       y de tipos sin abrir OBS. Los avisos X3570 son normales.
    2. Compara el código en español con el de en/, quitando comentarios y textos: deben ser idénticos.

    Compiles every shader with fxc and verifies that the Spanish and English code is identical apart
    from comments and strings.

.EXAMPLE
    pwsh tools/check.ps1
#>
[CmdletBinding()]
param(
    # Ruta a fxc.exe; por defecto busca el Windows SDK más reciente / Defaults to the newest Windows SDK
    [string]$Fxc
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failed = 0

function Write-Result([string]$name, [bool]$ok, [string]$detail = '') {
    $mark = if ($ok) { '[ OK ]' } else { '[FAIL]' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host "$mark " -ForegroundColor $color -NoNewline
    Write-Host $name -NoNewline
    if ($detail) { Write-Host "  $detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

# Pares español / inglés que deben tener el mismo código
$pairs = @(
    @('glitch.shader', 'en/glitch.shader'),
    @('trazo-de-luz.shader', 'en/light-trace.shader'),
    @('gargantua.shader', 'en/gargantua.shader')
)
$shaders = $pairs | ForEach-Object { $_ }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "obs-modern-tv-check-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null

try {
    # ---------------------------------------------------------------- 1. Shaders
    Write-Host "`nShaders (fxc)" -ForegroundColor Cyan
    if (-not $Fxc) {
        $kits = 'C:\Program Files (x86)\Windows Kits\10\bin'
        $Fxc = Get-ChildItem $kits -Directory -Filter '10.*' -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\fxc.exe' } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Fxc -or -not (Test-Path $Fxc)) {
        Write-Result 'fxc.exe' $false 'no encontrado: instala el Windows SDK o usa -Fxc <ruta>'
        $failed++
    } else {
        # Lo que obs-shaderfilter declara antes del texto del shader
        $header = @'
Texture2D image; SamplerState textureSampler;
float2 uv_size; float2 uv_pixel_interval; float elapsed_time;
struct VertData { float4 pos : SV_Position; float2 uv : TEXCOORD0; };
#define texture2d Texture2D
#define TARGET SV_Target
'@
        foreach ($s in $shaders) {
            $src = Join-Path $root $s
            if (-not (Test-Path $src)) { Write-Result $s $false 'no existe'; $failed++; continue }
            $hlsl = Join-Path $tmp (($s -replace '[\\/]', '_') + '.hlsl')
            Set-Content $hlsl ($header + "`n" + (Get-Content $src -Raw)) -Encoding utf8
            $out = & $Fxc /nologo /T ps_5_0 /E mainImage /Fo (Join-Path $tmp 'out.cso') $hlsl 2>&1 | Out-String
            $errors = @($out -split "`r?`n" | Where-Object { $_ -match 'error X\d+' })
            $ok = ($LASTEXITCODE -eq 0) -and ($errors.Count -eq 0)
            Write-Result $s $ok
            if (-not $ok) {
                $failed++
                # fxc cuenta las líneas de la cabecera; se restan para apuntar a la línea real del .shader
                $offset = ($header -split "`n").Count
                $errors | ForEach-Object {
                    $msg = [regex]::Replace($_, [regex]::Escape($hlsl) + '\((\d+)', {
                            param($m) "$s($([int]$m.Groups[1].Value - $offset)" })
                    Write-Host "       $msg" -ForegroundColor Red
                }
            }
        }
    }

    # ---------------------------------------------------------------- 2. Paridad ES / EN
    Write-Host "`nEspañol = inglés (sin comentarios ni textos)" -ForegroundColor Cyan
    # Una sola pasada de izquierda a derecha: lo que aparece primero gana, para que un apóstrofo
    # dentro de un comentario no se tome como inicio de una cadena.
    $tokens = [regex]::new('(?<c>/\*.*?\*/)|(?<c>//[^\r\n]*)|(?<s>"(?:\\.|[^"\\\r\n])*")', 'Singleline')
    function Get-CodeLines([string]$path) {
        $t = $tokens.Replace((Get-Content $path -Raw), {
                param($m) if ($m.Groups['c'].Success) { '' } else { '""' } })
        $t -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    foreach ($p in $pairs) {
        $pa = Join-Path $root $p[0]; $pb = Join-Path $root $p[1]
        if (-not ((Test-Path $pa) -and (Test-Path $pb))) { Write-Result "$($p[0])  =  $($p[1])" $false 'falta un archivo'; $failed++; continue }
        $diff = @(Compare-Object @(Get-CodeLines $pa) @(Get-CodeLines $pb) -SyncWindow 0)
        $ok = $diff.Count -eq 0
        Write-Result "$($p[0])  =  $($p[1])" $ok
        if (-not $ok) {
            $failed++
            $diff | Select-Object -First 6 | ForEach-Object {
                $side = if ($_.SideIndicator -eq '<=') { $p[0] } else { $p[1] }
                Write-Host "       $side`: $($_.InputObject)" -ForegroundColor Red
            }
        }
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failed) {
    Write-Host "$failed problema(s) / problem(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'Todo bien / All good' -ForegroundColor Green
exit 0
