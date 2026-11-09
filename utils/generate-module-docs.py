#!/usr/bin/env python3
"""Generate MDX (Docusaurus) and MAML (PowerShell Get-Help) from C# XML doc comments.

Reads:
  - The XML documentation file produced by <GenerateDocumentationFile>true</GenerateDocumentationFile>
  - JSON metadata from dump-module-metadata.ps1 (parameter binding info via reflection)

Emits:
  - One .mdx file per exported cmdlet under --output-mdx
  - A single MAML help file at --output-maml

Usage:
  python3 utils/generate-module-docs.py \\
    --module  Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1 \\
    --xml     src/AMT.PowerShell.Common/bin/Debug/AMT.PowerShell.Common.xml \\
    --output-mdx  docs/docs/module/common/AMT.PowerShell.Common \\
    --output-maml src/AMT.PowerShell.Common/Module/en-US/AMT.PowerShell.Common-help.xml
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET


def _inline_text(elem) -> str:
    """Concatenate text from an inline element, handling see/c/code tags."""
    result = elem.text or ""
    for child in elem:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        if tag == "see":
            langword = child.get("langword")
            if langword:
                result += langword
            else:
                cref = child.get("cref", "")
                # strip member-type prefix (T: P: M:) and namespace
                cref = re.sub(r"^[A-Z]:", "", cref)
                result += cref.rsplit(".", 1)[-1] if "." in cref else cref
        elif tag in ("c",):
            result += child.text or ""
        elif tag == "code":
            # inline code reference inside a remark sentence
            result += f"`{(child.text or '').strip()}`"
        else:
            result += _inline_text(child)
        result += child.tail or ""
    return result


def _inner_text(elem) -> str:
    """Extract block text; treat <para> as paragraph separators."""
    if elem is None:
        return ""
    paragraphs: list[str] = []
    current: str = elem.text or ""
    for child in elem:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        if tag == "para":
            combined = " ".join(line.strip() for line in current.strip().split("\n") if line.strip())
            inner = " ".join(line.strip() for line in _inline_text(child).strip().split("\n") if line.strip())
            if inner:
                combined = (combined + " " + inner).strip() if combined else inner
            if combined:
                paragraphs.append(combined)
            current = child.tail or ""
        else:
            current += _inline_text(child) + (child.tail or "")
    if current.strip():
        # Strip per-line indentation produced by XML doc comment formatting.
        # Plain prose in <remarks> without <para> is a single paragraph.
        para_text = " ".join(line.strip() for line in current.strip().split("\n") if line.strip())
        paragraphs.append(para_text)
    result = "\n\n".join(p for p in paragraphs if p)
    if not result.strip():
        return ""
    # Dedent: strip common leading whitespace across lines
    lines = result.split("\n")
    lines = [line.rstrip() for line in lines]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    indents = [len(line) - len(line.lstrip()) for line in lines if line.strip()]
    if indents:
        cut = min(indents)
        lines = [line[cut:] if line.strip() else "" for line in lines]
    return "\n".join(lines)


def _example_parts(elem) -> tuple[str, str]:
    """Return (code, prose) from an <example> element."""
    code = ""
    prose_parts: list[str] = []
    if elem.text and elem.text.strip():
        prose_parts.append(elem.text.strip())
    for child in elem:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        if tag == "code":
            code = (child.text or "").strip()
        elif tag == "para":
            inner = _inner_text(child)
            if inner:
                prose_parts.append(inner)
        else:
            inner = _inner_text(child)
            if inner:
                prose_parts.append(inner)
        if child.tail and child.tail.strip():
            prose_parts.append(child.tail.strip())
    prose = "\n\n".join(prose_parts)
    return code, prose


def parse_xml_doc(xml_path: Path) -> dict[str, dict]:
    """Parse XML doc file → {member_name: {summary, remarks, params, examples, notes}}."""
    tree = ET.parse(str(xml_path))
    root = tree.getroot()
    members: dict[str, dict] = {}
    for member in root.iter("member"):
        name = member.get("name", "")
        summary = _inner_text(member.find("summary"))
        remarks = _inner_text(member.find("remarks"))
        notes = _inner_text(member.find("note")) or _inner_text(member.find("notes"))
        params: dict[str, str] = {}
        for p in member.findall("param"):
            pname = p.get("name", "")
            if pname:
                params[pname] = _inner_text(p)
        examples: list[tuple[str, str]] = []
        for ex in member.findall("example"):
            code, prose = _example_parts(ex)
            if code or prose:
                examples.append((code, prose))
        members[name] = {
            "summary": summary,
            "remarks": remarks,
            "notes": notes,
            "params": params,
            "examples": examples,
        }
    return members


def dump_metadata(module_path: Path, dump_script: Path) -> dict:
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        out_path = f.name

    result = subprocess.run(
        ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(dump_script),
         "-ModulePath", str(module_path), "-OutputPath", out_path],
        capture_output=True,
        text=True,
        check=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"dump-module-metadata.ps1 failed:\n{result.stderr}")
    with open(out_path, encoding="utf-8") as f:
        return json.load(f)


_SHORT_TYPE: dict[str, str] = {
    "System.String": "String",
    "System.Int32": "Int32",
    "System.Int64": "Int64",
    "System.Boolean": "Boolean",
    "System.Double": "Double",
    "System.Object": "Object",
    "System.Object[]": "Object[]",
    "System.String[]": "String[]",
    "System.TimeSpan": "TimeSpan",
    "System.Management.Automation.SwitchParameter": "SwitchParameter",
    "System.Management.Automation.ScriptBlock": "ScriptBlock",
    "System.Management.Automation.ScriptBlock[]": "ScriptBlock[]",
    "System.Management.Automation.PSCmdlet": "PSCmdlet",
    "System.Management.Automation.InvocationInfo": "InvocationInfo",
    "System.Management.Automation.ErrorRecord": "ErrorRecord",
    "System.Management.Automation.ErrorCategory": "ErrorCategory",
    "System.Management.Automation.ActionPreference": "ActionPreference",
    "System.Collections.Hashtable": "Hashtable",
    "System.Collections.Hashtable[]": "Hashtable[]",
    "System.Collections.Generic.List`1[System.String]": "List[String]",
}


def short_type(full_type: str, type_name: str) -> str:
    if full_type in _SHORT_TYPE:
        return _SHORT_TYPE[full_type]
    # strip namespace for known AMT types
    if "AMT.PowerShell.Common" in full_type:
        return full_type.rsplit(".", 1)[-1]
    # Nullable<T>: handle assembly-qualified inner type names
    m = re.match(r"System\.Nullable`1\[\[?([^,\]]+)", full_type)
    if m:
        inner = m.group(1).strip()
        return inner.rsplit(".", 1)[-1]
    # strip assembly qualifier cruft from generics before map lookup
    clean = re.sub(r",\s*[A-Za-z][^,\[\]]*,\s*Version=[^\[\]]+", "", full_type)
    clean = re.sub(r"\[\[([^,\]]+),[^\]]*\]\]", r"[\1]", clean)
    if clean in _SHORT_TYPE:
        return _SHORT_TYPE[clean]
    # strip assembly info and backtick arity
    base = full_type.split("`")[0]
    if base in _SHORT_TYPE:
        return _SHORT_TYPE[base]
    # strip namespace for known AMT types
    if "AMT.PowerShell.Common" in full_type:
        return full_type.rsplit(".", 1)[-1]
    # fall back to short name, cleaning backtick
    return type_name.split("`")[0] if "`" in type_name else type_name


def is_switch(full_type: str) -> bool:
    return "SwitchParameter" in full_type


def _param_in_set(pdata: dict, set_name: str) -> dict | None:
    """Return the binding info if this param participates in set_name, else None."""
    sets = pdata.get("Sets", {})
    return sets.get(set_name) or sets.get("__AllParameterSets") or sets.get("(All)")


def _all_set_names(params: dict) -> list[str]:
    names: set[str] = set()
    for p in params.values():
        for s in p.get("Sets", {}):
            names.add(s)
    return sorted(names) if names else ["__AllParameterSets"]


def _display_set(name: str) -> str:
    return "(All)" if name == "__AllParameterSets" else name


def build_syntax(cmd_name: str, params: dict) -> list[tuple[str, str]]:
    all_sets = _all_set_names(params)
    result: list[tuple[str, str]] = []
    for set_name in all_sets:
        tokens = [cmd_name]
        positional: list[tuple[int, str]] = []
        named: list[str] = []
        for pname, pdata in params.items():
            binding = _param_in_set(pdata, set_name)
            if binding is None:
                continue
            pos = binding.get("Position")
            if pos is not None:
                positional.append((int(pos), pname))
            else:
                named.append(pname)
        positional.sort(key=lambda x: x[0])

        def param_token(pname: str) -> str:
            pdata = params[pname]
            binding = _param_in_set(pdata, set_name) or {}
            required = binding.get("Required", False)
            pos = binding.get("Position")
            tname = short_type(pdata.get("FullType", ""), pdata.get("Type", "Object"))
            switch = is_switch(pdata.get("FullType", ""))
            if switch:
                return f"[-{pname}]"
            if pos is not None:
                inner = f"[-{pname}] <{tname}>"
                return inner if required else f"[{inner}]"
            inner = f"-{pname} <{tname}>"
            return inner if required else f"[{inner}]"

        for _, pname in positional:
            tokens.append(param_token(pname))
        for pname in sorted(named):
            tokens.append(param_token(pname))
        tokens.append("[<CommonParameters>]")
        result.append((_display_set(set_name), " ".join(tokens)))
    return result


_MDX_FRONT = """\
---
id: {name}
title: {name}
description: {synopsis}
keywords:
  - PowerShell
  - Help
  - Documentation
hide_title: false
hide_table_of_contents: false
custom_edit_url: null
---
"""

_COMMON_PARAM_TEXT = (
    "This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,\n"
    "-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,\n"
    "-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see\n"
    "[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216)."
)

_YAML_TEMPLATE = """\
```yaml
Type: {type_name}
DefaultValue: ''
SupportsWildcards: false
Aliases: [{aliases}]
ParameterSets:
{sets}DontShow: false
AcceptedValues: []
HelpMessage: ''
```"""


def _yaml_sets(param_name: str, pdata: dict) -> str:
    lines: list[str] = []
    for set_name, binding in sorted(pdata.get("Sets", {}).items()):
        pos = binding.get("Position")
        lines.append(f"- Name: {set_name}\n")
        lines.append(f"  Position: {pos if pos is not None else 'Named'}\n")
        lines.append(f"  IsRequired: {'true' if binding.get('Required') else 'false'}\n")
        lines.append(f"  ValueFromPipeline: {'true' if binding.get('ValueFromPipeline') else 'false'}\n")
        lines.append(f"  ValueFromPipelineByPropertyName: {'true' if binding.get('ValueFromPipelineByPropertyName') else 'false'}\n")
        lines.append("  ValueFromRemainingArguments: false\n")
    return "".join(lines)


def emit_mdx(
    name: str,
    verb: str,
    noun: str,
    cmd_meta: dict,
    doc: dict,
    xml_members: dict[str, dict],
    output_dir: Path,
) -> None:
    type_name = cmd_meta.get("TypeName", "")
    class_key = f"T:{type_name}"
    class_doc = xml_members.get(class_key, {})

    synopsis = class_doc.get("summary", "").strip() or f"{verb}s a {noun}."
    description = class_doc.get("remarks", "").strip()
    notes = class_doc.get("notes", "").strip()
    examples = class_doc.get("examples", [])
    params = cmd_meta.get("Parameters", {})
    output_types = cmd_meta.get("OutputTypes", [])

    lines: list[str] = []
    lines.append(_MDX_FRONT.format(
        name=name,
        synopsis=synopsis.replace("\n", " ").replace('"', '\\"'),
    ))
    lines.append("\n")

    lines.append("## SYNOPSIS\n")
    lines.append(synopsis + "\n\n")

    # SYNTAX
    syntax_items = build_syntax(name, params)
    lines.append("## SYNTAX\n")
    if len(syntax_items) == 1 and syntax_items[0][0] in ("(All)", "__AllParameterSets"):
        lines.append("```powershell\n")
        lines.append(syntax_items[0][1] + "\n")
        lines.append("```\n\n")
    else:
        for set_name, syntax_str in syntax_items:
            lines.append(f"### {set_name}\n\n")
            lines.append("```powershell\n")
            lines.append(syntax_str + "\n")
            lines.append("```\n\n")

    # DESCRIPTION
    lines.append("## DESCRIPTION\n")
    if description:
        lines.append(description + "\n\n")
    else:
        lines.append(synopsis + "\n\n")

    # EXAMPLES
    lines.append("## EXAMPLES\n")
    if examples:
        for i, (code, prose) in enumerate(examples, 1):
            lines.append(f"\n### Example {i}\n\n")
            if prose:
                lines.append(prose + "\n\n")
            if code:
                lines.append("```powershell\n")
                lines.append(code + "\n")
                lines.append("```\n\n")
    else:
        lines.append("\n")

    # PARAMETERS
    lines.append("## PARAMETERS\n")
    for pname in sorted(params.keys()):
        pdata = params[pname]
        prop_key = f"P:{type_name}.{pname}"
        prop_doc = xml_members.get(prop_key, {})
        param_desc = prop_doc.get("summary", "").strip()
        tname = short_type(pdata.get("FullType", ""), pdata.get("Type", "Object"))
        aliases = ", ".join(pdata.get("Aliases", [])) if pdata.get("Aliases") else ""

        lines.append(f"\n### -{pname}\n\n")
        if param_desc:
            lines.append(param_desc + "\n\n")
        sets_str = _yaml_sets(pname, pdata)
        # Normalise __AllParameterSets → (All) in the YAML block
        sets_str = sets_str.replace("Name: __AllParameterSets", "Name: (All)")
        lines.append(
            _YAML_TEMPLATE.format(
                type_name=tname,
                aliases=aliases,
                sets=sets_str,
            ) + "\n\n"
        )

    lines.append("\n### CommonParameters\n\n")
    lines.append(_COMMON_PARAM_TEXT + "\n\n")

    # INPUTS
    lines.append("## INPUTS\n\n")

    # OUTPUTS
    lines.append("## OUTPUTS\n")
    if output_types:
        for output_type in output_types:
            lines.append(f"\n### {output_type}\n\n")
    else:
        lines.append("\n")

    # NOTES
    lines.append("## NOTES\n")
    if notes:
        lines.append("\n" + notes + "\n\n")
    else:
        lines.append("\n")

    lines.append("## RELATED LINKS\n")

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{name}.mdx"
    out_path.write_text("".join(lines), encoding="utf-8")


def _x(tag: str) -> str:
    prefixes = {"maml": "maml", "command": "command", "dev": "dev"}
    for prefix in prefixes:
        if tag.startswith(prefix + ":"):
            return tag
    return tag


def _esc(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def emit_maml(commands: dict, xml_members: dict, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines: list[str] = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<helpItems schema="maml" xmlns="http://msh"',
        '  xmlns:maml="http://schemas.microsoft.com/maml/2004/10"',
        '  xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10"',
        '  xmlns:dev="http://schemas.microsoft.com/maml/dev/2004/10">',
    ]

    for cmd_name in sorted(commands.keys()):
        cmd_meta = commands[cmd_name]
        type_name = cmd_meta.get("TypeName", "")
        class_key = f"T:{type_name}"
        class_doc = xml_members.get(class_key, {})

        synopsis = class_doc.get("summary", "").strip()
        description = class_doc.get("remarks", "").strip() or synopsis
        notes = class_doc.get("notes", "").strip()
        examples = class_doc.get("examples", [])
        params = cmd_meta.get("Parameters", {})
        output_types = cmd_meta.get("OutputTypes", [])
        verb = cmd_meta.get("Verb", "")
        noun = cmd_meta.get("Noun", "")

        lines.append("  <command:command>")
        lines.append("    <command:details>")
        lines.append(f"      <command:name>{_esc(cmd_name)}</command:name>")
        lines.append(f"      <command:verb>{_esc(verb)}</command:verb>")
        lines.append(f"      <command:noun>{_esc(noun)}</command:noun>")
        lines.append("      <maml:description>")
        lines.append(f"        <maml:para>{_esc(synopsis)}</maml:para>")
        lines.append("      </maml:description>")
        lines.append("    </command:details>")

        lines.append("    <maml:description>")
        for para in (description or synopsis).split("\n\n"):
            if para.strip():
                lines.append(f"      <maml:para>{_esc(para.strip())}</maml:para>")
        lines.append("    </maml:description>")

        # Syntax
        syntax_items = build_syntax(cmd_name, params)
        lines.append("    <command:syntax>")
        for _, _ in syntax_items:
            lines.append("      <command:syntaxItem>")
            lines.append(f"        <maml:name>{_esc(cmd_name)}</maml:name>")
            for pname, pdata in params.items():
                sets = pdata.get("Sets", {})
                binding = next(iter(sets.values()), {})
                required = "true" if binding.get("Required") else "false"
                pos = binding.get("Position")
                pos_str = str(pos) if pos is not None else "named"
                tname = short_type(pdata.get("FullType", ""), pdata.get("Type", "Object"))
                vfp = "true" if binding.get("ValueFromPipeline") else "false"
                lines.append(f'        <command:parameter required="{required}" pipelineInput="{vfp}" position="{pos_str}">')
                lines.append(f"          <maml:name>{_esc(pname)}</maml:name>")
                if not is_switch(pdata.get("FullType", "")):
                    lines.append(f'          <command:parameterValue required="{required}" variableLength="false">{_esc(tname)}</command:parameterValue>')
                lines.append("        </command:parameter>")
            lines.append("      </command:syntaxItem>")
        lines.append("    </command:syntax>")

        # Parameters
        lines.append("    <command:parameters>")
        for pname, pdata in params.items():
            prop_key = f"P:{type_name}.{pname}"
            prop_doc = xml_members.get(prop_key, {})
            param_desc = prop_doc.get("summary", "").strip()
            sets = pdata.get("Sets", {})
            binding = next(iter(sets.values()), {})
            required = "true" if binding.get("Required") else "false"
            pos = binding.get("Position")
            pos_str = str(pos) if pos is not None else "named"
            vfp = "true" if binding.get("ValueFromPipeline") else "false"
            tname = short_type(pdata.get("FullType", ""), pdata.get("Type", "Object"))
            aliases = " ".join(pdata.get("Aliases", []))
            lines.append(f'      <command:parameter required="{required}" pipelineInput="{vfp}" position="{pos_str}" aliases="{_esc(aliases)}">')
            lines.append(f"        <maml:name>{_esc(pname)}</maml:name>")
            lines.append("        <maml:description>")
            lines.append(f"          <maml:para>{_esc(param_desc)}</maml:para>")
            lines.append("        </maml:description>")
            if not is_switch(pdata.get("FullType", "")):
                lines.append(f'        <command:parameterValue required="{required}" variableLength="false">{_esc(tname)}</command:parameterValue>')
            lines.append(f"        <dev:type><maml:name>{_esc(tname)}</maml:name><maml:uri /></dev:type>")
            lines.append("        <dev:defaultValue>None</dev:defaultValue>")
            lines.append("      </command:parameter>")
        lines.append("    </command:parameters>")

        # Examples
        lines.append("    <command:examples>")
        if examples:
            for i, (code, prose) in enumerate(examples, 1):
                lines.append("      <command:example>")
                lines.append(f"        <maml:title>--- Example {i} ---</maml:title>")
                lines.append(f"        <dev:code>{_esc(code)}</dev:code>")
                lines.append("        <dev:remarks>")
                for para in prose.split("\n\n"):
                    if para.strip():
                        lines.append(f"          <maml:para>{_esc(para.strip())}</maml:para>")
                lines.append("        </dev:remarks>")
                lines.append("      </command:example>")
        lines.append("    </command:examples>")

        # Outputs
        lines.append("    <command:returnValues>")
        for ot in (output_types or ["System.Object"]):
            lines.append("      <command:returnValue>")
            lines.append(f"        <dev:type><maml:name>{_esc(ot)}</maml:name><maml:uri /></dev:type>")
            lines.append("        <maml:description><maml:para></maml:para></maml:description>")
            lines.append("      </command:returnValue>")
        lines.append("    </command:returnValues>")

        # Notes
        lines.append("    <maml:alertSet>")
        lines.append("      <maml:alert>")
        lines.append(f"        <maml:para>{_esc(notes)}</maml:para>")
        lines.append("      </maml:alert>")
        lines.append("    </maml:alertSet>")

        lines.append("    <command:relatedLinks />")
        lines.append("  </command:command>")

    lines.append("</helpItems>")
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module", default=str(repo_root / "Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1"))
    parser.add_argument("--xml", default=str(repo_root / "src/AMT.PowerShell.Common/bin/Debug/AMT.PowerShell.Common.xml"))
    parser.add_argument("--output-mdx", default=str(repo_root / "docs/docs/module/common/AMT.PowerShell.Common"))
    parser.add_argument("--output-maml", default=str(repo_root / "src/AMT.PowerShell.Common/Module/en-AU/AMT.PowerShell.Common-help.xml"))
    parser.add_argument("--dump-script", default=str(repo_root / "utils/dump-module-metadata.ps1"))
    args = parser.parse_args()

    module_path = Path(args.module)
    xml_path = Path(args.xml)
    output_mdx = Path(args.output_mdx)
    output_maml = Path(args.output_maml)
    dump_script = Path(args.dump_script)

    if not xml_path.exists():
        print(f"ERROR: XML doc file not found: {xml_path}", file=sys.stderr)
        print("Build the module first: dotnet build src/AMT.PowerShell.Common", file=sys.stderr)
        return 1
    if not module_path.exists():
        print(f"ERROR: Module not found: {module_path}", file=sys.stderr)
        return 1

    print(f"Parsing XML doc: {xml_path}")
    xml_members = parse_xml_doc(xml_path)
    print(f"  Found {len(xml_members)} documented members")

    print(f"Loading module metadata: {module_path}")
    commands = dump_metadata(module_path, dump_script)
    print(f"  Found {len(commands)} commands")

    print(f"Generating MDX to: {output_mdx}")
    for name, cmd_meta in sorted(commands.items()):
        emit_mdx(name, cmd_meta.get("Verb", ""), cmd_meta.get("Noun", ""),
                 cmd_meta, {}, xml_members, output_mdx)
    print(f"  Wrote {len(commands)} MDX pages")

    print(f"Generating MAML to: {output_maml}")
    emit_maml(commands, xml_members, output_maml)
    print("  Done")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
