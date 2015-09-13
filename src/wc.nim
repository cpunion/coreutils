import os, memfiles, parseopt2, strutils, sequtils, posix, math

type
  Stat = object
    bytes: BiggestInt
    chars: BiggestInt
    words: BiggestInt
    lines: BiggestInt
    maxLineLength: int
    failed: bool

  StatType = enum
    Bytes, Chars, Words, Lines, MaxLineLength

  Option = object
    maxLineLength: bool
    bytes: bool
    chars: bool
    words: bool
    lines: bool
    fromStdin: bool
    filenames: seq[string]

proc `+`*(a: Stat, b: Stat): Stat =
  result.bytes = a.bytes + b.bytes
  result.chars = a.chars + b.chars
  result.words = a.words + b.words
  result.lines = a.lines + b.lines
  result.maxLineLength = a.maxLineLength + b.maxLineLength

proc `+=`(a: var Stat, b: Stat) =
  a.bytes += b.bytes
  a.chars += b.chars
  a.words += b.words
  a.lines += b.lines
  a.maxLineLength += b.maxLineLength

proc isBasic(c: char): bool =
  case c
  of
    '\t', '\v', '\f',
    ' ', '!', '"', '#', '%',
    '&', '\'', '(', ')', '*',
    '+', ',', '-', '.', '/',
    '0', '1', '2', '3', '4',
    '5', '6', '7', '8', '9',
    ':', ';', '<', '=', '>',
    '?',
    'A', 'B', 'C', 'D', 'E',
    'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y',
    'Z',
    '[', '\\', ']', '^', '_',
    'a', 'b', 'c', 'd', 'e',
    'f', 'g', 'h', 'i', 'j',
    'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't',
    'u', 'v', 'w', 'x', 'y',
    'z', '{', '|', '}', '~':
      return true
  else:
      return false

proc emitStdinNote() =
  echo "With no FILE, or when FILE is -, read standard input."

const HELP_OPTION_DESCRIPTION    = "      --help     display this help and exit"
const VERSION_OPTION_DESCRIPTION = "      --version  output version information and exit"

proc writeHelp(status: int) =
  echo """
Usage: $1 [OPTION]... [FILE]...
  or:  $1 [OPTION]... --files0-from=F
Print newline, word, and byte counts for each FILE, and a total line if
more than one FILE is specified.  A word is a non-zero-length sequence of
characters delimited by white space.""" % paramStr(0)

  emit_stdin_note()

  echo """
The options below may be used to select which counts are printed, always in
the following order: newline, word, character, byte, maximum line length.
  -c, --bytes            print the byte counts
  -m, --chars            print the character counts
  -l, --lines            print the newline counts
      --files0-from=F    read input from the files specified by
                           NUL-terminated names in file F;
                           If F is - then read names from standard input
  -L, --max-line-length  print the maximum display width
  -w, --words            print the word counts"""

  echo HELP_OPTION_DESCRIPTION
  echo VERSION_OPTION_DESCRIPTION

  exitnow(status)

proc writeVersion() =
  echo "1.0.0"

proc writeFiles0Error() =
  stderr.write("""
file operands cannot be combined with --files0-from
Try 'wc --help' for more information.""")

proc readNames(filename: string): seq[string] =
  var lines = readFile(filename).splitLines()
  lines.mapIt(it.strip)
  result = @[]
  for line in lines:
    if line.len > 0:
      result.add(line)

proc parseOption(): Option =
  result.filenames = @[]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      result.filenames.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": writeHelp(0)
      of "version", "v": writeVersion()
      of "bytes", "c": result.bytes = true
      of "chars", "m": result.chars = true
      of "words", "w": result.words = true
      of "lines", "l": result.lines = true
      of "max-line-length", "L": result.maxLineLength = true
      of "files0-from":
        if val == "-":
          result.fromStdin = true
        else:
          stderr.write("--files0-from not implemented.\l")
          exitnow(1)
          result.filenames = readNames(val)
      else: assert(false)
    of cmdEnd: assert(false) # cannot happen

  if result.fromStdin and result.filenames.len > 0:
    writeFiles0Error()
    exitnow(1)

  if result.filenames.len == 0:
    result.fromStdin = true

  if not (result.bytes or result.chars or result.words or result.lines or result.maxLineLength):
    result.bytes = true
    result.words = true
    result.lines = true

proc printStat(filename: string, width: int, stat: Stat, option: Option) =
  if (option.lines):
    stdout.write(align($stat.lines, width), ' ')
  if (option.words):
    stdout.write(align($stat.words, width), ' ')
  if (option.chars):
    stdout.write(align($stat.chars, width), ' ')
  if (option.bytes):
    stdout.write(align($stat.bytes, width), ' ')
  if (option.maxLineLength):
    stdout.write(align($stat.maxLineLength, width), ' ')
  stdout.write(filename, '\l')

proc wcharBytes(c: char): int =
  if ord(c) <=% 127: inc(result)
  elif ord(c) shr 5 == 0b110: inc(result, 2)
  elif ord(c) shr 4 == 0b1110: inc(result, 3)
  elif ord(c) shr 3 == 0b11110: inc(result, 4)
  elif ord(c) shr 2 == 0b111110: inc(result, 5)
  elif ord(c) shr 1 == 0b1111110: inc(result, 6)
  else: inc(result)

proc wc(filename: string, option: Option): Stat =
  let memfilesAvailable = not option.chars and not option.fromStdin

  if option.bytes and memfilesAvailable:
    try:
      result.bytes = getFileSize(filename)
    except OSError:
      stderr.write("$1: $2: $3\l" % [paramStr(0), filename, getCurrentExceptionMsg()])
      result.failed = true
      return

  try:
    if not memfilesAvailable:
      var file: cint
      if filename == nil:
        file = stdin.getFileHandle()
      else:
        while true:
          file = open(filename, O_RDONLY)
          if file == -1:
            if osLastError().cint == EINTR:
              continue
            else:
              raiseOSError(osLastError())
          break

      var inWord: bool
      var inShift: bool
      var wideChar: int16
      var buffer: array[0..16383, char]
      var skip: int
      var lineLength: int

      while true:
        let readBytes = file.read(addr(buffer[0]), buffer.len)
        if readBytes == -1:
          if osLastError().cint == EINTR:
            continue
          else:
            raiseOSError(osLastError())
        elif readBytes == 0:
          break

        result.bytes += readBytes

        var p: ptr char
        var ending: ptr char
        ending = cast[ptr char](cast[int](addr(buffer[0])) + readBytes)

        if readBytes >= skip:
          p = cast[ptr char](cast[int](addr(buffer[0])) + skip)
        else:
          p = cast[ptr char](cast[int](addr(buffer[0])) + readBytes)
          skip -= readBytes
          continue

        while p != ending:
          let c = p[]

          if c.isBasic:
            skip = 1
          else:
            skip = wcharBytes(c)
          result.chars += 1

          if c == '\l':
            result.lines += 1
            if lineLength > result.maxLineLength:
              result.maxLineLength = lineLength
            lineLength = 0
          else:
            lineLength += 1

          let isWhiteSpace = (c == ' ') or (c >= 9.char and c <= 13.char)

          if inWord:
            if isWhiteSpace:
              inWord = false
          else:
            if not isWhiteSpace:
              inWord = true
              result.words += 1

          let remain = cast[int](ending) - cast[int](p)
          if remain >= skip:
            p = cast[ptr char](cast[int](p) + skip)
            skip = 0
          else:
            p = ending
            skip -= remain

    else:
      var file = memfiles.open(filename)
      defer: file.close

      for slice in memSlices(file):
        inc(result.lines)

        if option.words:
          var last = -1
          for i in 0..(slice.size - 1):
            let c = cast[ptr char](cast[int](slice.data) + i)[]
            if c == ' ':
              if i - 1 > last:
                inc(result.words)
              last = i
          if slice.size - 1 > last:
            inc(result.words)

        if option.maxLineLength:
          if slice.size > result.maxLineLength:
            result.maxLineLength = slice.size
  except OSError:
    stderr.write("$1: $2: $3\l" % [paramStr(0), filename, getCurrentExceptionMsg()])
    result.failed = true

let option = parseOption()

if option.fromStdin:
  let stat = wc(nil, option)
  if not stat.failed:
    let width = 7
    printStat(nil, width, stat, option)
else:
  var maxBytes: BiggestInt = 0
  for i in 0..(option.filenames.len - 1):
    try:
      let bytes = getFileSize(option.filenames[i])
      if bytes > maxBytes:
        maxBytes = bytes
    except OSError:
      discard

  let width = maxBytes.float.log10.int + 1
  var totalStat: Stat

  for filename in option.filenames:
    let stat = wc(filename, option)
    if not stat.failed:
      totalStat += stat
      printStat(filename, width, stat, option)

  if option.filenames.len > 1:
    printStat("total", width, totalStat, option)
