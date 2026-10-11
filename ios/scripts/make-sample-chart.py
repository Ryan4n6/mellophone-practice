#!/usr/bin/env python3
"""Emit the MusicXML for the app's sample chart from a compact spec.
Durations are in eighths. 'r' is a rest; a whole bar rest is ('r', 8)."""
import sys
BARS = [
 [("F4",2),("A4",2),("C5",4)],
 [("C5",1),("D5",1),("C5",1),("Bb4",1),("A4",2),("F4",2)],
 [("G4",3),("A4",1),("Bb4",2),("G4",2)],
 [("A4",6),("r",2)],
 [("F4",2),("A4",2),("C5",4)],
 [("D5",1),("E5",1),("F5",2),("E5",2),("C5",2)],
 [("D5",3),("C5",1),("B4",2),("D5",2)],
 [("C5",8)],
 [("r",8)],
 [("r",8)],
 [("C5",2),("C5",1),("C5",1),("D5",2),("C5",2)],
 [("Bb4",2),("Bb4",1),("Bb4",1),("C5",2),("Bb4",2)],
 [("A4",1),("Bb4",1),("C5",1),("D5",1),("C5",2),("A4",2)],
 [("G4",6),("r",2)],
 [("A4",2),("C5",2),("F5",2),("E5",1),("D5",1)],
 [("C5",2),("G4",2),("F4",4)],
]
TYPES = {1:("eighth",0),2:("quarter",0),3:("quarter",1),4:("half",0),6:("half",1),8:("whole",0)}
HEAD = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<!--
  The SOURCE of ios/Mellophone/Resources/Sample Chart - Band Room March.pdf, the
  one chart the app ships (#28). Kept in the repo so the PDF can be regenerated
  instead of being an opaque binary nobody can check.

  This tune is OURS: sixteen bars written for this app in 2026, not an
  arrangement of anything. The app declares DOES_NOT_USE_THIRD_PARTY_CONTENT
  and this file is why that is still true with music in the bundle. Sam's
  charts are copyrighted arrangements and never go in git or in a build.

  It is written to exercise the chart reader: one flat in the key, a B natural
  against it in bar 7, beamed eighths, dotted quarters, a rest inside a bar and
  two whole bars of rest to count.

  Regenerate with:
    "/Applications/MuseScore 4.app/Contents/MacOS/mscore" \\
      -o "ios/Mellophone/Resources/Sample Chart - Band Room March.pdf" \\
      ios/scripts/sample-chart.musicxml

  B is flat by key signature, so a B flat carries <alter>-1</alter> and NO
  <accidental>, which stops MuseScore printing a redundant flat. The B natural
  in bar 7 carries <accidental>natural</accidental> because that one is printed.
-->
<score-partwise version="4.0">
  <work>
    <work-title>Band Room March</work-title>
  </work>
  <identification>
    <creator type="composer">Honk It Up! sample chart</creator>
  </identification>
  <part-list>
    <score-part id="P1">
      <part-name>Brass in treble clef</part-name>
    </score-part>
  </part-list>
  <part id="P1">
'''
def note(p, d, beam=None):
    t, dots = TYPES[d]
    if p == "r":
        if d == 8:
            return f'      <note><rest measure="yes"/><duration>{d}</duration></note>\n'
        return f'      <note><rest/><duration>{d}</duration><type>{t}</type>{"<dot/>"*dots}</note>\n'
    step, octave = p[0], p[-1]
    flat = "b" in p[1:-1]
    alter = "<alter>-1</alter>" if flat else ""
    acc = "<accidental>natural</accidental>" if p == "B4" else ""
    b = f'<beam number="1">{beam}</beam>' if beam else ""
    return (f'      <note><pitch><step>{step}</step>{alter}<octave>{octave}</octave></pitch>'
            f'<duration>{d}</duration><type>{t}</type>{"<dot/>"*dots}{acc}{b}</note>\n')
out = HEAD
for i, bar in enumerate(BARS, 1):
    assert sum(d for _, d in bar) == 8, i
    out += f'    <measure number="{i}">\n'
    if i == 1:
        out += ('      <attributes>\n        <divisions>2</divisions>\n        <key><fifths>-1</fifths></key>\n'
                '        <time><beats>4</beats><beat-type>4</beat-type></time>\n'
                '        <clef><sign>G</sign><line>2</line></clef>\n      </attributes>\n')
    pos = 0; beams = [None]*len(bar); starts = []
    for p, d in bar:
        starts.append(pos); pos += d
    j = 0
    while j < len(bar):
        if bar[j][1] == 1 and bar[j][0] != "r":
            k = j
            while k + 1 < len(bar) and bar[k+1][1] == 1 and bar[k+1][0] != "r" and starts[k+1] // 4 == starts[j] // 4:
                k += 1
            if k > j:
                for m in range(j, k+1):
                    beams[m] = "begin" if m == j else ("end" if m == k else "continue")
            j = k + 1
        else:
            j += 1
    for (p, d), b in zip(bar, beams):
        out += note(p, d, b)
    if i == len(BARS):
        out += '      <barline location="right"><bar-style>light-heavy</bar-style></barline>\n'
    out += '    </measure>\n'
out += '  </part>\n</score-partwise>\n'
open(sys.argv[1], "w").write(out)
