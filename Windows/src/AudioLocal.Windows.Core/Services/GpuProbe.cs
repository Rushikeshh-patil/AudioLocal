using System.Management;

namespace AudioLocal.Windows.Core.Services;

public sealed record GpuAdapterInfo(string Name, bool IsNvidia, bool IsSoftwareAdapter);

public sealed class GpuProbe
{
    public IReadOnlyList<GpuAdapterInfo> GetAdapters()
    {
        var adapters = new List<GpuAdapterInfo>();

        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController");
            foreach (ManagementObject controller in searcher.Get())
            {
                var name = controller["Name"]?.ToString()?.Trim();
                if (string.IsNullOrWhiteSpace(name))
                {
                    continue;
                }

                var isSoftware = name.Contains("Microsoft Basic", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("Remote Display", StringComparison.OrdinalIgnoreCase);
                adapters.Add(new GpuAdapterInfo(
                    name,
                    IsNvidia: name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase),
                    IsSoftwareAdapter: isSoftware));
            }
        }
        catch
        {
            // Keep GPU probing best-effort. The runtime selector can still fall back to CPU.
        }

        return adapters;
    }

    public bool HasNvidiaAdapter() =>
        GetAdapters().Any(static adapter => adapter.IsNvidia && !adapter.IsSoftwareAdapter);

    public bool HasAnyHardwareAdapter() =>
        GetAdapters().Any(static adapter => !adapter.IsSoftwareAdapter);
}
