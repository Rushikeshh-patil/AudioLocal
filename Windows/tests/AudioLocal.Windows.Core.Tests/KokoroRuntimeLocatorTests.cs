using System.IO.Compression;
using AudioLocal.Windows.Core.Models;
using AudioLocal.Windows.Core.Services;

namespace AudioLocal.Windows.Core.Tests;

public sealed class KokoroRuntimeLocatorTests
{
    private readonly KokoroRuntimeLocator locator = new();

    [Fact]
    public void AutoModePrefersCudaFirstWhenNvidiaIsPresent()
    {
        var result = locator.ResolveCandidateOrder(
            AccelerationMode.Auto,
            lastKnownGoodBackend: null,
            [new GpuAdapterInfo("NVIDIA GeForce RTX 4090", IsNvidia: true, IsSoftwareAdapter: false)]);

        Assert.Equal(
            [ResolvedLocalBackend.Cuda, ResolvedLocalBackend.DirectML, ResolvedLocalBackend.Cpu],
            result);
    }

    [Fact]
    public void AutoModePrefersDirectMLFirstForNonNvidiaHardware()
    {
        var result = locator.ResolveCandidateOrder(
            AccelerationMode.Auto,
            lastKnownGoodBackend: null,
            [new GpuAdapterInfo("AMD Radeon 780M", IsNvidia: false, IsSoftwareAdapter: false)]);

        Assert.Equal(
            [ResolvedLocalBackend.DirectML, ResolvedLocalBackend.Cuda, ResolvedLocalBackend.Cpu],
            result);
    }

    [Fact]
    public void LastKnownGoodBackendStaysFirstWithoutDuplicates()
    {
        var result = locator.ResolveCandidateOrder(
            AccelerationMode.Auto,
            ResolvedLocalBackend.DirectML,
            [new GpuAdapterInfo("AMD Radeon 780M", IsNvidia: false, IsSoftwareAdapter: false)]);

        Assert.Equal(
            [ResolvedLocalBackend.DirectML, ResolvedLocalBackend.Cuda, ResolvedLocalBackend.Cpu],
            result);
    }

    [Fact]
    public void TryResolveRuntimeExtractsBundledArchiveIntoLocalRuntimeRoot()
    {
        var originalCpuPython = Environment.GetEnvironmentVariable("AUDIOLOCAL_KOKORO_CPU_PYTHON");
        Environment.SetEnvironmentVariable("AUDIOLOCAL_KOKORO_CPU_PYTHON", null);

        var tempRoot = Path.Combine(Path.GetTempPath(), "AudioLocal-Tests", Guid.NewGuid().ToString("N"));
        var appBase = Path.Combine(tempRoot, "App");
        var localRuntimeRoot = Path.Combine(tempRoot, "LocalRuntimes");
        Directory.CreateDirectory(Path.Combine(appBase, "Runtime"));
        Directory.CreateDirectory(Path.Combine(appBase, "RuntimeArchives"));
        File.WriteAllText(Path.Combine(appBase, "Runtime", "kokoro_windows.py"), "# helper");

        var stagingRoot = Path.Combine(tempRoot, "Staging");
        var runtimeSource = Path.Combine(stagingRoot, "KokoroCpu");
        Directory.CreateDirectory(Path.Combine(runtimeSource, "Scripts"));
        File.WriteAllText(Path.Combine(runtimeSource, "Scripts", "python.exe"), "fake python");

        var archivePath = Path.Combine(appBase, "RuntimeArchives", "KokoroCpu.zip");
        ZipFile.CreateFromDirectory(runtimeSource, archivePath, CompressionLevel.Optimal, includeBaseDirectory: false);

        try
        {
            var runtimeLocator = new KokoroRuntimeLocator(appBase, localRuntimeRoot);

            var resolved = runtimeLocator.TryResolveRuntime(ResolvedLocalBackend.Cpu, out var runtime);

            Assert.True(resolved);
            Assert.Equal(Path.Combine(localRuntimeRoot, "KokoroCpu", "Scripts", "python.exe"), runtime.PythonExecutable);
            Assert.Equal(Path.Combine(appBase, "Runtime", "kokoro_windows.py"), runtime.HelperScript);
            Assert.True(File.Exists(runtime.PythonExecutable));
        }
        finally
        {
            Environment.SetEnvironmentVariable("AUDIOLOCAL_KOKORO_CPU_PYTHON", originalCpuPython);
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }
}
