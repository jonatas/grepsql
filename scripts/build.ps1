# PgQuery.NET Build Script for Windows
# Requires: Visual Studio Build Tools, Git, .NET SDK, Protocol Buffers compiler

param(
    [switch]$SkipNative,
    [switch]$SkipProtobuf,
    [switch]$SkipBuild,
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "🏗️  Building PgQuery.NET with libpg_query (Windows)" -ForegroundColor Green

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Configuration
$LibPgQueryBranch = "17-latest"
$LibPgQueryRepo = "https://github.com/pganalyze/libpg_query.git"
$TargetRid = "win-x64"

Set-Location $ProjectRoot

# Step 1: Check prerequisites
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow

# Check for Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is required but not found in PATH"
    exit 1
}

# Check for .NET SDK
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error ".NET SDK is required but not found in PATH"
    exit 1
}

# Check for Visual Studio Build Tools
$MSBuildPaths = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
)

$MSBuild = $null
foreach ($path in $MSBuildPaths) {
    if (Test-Path $path) {
        $MSBuild = $path
        break
    }
}

if (-not $MSBuild) {
    Write-Warning "⚠️  MSBuild not found. Native library compilation may fail."
    Write-Host "Please install Visual Studio Build Tools 2019 or later"
}

# Step 2: Clone and prepare libpg_query
if (-not $SkipNative) {
    Write-Host "📥 Setting up libpg_query..." -ForegroundColor Yellow
    
    if (-not (Test-Path "libpg_query")) {
        Write-Host "Cloning libpg_query (branch: $LibPgQueryBranch)..."
        & git clone -b $LibPgQueryBranch $LibPgQueryRepo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } else {
        Write-Host "libpg_query already exists, updating..."
        Set-Location libpg_query
        & git fetch origin
        & git checkout $LibPgQueryBranch
        & git pull origin $LibPgQueryBranch
        Set-Location ..
    }

    # Build libpg_query using Windows Makefile
    Write-Host "🔨 Building libpg_query for Windows..." -ForegroundColor Yellow
    Set-Location libpg_query
    
    if ($MSBuild) {
        # Try to build with Visual Studio
        if (Test-Path "Makefile.msvc") {
            Write-Host "Using Visual Studio tools..."
            & nmake /F Makefile.msvc clean
            & nmake /F Makefile.msvc
        } else {
            Write-Warning "Makefile.msvc not found, trying alternative approach..."
            # Fallback: try to use make with WSL or similar
            if (Get-Command make -ErrorAction SilentlyContinue) {
                & make clean
                & make
            } else {
                Write-Error "Cannot build libpg_query. Please install Visual Studio Build Tools or WSL."
                exit 1
            }
        }
    }
    
    Set-Location $ProjectRoot
}

# Step 3: Create runtime directories and copy libraries
if (-not $SkipNative) {
    Write-Host "📁 Setting up runtime directories..." -ForegroundColor Yellow
    
    $RuntimeDir = "runtimes\$TargetRid\native"
    New-Item -Path $RuntimeDir -ItemType Directory -Force | Out-Null
    
    # Copy libraries (both .dll and .lib if they exist)
    $LibraryFiles = @("libpg_query.dll", "libpg_query.lib", "libpgquery_wrapper.dll", "pg_query.dll")
    
    foreach ($lib in $LibraryFiles) {
        if (Test-Path "libpg_query\$lib") {
            Write-Host "Copying $lib to $RuntimeDir"
            Copy-Item "libpg_query\$lib" $RuntimeDir -Force
        }
    }
    
    # Also copy to project runtimes directory
    $ProjectRuntimeDir = "src\PgQuery.NET\runtimes\$TargetRid\native"
    New-Item -Path $ProjectRuntimeDir -ItemType Directory -Force | Out-Null
    
    foreach ($lib in $LibraryFiles) {
        if (Test-Path "libpg_query\$lib") {
            Copy-Item "libpg_query\$lib" $ProjectRuntimeDir -Force
        }
    }
}

# Step 4: Generate protobuf files
if (-not $SkipProtobuf) {
    Write-Host "🔧 Generating protobuf files..." -ForegroundColor Yellow
    
    # Check for protoc
    $ProtocPath = Get-Command protoc -ErrorAction SilentlyContinue
    if (-not $ProtocPath) {
        Write-Warning "⚠️  protoc not found. Attempting to install via dotnet tool..."
        & dotnet tool install --global protobuf-net.Protogen --version 3.2.26
        
        # Try again
        $ProtocPath = Get-Command protoc -ErrorAction SilentlyContinue
        if (-not $ProtocPath) {
            Write-Error "❌ Could not find or install protoc. Please install Protocol Buffers compiler manually."
            exit 1
        }
    }
    
    # Add Grpc.Tools if not present
    $GrpcToolsPath = "$env:USERPROFILE\.nuget\packages\grpc.tools"
    if (-not (Test-Path $GrpcToolsPath)) {
        Write-Host "Installing Grpc.Tools..."
        & dotnet add "src\PgQuery.NET" package Grpc.Tools --version 2.72.0
    }
    
    # Find the latest version and appropriate platform tools
    $LatestVersion = Get-ChildItem $GrpcToolsPath | Sort-Object Name -Descending | Select-Object -First 1
    $PluginPath = "$($LatestVersion.FullName)\tools\windows_x64"
    
    if (-not (Test-Path $PluginPath)) {
        $PluginPath = "$($LatestVersion.FullName)\tools\windows_x86"
    }
    
    $env:PATH = "$env:PATH;$PluginPath"
    
    # Generate protobuf files
    $ProtoSrc = "libpg_query\protobuf"
    $ProtoOut = "src\PgQuery.NET\AST\Generated"
    
    New-Item -Path $ProtoOut -ItemType Directory -Force | Out-Null
    
    # Clean previous files
    Get-ChildItem "$ProtoOut\*.cs" -ErrorAction SilentlyContinue | Remove-Item -Force
    
    Write-Host "Generating C# protobuf classes..."
    & protoc --proto_path="$ProtoSrc" --csharp_out="$ProtoOut" --csharp_opt=file_extension=.g.cs "$ProtoSrc\pg_query.proto"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Protobuf generation failed"
        exit $LASTEXITCODE
    }
    
    # Verify generated files
    if (-not (Test-Path "$ProtoOut\PgQuery.g.cs")) {
        Write-Error "❌ Expected protobuf files not generated"
        exit 1
    }
    
    Write-Host "✅ Protobuf generation completed" -ForegroundColor Green
}

# Step 5: Build .NET project
if (-not $SkipBuild) {
    Write-Host "🔨 Building .NET project..." -ForegroundColor Yellow
    
    & dotnet restore
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    
    & dotnet build --configuration $Configuration --verbosity minimal
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Build failed"
        exit $LASTEXITCODE
    }
    
    Write-Host "✅ Build completed successfully" -ForegroundColor Green
    
    # Run tests if they exist
    if (Test-Path "tests\PgQuery.NET.Tests.csproj") {
        Write-Host "🧪 Running tests..." -ForegroundColor Yellow
        & dotnet test --configuration $Configuration --verbosity minimal
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "⚠️  Tests failed"
        }
    }
    
    # Create NuGet package
    Write-Host "📦 Creating NuGet package..." -ForegroundColor Yellow
    New-Item -Path "artifacts" -ItemType Directory -Force | Out-Null
    & dotnet pack "src\PgQuery.NET" --configuration $Configuration --output "artifacts"
}

Write-Host ""
Write-Host "🎉 Build completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Build Summary:" -ForegroundColor Cyan
Write-Host "  Target RID: $TargetRid"
Write-Host "  Configuration: $Configuration"

if (Test-Path "runtimes\$TargetRid\native") {
    Write-Host "  Generated Libraries:"
    Get-ChildItem "runtimes\$TargetRid\native" | ForEach-Object { Write-Host "    $($_.Name)" }
}

if (Test-Path "src\PgQuery.NET\AST\Generated") {
    Write-Host "  Generated Protobuf Files:"
    Get-ChildItem "src\PgQuery.NET\AST\Generated\*.cs" | ForEach-Object { Write-Host "    $($_.Name)" }
}

if (Test-Path "artifacts") {
    Write-Host "  NuGet Packages:"
    Get-ChildItem "artifacts\*.nupkg" | ForEach-Object { Write-Host "    $($_.Name)" }
} 