using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// The development front end: every tool, one button each, drawn with HMA's own art.
/// </summary>
/// <remarks>
/// **Nothing here reimplements anything.** Each button names a subcommand of `tool/hma.py`, so a change to a tool
/// reaches this window without being ported, and there is exactly one behaviour to be wrong.
///
/// **The art is loaded as `Texture2D` and wrapped in a `Sprite` by hand.** `Resources.Load<Sprite>` depends on how the
/// file was imported, and a PNG in a 3D project imports as a texture -- so asking for a sprite returns null and the
/// art quietly does not appear. Creating the sprite here works whatever the import settings happen to be, which
/// matters because the failure is invisible.
///
/// **`fix` is deliberately two buttons.** The first runs the dry run, which changes nothing; the second passes
/// `--apply`. Collapsing them would let one click move somebody files.
/// </remarks>
public class HmaPanel : MonoBehaviour
{
    private static readonly (string Label, string Command, bool NeedsArgument)[] Commands =
    {
        ("这边什么状态 (status)", "status", false),
        ("看看机器上有什么 (doctor)", "doctor", false),
        ("把诊断收成一个包 (report)", "report", false),
        ("只看不改 (fix · 演练)", "fix", false),
        ("真的动手 (fix · --apply)", "fix --apply", false),
        ("哪几家模型配好了 (models)", "models", false),
        ("问一句 (ask)", "ask gemini", true),
        ("让它去查 (agent)", "agent", true),
    };

    private const float RowHeight = 52f;
    private const float SideWidth = 340f;

    private Text _output;
    private InputField _input;
    private Font _font;
    private readonly Dictionary<string, Sprite> _art = new Dictionary<string, Sprite>();

    private void Start()
    {
        // **A font that has CJK glyphs.** Unity's built-in one does not, and a window full of boxes looks exactly
        // like a tool that failed rather than like a missing typeface.
        _font = Font.CreateDynamicFontFromOSFont(
            new[] { "Microsoft YaHei", "Yu Gothic UI", "SimSun", "Noto Sans CJK SC", "Arial Unicode MS" }, 16);
        if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

        LoadArt();
        var canvas = MakeCanvas();
        BuildGround(canvas);
        BuildButtons(canvas);
        BuildInput(canvas);
        BuildOutput(canvas);

        _output.text = Hma.Run("doctor");
    }

    /// <summary>Loads every picture once, by name, wrapped as a sprite regardless of import settings.</summary>
    private void LoadArt()
    {
        foreach (var name in new[] { "panel-9slice", "wash", "divider", "button-normal", "button-press", "button-disable" })
        {
            var texture = Resources.Load<Texture2D>("Art/" + name);
            if (texture == null) continue;
            _art[name] = Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height),
                                       new Vector2(0.5f, 0.5f), 100f);
        }
    }

    private GameObject MakeCanvas()
    {
        var canvas = new GameObject("Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        canvas.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
        return canvas;
    }

    /// <summary>The faint wash behind everything, and the ground colour under it.</summary>
    private void BuildGround(GameObject canvas)
    {
        if (!_art.ContainsKey("wash")) return;
        var wash = MakeImage(canvas, "Wash", _art["wash"]);
        var rect = wash.GetComponent<RectTransform>();
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        var image = wash.GetComponent<Image>();
        image.type = Image.Type.Tiled;
        image.color = new Color(1f, 1f, 1f, 0.5f);
    }

    private void BuildButtons(GameObject canvas)
    {
        var normal = _art.ContainsKey("button-normal") ? _art["button-normal"] : null;
        var pressed = _art.ContainsKey("button-press") ? _art["button-press"] : null;
        var disabled = _art.ContainsKey("button-disable") ? _art["button-disable"] : null;

        for (var index = 0; index < Commands.Length; index++)
        {
            var entry = Commands[index];
            var button = new GameObject(entry.Label, typeof(RectTransform), typeof(Image), typeof(Button));
            button.transform.SetParent(canvas.transform, false);
            var rect = button.GetComponent<RectTransform>();
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(0f, 1f);
            rect.pivot = new Vector2(0f, 1f);
            rect.anchoredPosition = new Vector2(16f, -16f - index * RowHeight);
            rect.sizeDelta = new Vector2(SideWidth - 32f, RowHeight - 6f);

            var image = button.GetComponent<Image>();
            if (normal != null) image.sprite = normal;
            image.type = Image.Type.Sliced;
            image.color = Color.white;

            // **Sprite states live on `spriteState`, not on `colors`.** Writing `pressedSprite` into a `ColorBlock`
            // does not compile, which is how this was found -- a headless compile is the referee for API guesses.
            var buttonComponent = button.GetComponent<Button>();
            var states = buttonComponent.spriteState;
            if (pressed != null) states.pressedSprite = pressed;
            if (disabled != null) states.disabledSprite = disabled;
            buttonComponent.spriteState = states;
            var colours = buttonComponent.colors;
            colours.highlightedColor = new Color(0.88f, 0.96f, 0.96f);
            buttonComponent.colors = colours;

            var label = MakeText(button, entry.Label);
            label.alignment = TextAnchor.MiddleLeft;
            label.color = new Color(0.05f, 0.06f, 0.08f);

            var command = entry.Command;
            var needsArgument = entry.NeedsArgument;
            button.GetComponent<Button>().onClick.AddListener(() => Run(command, needsArgument));
        }
    }

    private void BuildInput(GameObject canvas)
    {
        var field = new GameObject("Argument", typeof(RectTransform), typeof(Image), typeof(InputField));
        field.transform.SetParent(canvas.transform, false);
        var rect = field.GetComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 1f);
        rect.anchorMax = new Vector2(0f, 1f);
        rect.pivot = new Vector2(0f, 1f);
        rect.anchoredPosition = new Vector2(16f, -16f - Commands.Length * RowHeight - 8f);
        rect.sizeDelta = new Vector2(SideWidth - 32f, 40f);
        if (_art.ContainsKey("panel-9slice"))
        {
            var image = field.GetComponent<Image>();
            image.sprite = _art["panel-9slice"];
            image.type = Image.Type.Sliced;
            image.color = new Color(1f, 1f, 1f, 0.55f);
        }

        var placeholder = MakeText(field, "ask 与 agent 要说的话写在这里");
        placeholder.color = new Color(0.45f, 0.5f, 0.55f);

        var text = MakeText(field, string.Empty);
        text.color = new Color(0.92f, 0.95f, 0.96f);

        _input = field.GetComponent<InputField>();
        _input.textComponent = text;
        _input.placeholder = placeholder;
        _input.lineType = InputField.LineType.SingleLine;
    }

    private void BuildOutput(GameObject canvas)
    {
        var panel = new GameObject("Output", typeof(RectTransform), typeof(Image));
        panel.transform.SetParent(canvas.transform, false);
        var rect = panel.GetComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0f);
        rect.anchorMax = new Vector2(1f, 1f);
        rect.offsetMin = new Vector2(SideWidth, 16f);
        rect.offsetMax = new Vector2(-16f, -16f);
        var image = panel.GetComponent<Image>();
        if (_art.ContainsKey("panel-9slice"))
        {
            image.sprite = _art["panel-9slice"];
            image.type = Image.Type.Sliced;
            image.color = new Color(1f, 1f, 1f, 0.92f);
        }
        else
        {
            image.color = new Color(0.10f, 0.10f, 0.12f, 0.92f);
        }

        var text = MakeText(panel, string.Empty);
        var textRect = text.GetComponent<RectTransform>();
        textRect.offsetMin = new Vector2(14f, 14f);
        textRect.offsetMax = new Vector2(-14f, -14f);
        _output = text;
        _output.color = new Color(0.90f, 0.94f, 0.95f);
        _output.alignment = TextAnchor.UpperLeft;
        _output.supportRichText = false;
        _output.horizontalOverflow = HorizontalWrapMode.Wrap;
        _output.verticalOverflow = VerticalWrapMode.Overflow;

        // **The rule under the heading**, which is the one place a divider belongs in this window.
        if (_art.ContainsKey("divider"))
        {
            var rule = MakeImage(canvas, "Rule", _art["divider"]);
            var ruleRect = rule.GetComponent<RectTransform>();
            ruleRect.anchorMin = new Vector2(0f, 1f);
            ruleRect.anchorMax = new Vector2(0f, 1f);
            ruleRect.pivot = new Vector2(0f, 1f);
            ruleRect.anchoredPosition = new Vector2(16f, -16f - Commands.Length * RowHeight - 58f);
            ruleRect.sizeDelta = new Vector2(SideWidth - 32f, 14f);
            rule.GetComponent<Image>().color = new Color(1f, 1f, 1f, 0.8f);
        }
    }

    private GameObject MakeImage(GameObject parent, string name, Sprite sprite)
    {
        var go = new GameObject(name, typeof(RectTransform), typeof(Image));
        go.transform.SetParent(parent.transform, false);
        go.GetComponent<Image>().sprite = sprite;
        return go;
    }

    private Text MakeText(GameObject parent, string content)
    {
        var go = new GameObject("Text", typeof(RectTransform), typeof(Text));
        go.transform.SetParent(parent.transform, false);
        var rect = go.GetComponent<RectTransform>();
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = new Vector2(10f, 0f);
        rect.offsetMax = new Vector2(-10f, 0f);
        var text = go.GetComponent<Text>();
        text.font = _font;
        text.text = content;
        text.alignment = TextAnchor.MiddleCenter;
        return text;
    }

    private void Run(string command, bool needsArgument)
    {
        var argument = needsArgument ? _input.text : string.Empty;
        if (needsArgument && string.IsNullOrWhiteSpace(argument))
        {
            _output.text = "这一条要一句话 —— 写在左边的框里，再按一次。";
            return;
        }
        _output.text = "在跑：" + command + (needsArgument ? " " + argument : string.Empty) + " …";
        _output.text = Hma.Run(needsArgument ? command + " \"" + argument + "\"" : command);
    }
}
