using System;
using System.Diagnostics;
using System.Text;
using UnityEngine;

/// <summary>
/// One place that knows how to talk to the command line tools, and the only place that knows where they are.
/// </summary>
/// <remarks>
/// **The front end runs the same commands a person would.** `hma.py` is the whole platform as far as this window is
/// concerned -- doctor, report, fix, models, ask, agent -- so there is no second implementation to fall out of step with
/// the first, and every fix to the tools reaches the window without being ported.
/// </remarks>
public static class Hma
{
    /// <summary>The repository root, found by walking up from the project rather than hard-coded.</summary>
    public static string RepositoryRoot()
    {
        var directory = new System.IO.DirectoryInfo(Application.dataPath).Parent;
        while (directory != null && !System.IO.File.Exists(System.IO.Path.Combine(directory.FullName, "tool", "hma.py")))
        {
            directory = directory.Parent;
        }
        return directory?.FullName;
    }

    /// <summary>Runs one `hma` subcommand and returns everything it said, in its own language.</summary>
    public static string Run(string arguments)
    {
        var root = RepositoryRoot();
        if (root == null) return "找不到仓库根目录 —— 这个窗口必须住在空庭仓库里面。";

        var info = new ProcessStartInfo
        {
            FileName = "python",
            Arguments = "\"" + System.IO.Path.Combine(root, "tool", "hma.py") + "\" " + arguments,
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            // **Both ends explicit.** The tools answer in Chinese; a reader that guesses the code page returns
            // question marks, which looks like a tool that has nothing to say.
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        info.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";

        try
        {
            using (var process = Process.Start(info))
            {
                var output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
                process.WaitForExit(120000);
                return output;
            }
        }
        catch (Exception error)
        {
            return "跑不起来：" + error.Message;
        }
    }
}
