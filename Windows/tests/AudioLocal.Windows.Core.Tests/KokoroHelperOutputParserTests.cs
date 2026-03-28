using AudioLocal.Windows.Core.Services;

namespace AudioLocal.Windows.Core.Tests;

public sealed class KokoroHelperOutputParserTests
{
    [Fact]
    public void ParseReadsJsonWhenWarningsPrecedeIt()
    {
        const string output = """
            WARNING: Defaulting repo_id to hexgrad/Kokoro-82M.
            {"deviceLabel":"CPU","backendLabel":"Kokoro (CPU)"}
            """;

        var metadata = KokoroHelperOutputParser.Parse(output);

        Assert.Equal("CPU", metadata.DeviceLabel);
        Assert.Equal("Kokoro (CPU)", metadata.BackendLabel);
    }

    [Fact]
    public void ParseThrowsWhenNoJsonIsPresent()
    {
        var exception = Assert.Throws<InvalidOperationException>(() => KokoroHelperOutputParser.Parse("warning only"));

        Assert.Contains("helper", exception.Message, StringComparison.OrdinalIgnoreCase);
    }
}
