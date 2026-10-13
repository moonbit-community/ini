///|
test "parse/basic_ini" {
  let input = "[section1]\nkey1=value1\nkey2 = value2\n\n[section2]\nkey3=value3"
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="section1", "key1"),
    content=(
      #|Some("value1")
    ),
  )
  debug_inspect(
    ini.get(section="section1", "key2"),
    content=(
      #|Some("value2")
    ),
  )
  debug_inspect(
    ini.get(section="section2", "key3"),
    content=(
      #|Some("value3")
    ),
  )
}

///|
test "parse/global_section" {
  let input = "global_key=global_value\n[section1]\nkey1=value1"
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get("global_key"),
    content=(
      #|Some("global_value")
    ),
  )
  debug_inspect(
    ini.get(section="section1", "key1"),
    content=(
      #|Some("value1")
    ),
  )
}

///|
test "parse/case_insensitive_default" {
  let input = "[Section]\nKey=Value"
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="section", "key"),
    content=(
      #|Some("Value")
    ),
  )
}

///|
test "parse/case_sensitive" {
  let input = "[Section]\nKey=Value"
  let ini = @ini.parse(input, is_case_sensitive=true)
  debug_inspect(
    ini.get(section="Section", "Key"),
    content=(
      #|Some("Value")
    ),
  )
  debug_inspect(ini.get(section="section", "key"), content="None")
}

///|
test "parse/comments" {
  // let input = "; comment line\n# another comment\nglobal=value1 ; comment after value\n[section] # comment after section\nkey=value2 # comment"
  let input =
    #|; comment line
    #|# another comment
    #|global=value1 ; comment after value
    #|[section] # comment after section
    #|key=value2 # comment
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get("global"),
    content=(
      #|Some("value1")
    ),
  )
  debug_inspect(
    ini.get(section="section", "key"),
    content=(
      #|Some("value2")
    ),
  )
}

///|
test "parse/whitespace_handling" {
  let input = "  global_key  =  value1  \n[  section 1  ]\n  key 1  =  value 2  "
  let ini = @ini.parse(input)
  // Whitespace around keys and section names is trimmed by default (due to lowercasing/logic)
  // Whitespace within values is preserved unless quoted logic changes it.
  // Whitespace around '=' is ignored.
  debug_inspect(
    ini.get("global_key"),
    content=(
      #|Some("value1  ")
    ),
  )
  debug_inspect(
    ini.get(section="section 1", "key 1"),
    content=(
      #|Some("value 2  ")
    ),
  )
}

///|
test "parse/quoted_values" {
  let input = "[quotes]\nkey1='single quoted'\nkey2=\"double quoted\"\nkey3='  leading/trailing spaces  '\nkey4=\"  leading/trailing spaces  \""
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="quotes", "key1"),
    content=(
      #|Some("single quoted")
    ),
  )
  debug_inspect(
    ini.get(section="quotes", "key2"),
    content=(
      #|Some("double quoted")
    ),
  )
  // Quotes themselves are removed, but spaces inside are preserved.
  debug_inspect(
    ini.get(section="quotes", "key3"),
    content=(
      #|Some("  leading/trailing spaces  ")
    ),
  )
  debug_inspect(
    ini.get(section="quotes", "key4"),
    content=(
      #|Some("  leading/trailing spaces  ")
    ),
  )
}

///|
test "parse/empty_values" {
  let input = "[empty]\nkey1=\nkey2=\"  \"\nkey3=''\nkey4=\"\""
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="empty", "key1"),
    content=(
      #|Some("")
    ),
  )
  debug_inspect(
    ini.get(section="empty", "key2"),
    content=(
      #|Some("  ")
    ),
  )
  debug_inspect(
    ini.get(section="empty", "key3"),
    content=(
      #|Some("")
    ),
  )
  debug_inspect(
    ini.get(section="empty", "key4"),
    content=(
      #|Some("")
    ),
  )
}

///|
test "parse/overwrite_key" {
  let input = "[section]\nkey=value1\nkey=value2"
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="section", "key"),
    content=(
      #|Some("value2")
    ),
  )
}

///|
test "parse/multiple_chunks" {
  let chunk1 = "[section1]\nkey1="
  let chunk2 = "value1\n[section"
  let chunk3 = "2]\nkey2=value2"
  let state = @ini.IniParseState::new()
  let state = state.parse(chunk1)
  let state = state.parse(chunk2)
  let state = state.parse(chunk3)
  let ini = state.finish()
  debug_inspect(
    ini.get(section="section1", "key1"),
    content=(
      #|Some("value1")
    ),
  )
  debug_inspect(
    ini.get(section="section2", "key2"),
    content=(
      #|Some("value2")
    ),
  )
}

///|
test "parse/error_unclosed_section" {
  let input = "[section"
  assert_true(
    try @ini.parse(input) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "parse/error_unexpected_equal" {
  let input = "=value"
  assert_true(
    try @ini.parse(input) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let input = "[section]\n=value"
  assert_true(
    try @ini.parse(input) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "panic parse/error_empty_section_name" {
  let input = "[]\nkey=value"
  ignore(@ini.parse(input))
}

///|
test "parse/error_value_without_section_or_key" {
  // This case is tricky because the parser might interpret 'value' as a key
  // Let's test assignment without a preceding key
  let input = "[section]\n=value"
  try @ini.parse(input) catch {
    _ => assert_true(true)
  } noraise {
    _ => assert_true(false)
  }
  // The ValueWithoutSection error is harder to trigger directly with current logic,
  // as '=' is required to start reading a value, which implies a key was being read.
  // It might occur internally if state management had a bug.
}

///|
test "parse/error_quote_mismatch" {
  let input = "[section]\nkey='value\""
  assert_true(
    try @ini.parse(input) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let input = "[section]\nkey=\"value'\""
  assert_true(
    try @ini.parse(input) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "parse/error_quote_not_closed" {
  let input = "[section]\nkey='value"
  let result = Ok(@ini.parse(input)) catch { _ => Err(()) }
  assert_true(result is Err(_))
  let input = "[section]\nkey=\"value"
  let result = Ok(@ini.parse(input)) catch { _ => Err(()) }
  assert_true(result is Err(_))
}

///|
test "parse/escape_basic" {
  let input =
    #|[esc]
    #|key=\\ \' \" \b \t \r \n \; \# \= \:
  let ini = @ini.parse(input)
  let expect = "\\ \' \" \b \t \r \n ; # = :"
  inspect(ini.get(section="esc", "key").unwrap(), content=expect)
}

///|
test "parse/escape_hex_unicode" {
  let input =
    #|[hex]
    #|key=abc\x4e2d\x6587def
  let ini = @ini.parse(input)
  // \x4e2d = '中', \x6587 = '文'
  inspect(ini.get(section="hex", "key").unwrap(), content="abc中文def")
}

///|
test "parse/escape_mixed" {
  let input =
    #|[mix]
    #|key=\tTab\nNewline\x0021!
  let ini = @ini.parse(input)
  inspect(
    ini.get(section="mix", "key").unwrap(),
    content="\tTab\nNewline\u0021!",
  )
}

///|
test "parse/escape_in_quotes" {
  let input = "[q]\nkey1='\\n'\nkey2=\"\\t\"\nkey3='\\x4e2d'\nkey4=\"\\x6587\""
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="q", "key1"),
    content=(
      #|Some("\n")
    ),
  )
  debug_inspect(
    ini.get(section="q", "key2"),
    content=(
      #|Some("\t")
    ),
  )
  debug_inspect(
    ini.get(section="q", "key3"),
    content=(
      #|Some("中")
    ),
  )
  debug_inspect(
    ini.get(section="q", "key4"),
    content=(
      #|Some("文")
    ),
  )
}

///|
test "parse/escape_invalid_hex" {
  let input = "[badhex]\nkey=abc\\x12gZ"
  let ini = @ini.parse(input)
  // meet the non-hex character `g`, escape fails, output as-is
  debug_inspect(
    ini.get(section="badhex", "key"),
    content=(
      #|Some("abc\\x12gZ")
    ),
  )
}

///|
test "parse/escape_incomplete_hex" {
  let input = "[incomplete]\nkey=abc\\x12"
  let ini = @ini.parse(input)
  // less than 4 digits, output as-is
  debug_inspect(
    ini.get(section="incomplete", "key"),
    content=(
      #|Some("abc\\x12")
    ),
  )
}

///|
test "parse/escape_unknown" {
  let input = "[unknown]\nkey=abc\\zdef"
  let ini = @ini.parse(input)
  // unknown escape, z is output as-is
  debug_inspect(
    ini.get(section="unknown", "key"),
    content=(
      #|Some("abczdef")
    ),
  )
}

///|
test "parse/line_continuation_basic" {
  let input =
    #|[multi]
    #|key=foo\
    #|bar\
    #|baz
  let ini = @ini.parse(input)
  // Should join lines as "foo\nbar\nbaz"
  debug_inspect(
    ini.get(section="multi", "key"),
    content=(
      #|Some("foo\nbar\nbaz")
    ),
  )
}

///|
test "parse/line_continuation_with_spaces" {
  let input =
    #|[multi]
    #|key=foo \
    #| bar \
    #| baz
  let ini = @ini.parse(input)
  // Spaces before backslash are preserved
  debug_inspect(
    ini.get(section="multi", "key"),
    content=(
      #|Some("foo \n bar \n baz")
    ),
  )
}

///|
test "parse/line_continuation_and_comment" {
  let input =
    #|[multi]
    #|key=foo\
    #|bar ; comment
    #|key2=abc\
    #|\# not a comment
    #|key3=1\
    #|2\
    #|3
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="multi", "key"),
    content=(
      #|Some("foo\nbar")
    ),
  )
  debug_inspect(
    ini.get(section="multi", "key2"),
    content=(
      #|Some("abc\n# not a comment")
    ),
  )
  debug_inspect(
    ini.get(section="multi", "key3"),
    content=(
      #|Some("1\n2\n3")
    ),
  )
}

///|
test "parse/line_continuation_escape_and_quote" {
  let input =
    #|[multi]
    #|key='foo\
    #|bar'
    #|key2="abc\
    #|def"
  let ini = @ini.parse(input)
  debug_inspect(
    ini.get(section="multi", "key"),
    content=(
      #|Some("foo\nbar")
    ),
  )
  debug_inspect(
    ini.get(section="multi", "key2"),
    content=(
      #|Some("abc\ndef")
    ),
  )
}
