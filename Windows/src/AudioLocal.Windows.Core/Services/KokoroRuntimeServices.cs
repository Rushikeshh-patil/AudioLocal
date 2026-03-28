using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Text.Json;
using System.Threading;
using AudioLocal.Windows.Core.Infrastructure;
using AudioLocal.Windows.Core.Models;

namespace AudioLocal.Windows.Core.Services;

public sealed record KokoroHelperMetadata(string DeviceLabel, string BackendLabel);

public sealed record KokoroRuntimeUpdate(
    string Phase,
    string Message,
    ResolvedLocalBackend? Backend = null,
    string? RuntimePythonPath = null,
    string? HelperScriptPath = null,
    string? WorkingDirectory = null,
    int? WorkerProcessId = null,
    IReadOnlyList<ResolvedLocalBackend>? CandidateOrder = null);

public static class KokoroHelperOutputParser
{
    private static readonly JsonSerializerOptions ParserOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static KokoroHelperMetadata Parse(string stdoutText)
    {
        ArgumentNullException.ThrowIfNull(stdoutText);

        foreach (var line in stdoutText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Reverse())
        {
            var candidate = line.Trim().TrimStart('\uFEFF');
            if (!candidate.StartsWith('{') || !candidate.EndsWith('}'))
            {
                continue;
            }

            try
            {
                return JsonSerializer.Deserialize<KokoroHelperMetadata>(candidate, ParserOptions) ??
                    throw new InvalidOperationException("The Kokoro helper returned empty metadata.");
            }
            catch (JsonException)
            {
                // Keep scanning for the last valid JSON line.
            }
        }

        var trimmed = stdoutText.Trim().TrimStart('\uFEFF');
        if (!string.IsNullOrWhiteSpace(trimmed) && trimmed.StartsWith('{') && trimmed.EndsWith('}'))
        {
            try
            {
                return JsonSerializer.Deserialize<KokoroHelperMetadata>(trimmed, ParserOptions) ??
                    throw new InvalidOperationException("The Kokoro helper returned empty metadata.");
            }
            catch (JsonException exception)
            {
                throw new InvalidOperationException("The Kokoro helper returned unreadable metadata.", exception);
            }
        }

        throw new InvalidOperationException("The Kokoro helper returned no metadata.");
    }
}

public sealed record KokoroRuntimePath(ResolvedLocalBackend Backend, string PythonExecutable, string HelperScript);

public sealed class KokoroRuntimeLocator
{
    private static readonly SemaphoreSlim RuntimeExtractionGate = new(1, 1);
    private readonly string applicationBaseDirectory;
    private readonly string localRuntimeRoot;

    public KokoroRuntimeLocator(string? applicationBaseDirectory = null, string? localRuntimeRoot = null)
    {
        this.applicationBaseDirectory = applicationBaseDirectory ?? AppContext.BaseDirectory;
        this.localRuntimeRoot = localRuntimeRoot ?? Path.Combine(WindowsPaths.AppDataRoot, "Runtimes");
    }

    public bool TryResolveRuntime(ResolvedLocalBackend backend, out KokoroRuntimePath runtime)
    {
        var envName = backend switch
        {
            ResolvedLocalBackend.Cuda => "AUDIOLOCAL_KOKORO_CUDA_PYTHON",
            ResolvedLocalBackend.DirectML => "AUDIOLOCAL_KOKORO_DIRECTML_PYTHON",
            _ => "AUDIOLOCAL_KOKORO_CPU_PYTHON"
        };

        var helper = ResolveHelperScript();
        var envPython = Environment.GetEnvironmentVariable(envName);
        if (!string.IsNullOrWhiteSpace(envPython) && File.Exists(envPython) && helper is not null)
        {
            runtime = new KokoroRuntimePath(backend, envPython, helper);
            return true;
        }

        var rootName = backend switch
        {
            ResolvedLocalBackend.Cuda => "KokoroCuda",
            ResolvedLocalBackend.DirectML => "KokoroDirectML",
            _ => "KokoroCpu"
        };

        var python = FindPythonExecutable(Path.Combine(applicationBaseDirectory, "Runtimes", rootName)) ??
            FindPythonExecutable(Path.Combine(localRuntimeRoot, rootName));
        if (python is null && EnsureBundledRuntimeExtracted(rootName))
        {
            python = FindPythonExecutable(Path.Combine(localRuntimeRoot, rootName));
        }

        if (!string.IsNullOrWhiteSpace(python) && helper is not null)
        {
            runtime = new KokoroRuntimePath(backend, python, helper);
            return true;
        }

        runtime = null!;
        return false;
    }

    public IReadOnlyList<ResolvedLocalBackend> ResolveCandidateOrder(
        AccelerationMode accelerationMode,
        ResolvedLocalBackend? lastKnownGoodBackend,
        GpuProbe gpuProbe) =>
        ResolveCandidateOrder(accelerationMode, lastKnownGoodBackend, gpuProbe.GetAdapters());

    public IReadOnlyList<ResolvedLocalBackend> ResolveCandidateOrder(
        AccelerationMode accelerationMode,
        ResolvedLocalBackend? lastKnownGoodBackend,
        IReadOnlyList<GpuAdapterInfo> adapters)
    {
        var ordered = new List<ResolvedLocalBackend>();

        if (lastKnownGoodBackend is not null)
        {
            ordered.Add(lastKnownGoodBackend.Value);
        }

        switch (accelerationMode)
        {
        case AccelerationMode.Cuda:
            ordered.Add(ResolvedLocalBackend.Cuda);
            break;
        case AccelerationMode.DirectML:
            ordered.Add(ResolvedLocalBackend.DirectML);
            break;
        case AccelerationMode.Cpu:
            ordered.Add(ResolvedLocalBackend.Cpu);
            break;
        default:
            var hasNvidiaAdapter = adapters.Any(static adapter => adapter.IsNvidia && !adapter.IsSoftwareAdapter);
            var hasAnyHardwareAdapter = adapters.Any(static adapter => !adapter.IsSoftwareAdapter);

            if (hasNvidiaAdapter)
            {
                ordered.Add(ResolvedLocalBackend.Cuda);
                ordered.Add(ResolvedLocalBackend.DirectML);
            }
            else if (hasAnyHardwareAdapter)
            {
                ordered.Add(ResolvedLocalBackend.DirectML);
                ordered.Add(ResolvedLocalBackend.Cuda);
            }

            ordered.Add(ResolvedLocalBackend.Cpu);
            break;
        }

        return ordered.Distinct().ToArray();
    }

    private string? ResolveHelperScript()
    {
        return ResolveHelperScript(applicationBaseDirectory);
    }

    private static string? ResolveHelperScript(string baseDirectory)
    {
        var candidates = new[]
        {
            Path.Combine(baseDirectory, "Runtime", "kokoro_windows.py"),
            Path.Combine(baseDirectory, "Assets", "Runtime", "kokoro_windows.py")
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? FindPythonExecutable(string runtimeRoot)
    {
        var candidates = new[]
        {
            Path.Combine(runtimeRoot, "python.exe"),
            Path.Combine(runtimeRoot, "Scripts", "python.exe"),
            Path.Combine(runtimeRoot, "python", "python.exe")
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private bool EnsureBundledRuntimeExtracted(string rootName)
    {
        var archivePath = ResolveBundledRuntimeArchive(rootName);
        if (archivePath is null)
        {
            return false;
        }

        var destination = Path.Combine(localRuntimeRoot, rootName);
        if (FindPythonExecutable(destination) is not null)
        {
            return true;
        }

        RuntimeExtractionGate.Wait();
        try
        {
            if (FindPythonExecutable(destination) is not null)
            {
                return true;
            }

            Directory.CreateDirectory(localRuntimeRoot);

            var tempDirectory = destination + ".extracting-" + Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(tempDirectory);

            try
            {
                ZipFile.ExtractToDirectory(archivePath, tempDirectory);

                if (Directory.Exists(destination))
                {
                    Directory.Delete(destination, recursive: true);
                }

                Directory.Move(tempDirectory, destination);
            }
            finally
            {
                if (Directory.Exists(tempDirectory))
                {
                    try
                    {
                        Directory.Delete(tempDirectory, recursive: true);
                    }
                    catch
                    {
                        // Best-effort cleanup only.
                    }
                }
            }

            return FindPythonExecutable(destination) is not null;
        }
        finally
        {
            RuntimeExtractionGate.Release();
        }
    }

    private string? ResolveBundledRuntimeArchive(string rootName)
    {
        var candidates = new[]
        {
            Path.Combine(applicationBaseDirectory, "RuntimeArchives", rootName + ".zip"),
            Path.Combine(applicationBaseDirectory, "Runtimes", rootName + ".zip")
        };

        return candidates.FirstOrDefault(File.Exists);
    }
}

public sealed class KokoroSynthesizer
{
    private readonly GpuProbe gpuProbe;
    private readonly KokoroRuntimeLocator runtimeLocator;

    public KokoroSynthesizer(GpuProbe? gpuProbe = null, KokoroRuntimeLocator? runtimeLocator = null)
    {
        this.gpuProbe = gpuProbe ?? new GpuProbe();
        this.runtimeLocator = runtimeLocator ?? new KokoroRuntimeLocator();
    }

    public async Task<KokoroSynthesisResult> SynthesizeAsync(
        SynthesisRequest request,
        IProgress<KokoroRuntimeUpdate>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(request.Text);
        ArgumentException.ThrowIfNullOrWhiteSpace(request.Voice);

        var candidates = runtimeLocator.ResolveCandidateOrder(request.AccelerationMode, request.LastKnownGoodBackend, gpuProbe);
        var errors = new List<string>();
        progress?.Report(new KokoroRuntimeUpdate(
            "candidate-order",
            $"Backend order: {string.Join(" -> ", candidates)}",
            CandidateOrder: candidates));

        foreach (var backend in candidates)
        {
            if (!runtimeLocator.TryResolveRuntime(backend, out var runtime))
            {
                errors.Add($"{backend}: runtime not found");
                progress?.Report(new KokoroRuntimeUpdate(
                    "runtime-missing",
                    $"{backend} runtime not found",
                    Backend: backend));
                continue;
            }

            try
            {
                progress?.Report(new KokoroRuntimeUpdate(
                    "backend-starting",
                    $"Trying {runtime.Backend} with {runtime.PythonExecutable}",
                    Backend: runtime.Backend,
                    RuntimePythonPath: runtime.PythonExecutable,
                    HelperScriptPath: runtime.HelperScript));
                return await RunBackendAsync(runtime, request, progress, cancellationToken);
            }
            catch (Exception exception)
            {
                errors.Add($"{backend}: {exception.Message}");
                progress?.Report(new KokoroRuntimeUpdate(
                    "backend-failed",
                    $"{backend} failed: {SummarizeExceptionMessage(exception)}",
                    Backend: backend,
                    RuntimePythonPath: runtime.PythonExecutable,
                    HelperScriptPath: runtime.HelperScript));
            }
        }

        throw new InvalidOperationException("Kokoro synthesis failed on all Windows backends. " + string.Join(" | ", errors));
    }

    private static async Task<KokoroSynthesisResult> RunBackendAsync(
        KokoroRuntimePath runtime,
        SynthesisRequest request,
        IProgress<KokoroRuntimeUpdate>? progress,
        CancellationToken cancellationToken)
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), "AudioLocal", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        progress?.Report(new KokoroRuntimeUpdate(
            "scratch-created",
            $"Created scratch folder {tempRoot}",
            Backend: runtime.Backend,
            RuntimePythonPath: runtime.PythonExecutable,
            HelperScriptPath: runtime.HelperScript,
            WorkingDirectory: tempRoot));

        try
        {
            var inputPath = Path.Combine(tempRoot, "input.txt");
            var outputPath = Path.Combine(tempRoot, "output.wav");
            await File.WriteAllTextAsync(inputPath, request.Text, cancellationToken);
            progress?.Report(new KokoroRuntimeUpdate(
                "input-written",
                $"Wrote synthesis input to {inputPath}",
                Backend: runtime.Backend,
                RuntimePythonPath: runtime.PythonExecutable,
                HelperScriptPath: runtime.HelperScript,
                WorkingDirectory: tempRoot));

            var startInfo = new ProcessStartInfo
            {
                FileName = runtime.PythonExecutable,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            startInfo.ArgumentList.Add(runtime.HelperScript);
            startInfo.ArgumentList.Add("--input");
            startInfo.ArgumentList.Add(inputPath);
            startInfo.ArgumentList.Add("--output");
            startInfo.ArgumentList.Add(outputPath);
            startInfo.ArgumentList.Add("--voice");
            startInfo.ArgumentList.Add(request.Voice);
            startInfo.ArgumentList.Add("--speed");
            startInfo.ArgumentList.Add(request.Speed.ToString("0.00", CultureInfo.InvariantCulture));
            startInfo.ArgumentList.Add("--backend");
            startInfo.ArgumentList.Add(runtime.Backend switch
            {
                ResolvedLocalBackend.Cuda => "cuda",
                ResolvedLocalBackend.DirectML => "directml",
                _ => "cpu"
            });

            using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start the Kokoro runtime.");
            progress?.Report(new KokoroRuntimeUpdate(
                "worker-started",
                $"Started Kokoro worker pid {process.Id}",
                Backend: runtime.Backend,
                RuntimePythonPath: runtime.PythonExecutable,
                HelperScriptPath: runtime.HelperScript,
                WorkingDirectory: tempRoot,
                WorkerProcessId: process.Id));
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);

            var stdoutText = await stdoutTask;
            var stderrText = await stderrTask;
            progress?.Report(new KokoroRuntimeUpdate(
                "worker-exited",
                $"Kokoro worker exited with code {process.ExitCode}",
                Backend: runtime.Backend,
                RuntimePythonPath: runtime.PythonExecutable,
                HelperScriptPath: runtime.HelperScript,
                WorkingDirectory: tempRoot,
                WorkerProcessId: process.Id));

            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderrText) ? "Runtime exited with a non-zero status." : stderrText.Trim());
            }

            if (!File.Exists(outputPath))
            {
                throw new InvalidOperationException("Kokoro did not produce an output file.");
            }

            var metadata = KokoroHelperOutputParser.Parse(stdoutText);
            var wavData = await File.ReadAllBytesAsync(outputPath, cancellationToken);
            progress?.Report(new KokoroRuntimeUpdate(
                "audio-ready",
                $"Generated {(wavData.Length / 1024d):N0} KB of WAV audio",
                Backend: runtime.Backend,
                RuntimePythonPath: runtime.PythonExecutable,
                HelperScriptPath: runtime.HelperScript,
                WorkingDirectory: tempRoot,
                WorkerProcessId: process.Id));
            return new KokoroSynthesisResult(
                wavData,
                runtime.Backend,
                metadata.DeviceLabel,
                metadata.BackendLabel);
        }
        finally
        {
            try
            {
                Directory.Delete(tempRoot, recursive: true);
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }
    }

    private static string SummarizeExceptionMessage(Exception exception)
    {
        var firstLine = exception.GetBaseException().Message
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault();

        return string.IsNullOrWhiteSpace(firstLine) ? "Unknown runtime failure." : firstLine;
    }
}
