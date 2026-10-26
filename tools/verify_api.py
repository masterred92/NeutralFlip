#!/usr/bin/env python3
"""Verify every WoW API name an addon uses exists in Blizzard's UI source (Gethe/wow-ui-source).

usage: verify_api.py <wow-ui-source checkout> <addon .lua> [more .lua ...]

Checks, against the given checkout (we use the `forever` branch, 1.60.1 build 70374):
  * globals the code reads (found by luacheck as undefined, so nothing is missed)
  * C_Namespace.Function calls, Enum.X.Y values and RegisterEvent("EVENT") names
  * XML templates passed to CreateFrame and font objects
  * widget methods called with ':' (must be documented or used by Blizzard's own code)
Exit code 1 if anything is missing.
"""
import re, sys, subprocess, pathlib, shutil

# Globals and methods that come from the host addons (DBM, BigWigs, Details, Questie, LibStub...) or from the
# client but not from Blizzard's UI source. Each one was checked by hand in the host's own source; see host_api.py.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("host_api", pathlib.Path(__file__).with_name("host_api.py"))
_h = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_h)
HOST, HOST_METHODS = _h.HOST, _h.HOST_METHODS
_rc = (pathlib.Path(__file__).parent.parent / ".luacheckrc").read_text()
_m = re.search(r"^globals\s*=\s*\{(.*?)\}", _rc, re.S | re.M)
OWN = set(re.findall(r'"(\w+)"', _m.group(1))) if _m else set()

SRC = pathlib.Path(sys.argv[1]); files = [pathlib.Path(p) for p in sys.argv[2:]]
UI = SRC / "Interface"; DOC = UI / "AddOns/Blizzard_APIDocumentationGenerated"
docs = {p.name: p.read_text(errors="ignore") for p in DOC.glob("*.lua")}
alldocs = "\n".join(docs.values())

ns_funcs, global_funcs, doc_funcs = set(), set(), set()
for text in docs.values():
    for block in re.split(r"\nlocal \w+ =\n", text):
        names = set(re.findall(r'\t\t\tName = "(\w+)",\n\t\t\tType = "Function"', block))
        doc_funcs |= names
        m = re.search(r'Namespace = "([\w.]+)"', block)
        if m: ns_funcs |= {f"{m.group(1)}.{n}" for n in names}
        elif 'Type = "System"' in block or "Functions" in block: global_funcs |= names
events = set(re.findall(r'LiteralName = "(\w+)"', alldocs))
enum_vals = {}
for m in re.finditer(r'Name = "(\w+)",\n\t\t\tType = "Enumeration",(.*?)\n\t\t},', alldocs, re.S):
    enum_vals.setdefault(m.group(1), set()).update(re.findall(r'Name = "(\w+)", Type = "\w+", EnumValue', m.group(2)))

def rg(pattern, globs=("*.lua", "*.xml")):
    args = ["rg", "-q"] + sum((["-g", g] for g in globs), []) + [pattern, str(UI)]
    return subprocess.run(args, timeout=120).returncode == 0

LUA_STD = set("""assert error ipairs next pairs pcall print rawget rawset select setmetatable getmetatable tonumber
tostring type unpack xpcall math string table coroutine os _G""".split())
WOW_LUA_EXTRAS = {"date": "WoW keeps Lua's date()", "time": "WoW keeps Lua's time()"}

def luacheck_globals(path):
    lc = shutil.which("luacheck") or "/workspace/lua51/bin/luacheck"
    out = subprocess.run([lc, "--no-config", "--std", "lua51", "--formatter", "plain", "--codes", str(path)],
                         capture_output=True, text=True, timeout=120).stdout
    read = set(re.findall(r"\(W113\) accessing undefined variable '(\w+)'", out))
    wrote = set(re.findall(r"\(W111\) setting non-standard global variable '(\w+)'", out))
    return read, wrote

results, fails = [], 0
def report(name, ok, where):
    global fails
    results.append(("OK   " if ok else "MISS ") + f"{name:55s} [{where}]")
    if not ok: fails += 1

for f in files:
    code = f.read_text()
    code_nc = re.sub(r"--[^\n]*", "", code)
    results.append(f"\n== {f}")
    read, wrote = luacheck_globals(f)
    own = wrote | set(re.findall(r"^\s*(\w+)\s*=", code_nc, re.M))
    for g in sorted(read - own):
        if g in WOW_LUA_EXTRAS: report(g, rg(rf"\b{g}\("), WOW_LUA_EXTRAS[g] + "; used in UI source"); continue
        if g.startswith("C_") or g == "Enum": continue  # members checked below
        if g in OWN: report(g, True, "our own global (declared in .luacheckrc)"); continue
        if g in HOST: report(g, True, HOST[g]); continue
        if g in global_funcs: report(g, True, "global API doc"); continue
        if rg(rf"^\s*{g}\s*=|^function {g}\(|name=\"{g}\""): report(g, True, "defined in UI source"); continue
        report(g, rg(rf"(^|[^.:\w]){g}\("), "called by Blizzard UI code")
    for n in sorted(set(re.findall(r"\b(C_\w+\.\w+)\b", code_nc))):
        report(n, n in ns_funcs, "API documentation")
    for e, v in sorted(set(re.findall(r"\bEnum\.(\w+)\.(\w+)", code_nc))):
        report(f"Enum.{e}.{v}", v in enum_vals.get(e, ()), "API documentation enum")
    evs = set(re.findall(r'RegisterEvent\("(\w+)"\)', code_nc))
    m = re.search(r'for _, e in ipairs\(\{(.*?)\}\) do ev:RegisterEvent', code_nc, re.S)
    if m: evs |= set(re.findall(r'"(\w+)"', m.group(1)))
    for e in sorted(evs): report(e, e in events, "event documentation")
    for t in sorted(set(re.findall(r'CreateFrame\("\w+",\s*[^,]+,\s*[^,]+,\s*"(\w+)"\)', code_nc))):
        report(t, rg(rf'name="{t}"[^>]*virtual="true"|name="{t}"', ("*.xml",)), "XML template")
    for fo in sorted(set(re.findall(r'"((?:Game|Chat)Font\w+)"', code_nc))):
        report(fo, rg(rf'name="{fo}"', ("*.xml",)) or rg(rf"^{fo} =|CreateFont\(\"{fo}\"\)"), "font object")
    for meth in sorted(set(re.findall(r":(\w+)\(", code_nc)) | set(re.findall(r"\b\w+\.(StartMoving|StopMovingOrSizing)\b", code_nc))):
        if meth in ("match", "gmatch", "gsub", "find", "format", "lower", "upper", "sub", "rep", "byte", "len"):
            continue  # Lua string methods
        if meth in HOST_METHODS: report(":" + meth, True, HOST_METHODS[meth]); continue
        ok = meth in doc_funcs or rg(rf":{meth}\(")
        report(":" + meth, ok, "widget API doc" if meth in doc_funcs else "used by Blizzard UI code")

print("\n".join(results))
total = sum(1 for r in results if r.startswith(("OK", "MISS")))
print(f"\n{total - fails}/{total} verified; {fails} missing")
sys.exit(1 if fails else 0)
