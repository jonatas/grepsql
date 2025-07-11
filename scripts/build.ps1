# GrepSQL Build Script for Windows
# Requires: Visual Studio Build Tools, Git, .NET SDK, Protocol Buffers compiler

param(
    [switch]$SkipNative,
    [switch]$SkipProtobuf,
    [switch]$SkipBuild,
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "🏗️  Building GrepSQL with libpg_query (Windows)" -ForegroundColor Green

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Configuration
$LibPgQueryBranch = "17-latest"
$LibPgQueryRepo = "https://github.com/pganalyze/libpg_query.git"
$TargetRid = "win-x64" # Crucial for native compilation and .NET builds

Set-Location $ProjectRoot

# Step 1: Check prerequisites
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is required but not found in PATH"; exit 1
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error ".NET SDK is required but not found in PATH"; exit 1
}

# Step 2: Clone and prepare libpg_query
if (-not $SkipNative) {
    Write-Host "📥 Setting up libpg_query..." -ForegroundColor Yellow
    
    if (-not (Test-Path "libpg_query")) {
        Write-Host "Cloning libpg_query (branch: $LibPgQueryBranch)..."
        & git clone -b $LibPgQueryBranch $LibPgQueryRepo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    else {
        Write-Host "libpg_query already exists, updating..."
        Set-Location libpg_query
        & git fetch origin
        & git checkout $LibPgQueryBranch
        & git pull origin $LibPgQueryBranch
        Set-Location ..
    }

    Write-Host "🔨 Building libpg_query for Windows..." -ForegroundColor Yellow
    Set-Location libpg_query
    
    if (Test-Path "Makefile.msvc") {
        Write-Host "Using Visual Studio tools (nmake)..."
        & nmake /F Makefile.msvc clean
        & nmake /F Makefile.msvc
    }
    else {
        Write-Error "Makefile.msvc not found in libpg_query. Cannot proceed with Windows build."
        exit 1
    }
    
    Set-Location $ProjectRoot

    # Step 2b: Build wrapper library
    Write-Host "🔧 Building wrapper library..." -ForegroundColor Yellow
    
    Write-Host "🧹 Cleaning up old build artifacts..."
    Remove-Item -Path "wrapper.c", "wrapper.def", "libpgquery_wrapper.dll" -ErrorAction SilentlyContinue

    $WrapperPath = Join-Path $ProjectRoot "wrapper.c"
    $DefPath = Join-Path $ProjectRoot "wrapper.def"

    Write-Host "Creating wrapper.c with exported functions..." 
    @"
#include "libpg_query/pg_query.h"
#define EXPORT __declspec(dllexport)
#define STDCALL __stdcall

EXPORT PgQueryProtobufParseResult STDCALL pg_query_parse_protobuf_wrapper(const char* input) { return pg_query_parse_protobuf(input); }
EXPORT void STDCALL pg_query_free_protobuf_parse_result_wrapper(PgQueryProtobufParseResult result) { pg_query_free_protobuf_parse_result(result); }
EXPORT PgQueryParseResult STDCALL pg_query_parse_wrapper(const char* input) { return pg_query_parse(input); }
EXPORT void STDCALL pg_query_free_parse_result_wrapper(PgQueryParseResult result) { pg_query_free_parse_result(result); }
EXPORT PgQueryNormalizeResult STDCALL pg_query_normalize_wrapper(const char* input) { return pg_query_normalize(input); }
EXPORT void STDCALL pg_query_free_normalize_result_wrapper(PgQueryNormalizeResult result) { pg_query_free_normalize_result(result); }
"@ | Set-Content -Path $WrapperPath -Encoding Ascii


    Write-Host "Creating wrapper.def to export functions..."
    @"
EXPORTS
    pg_query_parse_protobuf_wrapper
    pg_query_free_protobuf_parse_result_wrapper
    pg_query_parse_wrapper
    pg_query_free_parse_result_wrapper
    pg_query_normalize_wrapper
    pg_query_free_normalize_result_wrapper
"@ | Set-Content -Path $DefPath -Encoding Ascii

    $ClPath = Get-Command cl.exe -ErrorAction SilentlyContinue
    if (-not $ClPath) { Write-Error "cl.exe not found. Ensure Visual Studio Build Tools are installed and vcvars are loaded."; exit 1 }

    & $ClPath /nologo /LD /I "libpg_query" $WrapperPath "libpg_query\pg_query.lib" /DEF:$DefPath /link /OUT:libpgquery_wrapper.dll
    if ($LASTEXITCODE -ne 0) { Write-Error "❌ Failed to compile wrapper library"; exit $LASTEXITCODE }
}

# Step 3: Place native library for the .NET SDK and NuGet packaging
if (-not $SkipNative) {
    Write-Host "📁 Placing native library for .NET SDK..." -ForegroundColor Yellow
    $ProjectRuntimeDir = "src\GrepSQL\runtimes\$TargetRid\native"
    New-Item -Path $ProjectRuntimeDir -ItemType Directory -Force | Out-Null
    
    $sourceDll = "libpgquery_wrapper.dll"
    if (Test-Path $sourceDll) {
        Copy-Item $sourceDll $ProjectRuntimeDir -Force
        Write-Host "✅ Copied $sourceDll to $ProjectRuntimeDir" -ForegroundColor Green
    }
    else {
        Write-Error "❌ Could not find compiled $sourceDll in project root."
    }
}


# Step 4: Generate protobuf files
if (-not $SkipProtobuf) {
    Write-Host "🔧 Generating protobuf files..." -ForegroundColor Yellow
    if (-not (Get-Command protoc -ErrorAction SilentlyContinue)) {
        Write-Warning "⚠️  protoc not found. Please ensure it's installed and in the PATH."
    }
    if (-not (Test-Path "$env:USERPROFILE\.nuget\packages\grpc.tools")) {
        Write-Host "Installing Grpc.Tools NuGet package..."
        & dotnet add "src\GrepSQL" package Grpc.Tools
    }
    
    $ProtoSrc = "libpg_query\protobuf"
    $ProtoOut = "src\GrepSQL\AST\Generated"
    New-Item -Path $ProtoOut -ItemType Directory -Force | Out-Null
    
    Write-Host "Generating C# protobuf classes..."
    & protoc --proto_path="$ProtoSrc" --csharp_out="$ProtoOut" --csharp_opt=file_extension=.g.cs "$ProtoSrc\pg_query.proto"
    if ($LASTEXITCODE -ne 0) { Write-Error "❌ Protobuf generation failed"; exit $LASTEXITCODE }
    if (-not (Test-Path "$ProtoOut\PgQuery.g.cs")) { Write-Error "❌ Expected protobuf files not generated"; exit 1 }
    Write-Host "✅ Protobuf generation completed" -ForegroundColor Green
}

# Step 5: Build and Test .NET project
if (-not $SkipBuild) {
    Write-Host "🔨 Building .NET projects for runtime $TargetRid..." -ForegroundColor Yellow

    # Build the test project. This will automatically build the main project (its dependency)
    # with the correct runtime context, avoiding solution platform errors.
    $buildArgs = @(
        "build",
        "tests\GrepSQL.Tests\GrepSQL.Tests.csproj",
        "--configuration", $Configuration,
        "--runtime", $TargetRid
    )
    & dotnet @buildArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "❌ Build failed"; exit $LASTEXITCODE }
    
    Write-Host "✅ Build completed successfully" -ForegroundColor Green
    
    if (Test-Path "tests\GrepSQL.Tests.csproj") {
        Write-Host "🧪 Running tests for runtime $TargetRid..." -ForegroundColor Yellow
        
        # Test with --no-build as the projects were just built.
        # This ensures we test the exact artifacts from the previous step.
        $testArgs = @(
            "test",
            "tests\GrepSQL.Tests\GrepSQL.Tests.csproj",
            "--configuration", $Configuration,
            "--runtime", $TargetRid,
            "--no-build",
            "--verbosity", "normal"
        )
        & dotnet @testArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Tests failed. Please review the output."
            exit $LASTEXITCODE
        }
    }

    Write-Host "✅ Tests passed successfully!" -ForegroundColor Green
    
    Write-Host "📦 Creating NuGet package..." -ForegroundColor Yellow
    New-Item -Path "artifacts" -ItemType Directory -Force | Out-Null
    $packArgs = @(
        "pack",
        "src\GrepSQL\GrepSQL.csproj",
        "--configuration", $Configuration,
        "--output", "artifacts",
        "--no-build" # We've already built, just pack the results.
    )
    & dotnet @packArgs
}

Write-Host ""
Write-Host "🎉 Build process completed successfully!" -ForegroundColor Green