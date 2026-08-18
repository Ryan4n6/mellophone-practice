#!/usr/bin/env python3
"""
sync-note-data.py: generate the Swift note tables from index.html.

CLAUDE.md says index.html is the source of truth for the note and scale data,
for both products. Issue #2 says the tables "should be lifted, not retyped from
memory". So they are not retyped at all: this script parses the NOTES and SCALES
arrays out of the page and emits Mellophone/Model/NoteData.swift.

A single wrong frequency or fingering is close to invisible in review (it is one
digit in a table of 38 rows) and completely wrong in the hand, so the way to get
it right is to never transcribe it by hand in the first place.

Usage:
    python3 scripts/sync-note-data.py            # regenerate the Swift file
    python3 scripts/sync-note-data.py --check    # fail if it is out of date

--check is the one to run before shipping: it proves the Swift tables still
match the page rather than assuming nobody edited one without the other.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HTML = ROOT.parent / "index.html"
SWIFT = ROOT / "Mellophone" / "Model" / "NoteData.swift"

NOTE_RE = re.compile(
    r'\{\s*name:\s*"(?P<name>[^"]+)"\s*,'
    r'\s*freq:\s*(?P<freq>[0-9.]+)\s*,'
    r'\s*staffPos:\s*(?P<staff>-?[0-9]+)\s*,'
    r'\s*finger:\s*"(?P<finger>[^"]*)"\s*,'
    r'\s*accidental:\s*"(?P<acc>[^"]*)"\s*,?\s*\}'
)

SCALE_RE = re.compile(
    r'\{\s*name:\s*"(?P<name>[^"]+)"\s*,\s*notes:\s*\[(?P<notes>[^\]]*)\]\s*\}'
)


def slice_array(source: str, declaration: str) -> str:
    """Return the text between the brackets of `const <declaration> = [ ... ];`."""
    start = source.index(declaration)
    open_bracket = source.index("[", start)
    depth = 0
    for i in range(open_bracket, len(source)):
        if source[i] == "[":
            depth += 1
        elif source[i] == "]":
            depth -= 1
            if depth == 0:
                return source[open_bracket : i + 1]
    raise ValueError(f"unterminated array for {declaration}")


def parse(source: str):
    notes_src = slice_array(source, "const NOTES")
    notes = [m.groupdict() for m in NOTE_RE.finditer(notes_src)]
    if not notes:
        raise ValueError("no NOTES parsed; the table's shape in index.html changed")

    scales_src = slice_array(source, "const SCALES")
    scales = []
    for m in SCALE_RE.finditer(scales_src):
        names = re.findall(r'"([^"]+)"', m.group("notes"))
        scales.append({"name": m.group("name"), "notes": names})
    if not scales:
        raise ValueError("no SCALES parsed; the table's shape in index.html changed")

    verify_fingerings(notes)
    return notes, scales


# The open (no valve) written notes of a three-valve brass instrument, and what
# each valve combination lowers a partial by. This is the whole chart: there is
# nothing to remember and nothing to look up.
OPEN_PARTIALS = ["C4", "G4", "C5", "E5", "G5", "C6"]
VALVES_BY_SEMITONE = {0: "Open", 1: "2", 2: "1", 3: "1+2", 4: "2+3", 5: "1+3", 6: "1+2+3"}
PITCH_CLASSES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
ENHARMONIC = {"Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb"}


def midi_number(name: str) -> int:
    match = re.match(r"^([A-G][b#]?)(\d)$", name)
    if not match:
        raise ValueError(f"cannot parse note name {name!r}")
    pitch_class, octave = match.group(1), int(match.group(2))
    pitch_class = ENHARMONIC.get(pitch_class, pitch_class)
    return PITCH_CLASSES.index(pitch_class) + 12 * (octave + 1)


def expected_fingering(name: str) -> str:
    """The fingering physics dictates, or None if three valves cannot reach it."""
    note = midi_number(name)
    best = None
    for partial in OPEN_PARTIALS:
        distance = midi_number(partial) - note
        if 0 <= distance <= 6 and (best is None or distance < best):
            best = distance
    return VALVES_BY_SEMITONE[best] if best is not None else None


def verify_fingerings(notes) -> None:
    """Refuse to generate from a table that disagrees with the instrument.

    Seven rows were wrong once (issue #9): F#3, Gb3, G3 and Ab3 carried the
    fingering of a neighbouring note, C#4 and Db4 used the fingering that is only
    correct an octave higher, and F3 was listed at all despite being seven
    semitones below the C4 partial when three valves reach six. The drill prints
    these as corrective feedback, so wrong values actively teach wrong fingerings.

    This table is fully derivable, so it should never again be a list of
    remembered facts.
    """
    problems = []
    for note in notes:
        expected = expected_fingering(note["name"])
        if expected is None:
            problems.append(f"{note['name']}: no three-valve fingering exists, it should not be in the table")
        elif note["finger"] != expected:
            problems.append(f"{note['name']}: table says {note['finger']!r}, physics says {expected!r}")
    if problems:
        raise SystemExit(
            "FAIL: the fingering table in index.html disagrees with the instrument:\n  "
            + "\n  ".join(problems)
        )


def accidental_case(symbol: str) -> str:
    return {"": ".natural", "#": ".sharp", "b": ".flat"}[symbol]


def render(notes, scales) -> str:
    lines = []
    add = lines.append

    add("// GENERATED FILE. Do not edit by hand.")
    add("//")
    add("// Produced by ios/scripts/sync-note-data.py from index.html, which is the")
    add("// source of truth for the note and scale data in BOTH products. To correct a")
    add("// frequency or a fingering, edit index.html and re-run:")
    add("//")
    add("//     python3 ios/scripts/sync-note-data.py")
    add("//")
    add("// Run it with --check to prove the two are still in sync.")
    add("")
    add("import Foundation")
    add("")
    add("extension Note {")
    add("    /// Every note the app knows about, including both spellings of each")
    add("    /// enharmonic pair, because the two spellings sit on different lines of")
    add("    /// the staff and the drill accepts either as an answer.")
    add(f"    static let all: [Note] = [")
    width_name = max(len(n["name"]) for n in notes) + 3
    width_finger = max(len(n["finger"]) for n in notes) + 3
    for n in notes:
        name = f'"{n["name"]}",'.ljust(width_name)
        freq = f'{n["freq"]},'.ljust(9)
        staff = f'{n["staff"]},'.ljust(5)
        finger = f'"{n["finger"]}",'.ljust(width_finger)
        add(
            f"        Note(name: {name} frequency: {freq} "
            f"staffPosition: {staff} fingering: {finger} "
            f"accidental: {accidental_case(n['acc'])}),"
        )
    add("    ]")
    add("}")
    add("")
    add("extension Scale {")
    add("    /// The scales and exercises from the web version, in its order.")
    add("    ///")
    add("    /// Names carry both the concert and the written pitch because the")
    add("    /// mellophone is in F and a director calls the concert key out loud while")
    add("    /// the player reads the written one.")
    add("    static let all: [Scale] = [")
    for s in scales:
        joined = ", ".join(f'"{x}"' for x in s["notes"])
        add(f'        Scale(name: "{s["name"]}", noteNames: [{joined}]),')
    add("    ]")
    add("}")
    add("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the Swift file is stale")
    args = parser.parse_args()

    source = HTML.read_text(encoding="utf-8")
    notes, scales = parse(source)
    generated = render(notes, scales)

    if args.check:
        if not SWIFT.exists():
            print(f"FAIL: {SWIFT} does not exist", file=sys.stderr)
            return 1
        if SWIFT.read_text(encoding="utf-8") != generated:
            print(
                "FAIL: NoteData.swift is out of sync with index.html.\n"
                "      Run: python3 ios/scripts/sync-note-data.py",
                file=sys.stderr,
            )
            return 1
        print(f"OK: {len(notes)} notes, {len(scales)} scales, Swift matches index.html")
        return 0

    SWIFT.parent.mkdir(parents=True, exist_ok=True)
    SWIFT.write_text(generated, encoding="utf-8")
    print(f"wrote {SWIFT.relative_to(ROOT.parent)}: {len(notes)} notes, {len(scales)} scales")
    return 0


if __name__ == "__main__":
    sys.exit(main())
