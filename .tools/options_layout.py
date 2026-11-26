"""Check native two-column option rows in an integrated source tree."""

import argparse
from dataclasses import dataclass
from pathlib import Path

from guardrails import bracket_pairs, lua_tokens, sym


# Exact adjacent controls with layout evidence outside their slot configs.
INTENTIONAL = {
    ("EUI_AuraBuffReminders_Options.lua", "SECTION_CONSUMABLES",
     "Inky Black Potion", "Show Without Item in Bags"):
        "The right region hosts the native Choose Zones button.",
    ("EUI_BlizzardSkin_Options.lua", "BLIZZARD TOOLTIP",
     "Show Max Stack for Items", "Show Health Strip"):
        "The final basic content control is independent of the following reskin controls.",
    ("EUI_Chat_Options.lua", "BORDER", "Sync Border with Chat Panel", "Border Style"):
        "The master toggle stands above the paired style/size and width/height editors.",
}


@dataclass(frozen=True)
class Row:
    line: int
    left: str
    right: str
    left_blank: bool
    right_blank: bool
    full_width: bool


def arguments(tokens, pairs, start):
    args, begin = [], start + 1
    i = begin
    while i < pairs[start]:
        if sym(tokens[i]) == ",":
            args.append(tokens[begin:i])
            begin = i + 1
        i = pairs.get(i, i) + 1
    return args + [tokens[begin:i]]


def shape(tokens):
    return tuple((kind, value) for kind, value, _ in tokens)


def blank(tokens):
    values = tuple(value for _, value, _ in tokens)
    # Only recognize an explicit empty slot or a direct availability fallback.
    if len(tokens) >= 5 and tokens[-5][0] == "name" and values[-4:] == (".", "BlankRowCfg", "(", ")"):
        return len(tokens) == 5 or tokens[-6][:2] == ("keyword", "or")
    if not tokens or sym(tokens[0]) != "{":
        return False
    pairs = bracket_pairs(tokens)
    if pairs.get(0) != len(tokens) - 1:
        return False
    fields = {field[0][1]: field[2][1] for field in arguments(tokens, pairs, 0)
              if len(field) == 3 and field[0][0] == "name" and sym(field[1]) == "="
              and field[2][0] == "string"}
    return fields.get("type") == "spacer" or (fields.get("type") == "label" and fields.get("text") == "")


def label(tokens):
    for i in range(len(tokens) - 2):
        if tokens[i][:2] == ("name", "text") and sym(tokens[i + 1]) == "=" and tokens[i + 2][0] == "string":
            return tokens[i + 2][1]
    return " ".join(value for _, value, _ in tokens[:12]) or "<omitted>"


def findings(source):
    tokens = lua_tokens(source)
    pairs = bracket_pairs(tokens)
    scopes = [{}]
    i = 0
    while i + 3 < len(tokens):
        word = sym(tokens[i])
        if word in {"function", "if", "do", "repeat"}:
            scopes.append({})
        elif word in {"else", "elseif"} and len(scopes) > 1:
            scopes[-1] = {}
        elif word in {"end", "until"} and len(scopes) > 1:
            scopes.pop()

        if (tokens[i][0] == "name" and sym(tokens[i + 1]) == ":" and i + 3 in pairs
                and sym(tokens[i + 3]) == "("):
            method = tokens[i + 2][1]
            if method in {"DualRow", "SectionHeader", "Spacer"}:
                args = arguments(tokens, pairs, i + 3)
                parent = shape(args[0])
                stream = scopes[-1].setdefault(parent, ["<section without a header>", None])
                if method == "SectionHeader" and len(args) >= 2:
                    stream[:] = [label(args[1]), None]
                elif method == "Spacer":
                    stream[1] = None
                elif len(args) >= 3:
                    left = args[2]
                    right = args[3] if len(args) >= 4 else []
                    row = Row(tokens[i][2], label(left), label(right), blank(left), blank(right),
                              not right or shape(right) == (("keyword", "nil"),))
                    previous = stream[1]
                    if previous and previous.right_blank and not row.full_width and not row.left_blank:
                        yield stream[0], previous, row
                    stream[1] = row
                i = pairs[i + 3]
        i += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    paths = list(args.root.glob("*.lua"))
    for module in args.root.glob("EllesmereUI*"):
        if module.is_dir() and module.name != "EllesmereUILocales":
            paths.extend(path for path in module.rglob("*")
                         if path.is_file() and path.suffix.lower() == ".lua"
                         and not {"libs", "locales"}.intersection(part.lower() for part in path.relative_to(module).parts))
    files = sorted((path, source) for path in set(paths)
                   if "DualRow" in (source := path.read_text(encoding="utf-8-sig")))
    if not files:
        parser.exit(1, f"No addon Lua files with DualRow found under {args.root}\n")
    failures = 0
    for path, source in files:
        for section, left, following in findings(source):
            relative = path.relative_to(args.root)
            if relative.parent == Path("EllesmereUIOptions") and (path.name, section, left.left, following.left) in INTENTIONAL:
                continue
            failures += 1
            print(f"{relative.as_posix()}:{left.line} [{section}]: "
                  f"{left.left} leaves a right slot before {following.left} (line {following.line})")
    print(f"Options layout: {len(files)} Lua files scanned, {failures} internal right-slot gaps.")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
