using UnityEngine;

/// <summary>
/// Puts the panel into whatever scene is running, so that no scene has to know about it.
/// </summary>
/// <remarks>
/// **Written because a headless build needs a scene and the panel needs to be in one.** A `MonoBehaviour` does not
/// exist until something instantiates it, and hand-maintaining a scene file that references the right component by GUID
/// is the sort of thing that breaks silently. `RuntimeInitializeOnLoadMethod` runs after the first scene loads
/// regardless of what is in it, so the scene can stay empty -- **a container rather than a design** -- and the panel
/// installs itself.
/// </remarks>
public static class Bootstrap
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Install()
    {
        if (Object.FindObjectOfType<HmaPanel>() != null) return;
        var host = new GameObject("HmaPanel");
        host.AddComponent<HmaPanel>();
        Object.DontDestroyOnLoad(host);
    }
}
