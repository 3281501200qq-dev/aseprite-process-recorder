from pathlib import Path
import re


plugin = Path(__file__).resolve().parent.parent / "plugin"
source = (plugin / "i18n.lua").read_text(encoding="utf-8")
used = set()
for filename in ("main.lua", "recorder.lua"):
    code = (plugin / filename).read_text(encoding="utf-8")
    used.update(re.findall(r't\("([a-z_]+)"\)', code))

translations = {}
for language in ("zh_CN", "en", "ja"):
    match = re.search(
        rf"  {language} = \{{(.*?)\n  \}}",
        source,
        re.DOTALL,
    )
    assert match, f"Missing language: {language}"
    translations[language] = set(
        re.findall(r"^    ([a-z_]+) =", match.group(1), re.MULTILINE)
    )
    missing = used - translations[language]
    assert not missing, f"{language} is missing: {sorted(missing)}"

assert translations["zh_CN"] == translations["en"] == translations["ja"]
print(f"TRANSLATIONS PASS: {len(used)} used strings in three languages")
