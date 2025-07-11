using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace GrepSQL
{
    internal static class NativeLibraryLoader
    {
        private static bool _loaded = false;
        private static readonly object _lock = new object();

        public static void EnsureLoaded()
        {
            if (_loaded) return;

            lock (_lock)
            {
                if (_loaded) return;

                try
                {
                    var assemblyLocation = Assembly.GetExecutingAssembly().Location;
                    var assemblyDirectory = Path.GetDirectoryName(assemblyLocation);

                    // More robust runtime identification
                    var rid = GetRuntimeIdentifier();
                    var libraryName = GetLibraryFileName();

                    // First try: runtimes/{rid}/native/{library}
                    var libraryPath = Path.Combine(assemblyDirectory ?? "", "runtimes", rid, "native", libraryName);

                    if (!File.Exists(libraryPath))
                    {
                        // Second try: fallback to generic names
                        var fallbackRids = GetFallbackRids(rid);
                        foreach (var fallbackRid in fallbackRids)
                        {
                            libraryPath = Path.Combine(assemblyDirectory ?? "", "runtimes", fallbackRid, "native", libraryName);
                            if (File.Exists(libraryPath)) break;
                        }
                    }

                    if (!File.Exists(libraryPath))
                    {
                        // Third try: next to assembly
                        libraryPath = Path.Combine(assemblyDirectory ?? "", libraryName);
                    }

                    if (!File.Exists(libraryPath))
                    {
                        throw new FileNotFoundException($"Library not found. Tried: {libraryPath}");
                    }

                    var handle = LoadLibrary(libraryPath);

                    _loaded = true;
                }
                catch (Exception ex)
                {
                    throw new DllNotFoundException($"Failed to load native library: {ex.Message}", ex);
                }
            }
        }

        private static string GetRuntimeIdentifier()
        {
            var rid = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "win-" :
                     RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? "linux-" :
                     RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "osx-" : "any-";

            rid += RuntimeInformation.ProcessArchitecture switch
            {
                Architecture.X64 => "x64",
                Architecture.X86 => "x86",
                Architecture.Arm64 => "arm64",
                Architecture.Arm => "arm",
                _ => "x64"
            };

            return rid;
        }

        private static string[] GetFallbackRids(string primaryRid)
        {
            // Handle M1 Mac fallback
            if (primaryRid == "osx-arm64")
                return new[] { "osx-x64", "osx-arm64" };

            if (primaryRid.StartsWith("linux-"))
                return new[] { "linux-x64", primaryRid };

            if (primaryRid.StartsWith("win-"))
                return new[] { "win-x64", "win-x86", primaryRid };

            return new[] { primaryRid };
        }

        private static string GetLibraryFileName()
        {
            // Look for both wrapper and direct libpg_query
            var baseName = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "libpgquery_wrapper.dll" :
                          RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? "libpgquery_wrapper.so" :
                          "libpgquery_wrapper.dylib";
            return baseName;
        }

        private static IntPtr LoadLibrary(string path)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                return LoadLibraryWindows(path);
            }
            else
            {
                // RTLD_NOW | RTLD_GLOBAL = 2 | 8 = 10
                var handle = dlopen(path, 10);
                if (handle == IntPtr.Zero)
                {
                    // Get detailed error message from dlerror
                    var errorPtr = dlerror();
                    var error = errorPtr != IntPtr.Zero ? Marshal.PtrToStringUTF8(errorPtr) : "Unknown dlopen error";
                    throw new DllNotFoundException($"Failed to load library from {path}. Error: {error}");
                }
                return handle;
            }
        }

        [DllImport("kernel32.dll", EntryPoint = "LoadLibraryW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr LoadLibraryWindows(string lpFileName);

        [DllImport("libdl", CharSet = CharSet.Ansi)]
        private static extern IntPtr dlopen(string filename, int flags);

        [DllImport("libdl")]
        private static extern IntPtr dlerror();
    }
}