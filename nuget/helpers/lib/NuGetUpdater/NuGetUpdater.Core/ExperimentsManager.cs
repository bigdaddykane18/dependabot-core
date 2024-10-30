using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Core;

public record ExperimentsManager
{
    public bool UseLegacyDependencySolver { get; init; } = false;

    public static ExperimentsManager GetExperimentsManager(Dictionary<string, object>? experiments)
    {
        return new ExperimentsManager()
        {
            UseLegacyDependencySolver = IsEnabled(experiments, "nuget_legacy_dependency_solver"),
        };
    }

    public static async Task<ExperimentsManager> FromJobFileAsync(string jobFilePath)
    {
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath);
        var jobWrapper = RunWorker.Deserialize(jobFileContent);
        return GetExperimentsManager(jobWrapper.Job.Experiments);
    }

    private static bool IsEnabled(Dictionary<string, object>? experiments, string experimentName)
    {
        if (experiments is null)
        {
            return false;
        }

        if (experiments.TryGetValue(experimentName, out var value))
        {
            if ((value?.ToString()?? "").Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
