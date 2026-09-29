using UnityEditor;
using UnityEngine;
using System.Linq;

/// <summary>
/// Puts the scene into the build settings and builds, so that a command line can do the whole thing.
/// </summary>
/// <remarks>
/// **The scene list lives in a binary-ish settings file that is painful to edit by hand and easy to get wrong.** Unity
/// has an API for it, and this runs that API from `-executeMethod`, which is the supported way to drive an editor from
/// a command line.
/// </remarks>
public static class BuildSetup
{
    public static void Build()
    {
        var scene = "Assets/Scenes/Main.unity";
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(scene, true) };
        AssetDatabase.SaveAssets();

        var target = System.Environment.GetEnvironmentVariable("HMA_BUILD_OUT")
                     ?? "Build/hma-dev.exe";
        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(target));
        var report = BuildPipeline.BuildPlayer(
            new[] { scene }, target, BuildTarget.StandaloneWindows64, BuildOptions.None);
        Debug.Log("HMA build result: " + report.summary.result + " size " + report.summary.totalSize);
        EditorApplication.Exit(report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded ? 0 : 1);
    }
}
