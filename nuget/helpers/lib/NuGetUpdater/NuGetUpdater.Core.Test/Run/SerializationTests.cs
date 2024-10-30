using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class SerializationTests
{
    [Fact]
    public void DeserializeJob()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "debug": false,
                "dependency-groups": [],
                "dependencies": null,
                "dependency-group-to-refresh": null,
                "existing-pull-requests": [],
                "existing-group-pull-requests": [],
                "experiments": null,
                "ignore-conditions": [],
                "lockfile-only": false,
                "requirements-update-strategy": null,
                "security-advisories": [],
                "security-updates-only": false,
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "specific-sdk",
                  "hostname": null,
                  "api-endpoint": null
                },
                "update-subdependencies": false,
                "updating-a-pull-request": false,
                "vendor-dependencies": false,
                "reject-external-code": false,
                "repo-private": false,
                "commit-message-options": null,
                "credentials-metadata": [
                  {
                    "host": "github.com",
                    "type": "git_source"
                  }
                ],
                "max-updater-run-time": 0
              }
            }
            """);
        Assert.Equal("github", jobWrapper.Job.Source.Provider);
        Assert.Equal("some-org/some-repo", jobWrapper.Job.Source.Repo);
        Assert.Equal("specific-sdk", jobWrapper.Job.Source.Directory);
    }

    [Fact]
    public void DeserializeExperimentsManager()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                },
                "experiments": {
                  "nuget_legacy_dependency_solver": true,
                  "unexpected_bool": true,
                  "unexpected_number": 42,
                  "unexpected_null": null,
                  "unexpected_string": "abc",
                  "unexpected_array": [1, "two", 3.0],
                  "unexpected_object": {
                    "a": 1,
                    "b": "two"
                  }
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.True(experimentsManager.UseLegacyDependencySolver);
    }

    [Fact]
    public void DeserializeExperimentsManager_EmptyExperiments()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                },
                "experiments": {
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.False(experimentsManager.UseLegacyDependencySolver);
    }

    [Fact]
    public void DeserializeExperimentsManager_NoExperiments()
    {
        var jobWrapper = RunWorker.Deserialize("""
            {
              "job": {
                "package-manager": "nuget",
                "allowed-updates": [
                  {
                    "update-type": "all"
                  }
                ],
                "source": {
                  "provider": "github",
                  "repo": "some-org/some-repo",
                  "directory": "some-dir"
                }
              }
            }
            """);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        Assert.False(experimentsManager.UseLegacyDependencySolver);
    }

    [Fact]
    public void SerializeError()
    {
        var error = new JobRepoNotFound("some message");
        var actual = HttpApiHandler.Serialize(error);
        var expected = """{"data":{"error-type":"job_repo_not_found","error-details":{"message":"some message"}}}""";
        Assert.Equal(expected, actual);
    }
}
