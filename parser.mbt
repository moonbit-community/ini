///|
pub suberror IniParseError {
  UnexpectedEqualSign(line~ : Int, col~ : Int)
  EmptySection(line~ : Int, col~ : Int)
  UnclosedSection(line~ : Int, col~ : Int)
  ValueWithoutSection(line~ : Int, col~ : Int)
  QuoteMismatch(line~ : Int, col~ : Int)
  QuoteNotClosed(line~ : Int, col~ : Int)
}

///|
priv struct ParseContext {
  mut current_section : Section
  sections : @hashmap.HashMap[Section, @hashmap.HashMap[Key, Value]]
  mut line : Int
  mut col : Int
  mut key : String
  buffer : StringBuilder
}

///|
priv enum ReadingValueState {
  None
  SingleQuote
  DoubleQuote
}

///|
impl Show for ReadingValueState with output(self, logger) {
  match self {
    ReadingValueState::None => logger.write_string("None")
    ReadingValueState::SingleQuote => logger.write_string("SingleQuote")
    ReadingValueState::DoubleQuote => logger.write_string("DoubleQuote")
  }
}

///|
priv enum ParsePhase {
  Start
  ReadingSection
  ReadingKey
  ReadingValue(ReadingValueState)
  InComment
}

///|
impl Show for ParsePhase with output(self, logger) {
  match self {
    ParsePhase::Start => logger.write_string("Start")
    ParsePhase::ReadingSection => logger.write_string("ReadingSection")
    ParsePhase::ReadingKey => logger.write_string("ReadingKey")
    ParsePhase::ReadingValue(state) => {
      logger.write_string("ReadingValue(")
      state.output(logger)
      logger.write_string(")")
    }
    ParsePhase::InComment => logger.write_string("InComment")
  }
}

///|
priv struct EscapeStateHex {
  hex : StringBuilder
  mut left : Int
}

///|
priv enum EscapeState {
  None
  Escape
  Hex(EscapeStateHex)
}

///|
struct IniParseState {
  ctx : ParseContext
  mut phase : ParsePhase
  is_case_sensitive : Bool
  mut escape_state : EscapeState
  mut last_char_is_backslash : Bool // Track if last char is an unescaped backslash
}

///|
fn IniParseState::lower_if_needed(self : IniParseState, s : String) -> String {
  if self.is_case_sensitive {
    s
  } else {
    s.to_lower()
  }
}

///|
pub fn IniParseState::new(is_case_sensitive? : Bool = false) -> IniParseState {
  IniParseState::{
    ctx: ParseContext::{
      current_section: Section::Global,
      sections: @hashmap.from_array([(Section::Global, @hashmap.new())]),
      line: 1,
      col: 1,
      key: "",
      buffer: StringBuilder::new(),
    },
    phase: ParsePhase::Start,
    is_case_sensitive,
    escape_state: EscapeState::None,
    last_char_is_backslash: false,
  }
}

///|
pub fn parse(
  str : String,
  is_case_sensitive? : Bool = false,
) -> IniFile raise IniParseError {
  IniParseState::new(is_case_sensitive~).parse(str).finish()
}

///|
pub fn IniParseState::parse(
  self : IniParseState,
  chunk : String,
) -> IniParseState raise IniParseError {
  let mut self = self
  for c in chunk.iter() {
    self = self.process_char(c)
  }
  self
}

///|
pub fn IniParseState::finish(
  self : IniParseState,
) -> IniFile raise IniParseError {
  let self = self.process_char('\n')
  IniFile::new_with_sections(
    self.ctx.sections,
    is_case_sensitive=self.is_case_sensitive,
  )
}

///|
fn IniParseState::process_char(
  self : IniParseState,
  c : Char,
) -> IniParseState raise IniParseError {
  self.update_position(c)
  match self.phase {
    ParsePhase::Start => self.handle_start(c)
    ParsePhase::ReadingSection => self.handle_section_char(c)
    ParsePhase::ReadingKey => self.handle_key_char(c)
    ParsePhase::ReadingValue(_) => self.handle_value_char(c)
    ParsePhase::InComment => self.handle_comment(c)
  }
}

///|
fn IniParseState::update_position(self : IniParseState, c : Char) -> Unit {
  if c == '\n' {
    self.ctx.line += 1
    self.ctx.col = 1
  } else {
    self.ctx.col += 1
  }
}

///|
fn IniParseState::handle_start(
  self : IniParseState,
  c : Char,
) -> IniParseState raise IniParseError {
  match c {
    '[' => {
      self.phase = ReadingSection
      self.ctx.buffer.reset()
      self
    }
    '#' | ';' => {
      self.phase = InComment
      self
    }
    '=' =>
      raise IniParseError::UnexpectedEqualSign(
        line=self.ctx.line,
        col=self.ctx.col,
      )
    '\n' => self.reset_line()
    _ if c.is_whitespace() => self
    _ => {
      self.phase = ReadingKey
      self.ctx.buffer.write_char(c)
      self
    }
  }
}

///|
fn IniParseState::handle_section_char(
  self : IniParseState,
  c : Char,
) -> IniParseState raise IniParseError {
  match c {
    '#' | ';' =>
      raise IniParseError::UnclosedSection(line=self.ctx.line, col=self.ctx.col)
    ']' => {
      if self.ctx.buffer.is_empty() {
        raise IniParseError::EmptySection(line=self.ctx.line, col=self.ctx.col)
      }
      let section_name = self.ctx.buffer.to_string().trim()
      let section_name = self.lower_if_needed(section_name.to_string())
      self.ctx.current_section = Section::NamedSection(section_name)
      if !self.ctx.sections.contains(self.ctx.current_section) {
        self.ctx.sections.set(self.ctx.current_section, @hashmap.new())
      }
      self.phase = Start
      self
    }
    '\n' =>
      raise IniParseError::UnclosedSection(line=self.ctx.line, col=self.ctx.col)
    _ => {
      self.ctx.buffer.write_char(c)
      self
    }
  }
}

///|
fn IniParseState::handle_key_char(
  self : IniParseState,
  c : Char,
) -> IniParseState raise IniParseError {
  match c {
    '=' => {
      if self.ctx.buffer.is_empty() {
        raise IniParseError::UnexpectedEqualSign(
          line=self.ctx.line,
          col=self.ctx.col,
        )
      }
      let key = self.ctx.buffer.to_string().trim()
      let key = self.lower_if_needed(key.to_string())
      self.ctx.buffer.reset()
      self.phase = ReadingValue(ReadingValueState::None)
      self.ctx.key = key
      self
    }
    '\n' | ';' | '#' => {
      let key = self.ctx.buffer.to_string().trim()
      if !key.is_empty() {
        let key = self.lower_if_needed(key.to_string())
        self.ctx.key = key
        self.ctx.buffer.reset()
        ignore(self.commit_value())
      }
      self.reset_line()
    }
    _ if c.is_whitespace() =>
      match self.ctx.buffer.is_empty() {
        true => self
        false => {
          self.ctx.buffer.write_char(c)
          self
        }
      }
    _ => {
      self.ctx.buffer.write_char(c)
      self
    }
  }
}

///|
fn IniParseState::handle_value_char(
  self : IniParseState,
  c : Char,
) -> IniParseState raise IniParseError {
  match self.escape_state {
    EscapeState::Hex(state) =>
      if c.is_digit(16) {
        state.hex.write_char(c)
        state.left -= 1
        if state.left == 0 {
          // it must be 4 digits hex
          let code = try! @strconv.parse_int(state.hex.to_string(), base=16)
          self.ctx.buffer.write_char(Int::unsafe_to_char(code))
          self.escape_state = EscapeState::None
          self.last_char_is_backslash = false
        }
        return self
      } else {
        self.ctx.buffer.write_string("\\x" + state.hex.to_string())
        self.escape_state = EscapeState::None
        self.last_char_is_backslash = false
        // handle the current character
      }
    EscapeState::Escape => {
      match c {
        '\\' => self.ctx.buffer.write_char('\\')
        '\'' => self.ctx.buffer.write_char('\'')
        '"' => self.ctx.buffer.write_char('"')
        '0' => self.ctx.buffer.write_char('\u0000')
        'a' => self.ctx.buffer.write_char('\u0007')
        'b' => self.ctx.buffer.write_char('\b')
        't' => self.ctx.buffer.write_char('\t')
        'r' => self.ctx.buffer.write_char('\r')
        'n' => self.ctx.buffer.write_char('\n')
        ';' => self.ctx.buffer.write_char(';')
        '#' => self.ctx.buffer.write_char('#')
        '=' => self.ctx.buffer.write_char('=')
        ':' => self.ctx.buffer.write_char(':')
        'x' => {
          let hex = StringBuilder::new()
          self.escape_state = EscapeState::Hex(EscapeStateHex::{ hex, left: 4 })
          self.last_char_is_backslash = false
          return self
        }
        _ => self.ctx.buffer.write_char(c)
      }
      self.escape_state = EscapeState::None
      self.last_char_is_backslash = false
      return self
    }
    EscapeState::None => ()
  }
  if c == '\\' {
    self.escape_state = EscapeState::Escape
    self.last_char_is_backslash = !self.last_char_is_backslash // handle consecutive backslashes
    return self
  }
  match c {
    '\n' => {
      guard self.phase is ReadingValue(ReadingValueState::None) else {
        raise IniParseError::QuoteNotClosed(
          line=self.ctx.line,
          col=self.ctx.col,
        )
      }
      if self.last_char_is_backslash {
        // Remove the effect of the backslash, do not commit value, just continue
        self.last_char_is_backslash = false
        return self
      }
      ignore(self.commit_value())
      self.last_char_is_backslash = false
      self.reset_line()
    }
    ';' | '#' => {
      guard self.phase is ReadingValue(ReadingValueState::None) else {
        raise IniParseError::QuoteNotClosed(
          line=self.ctx.line,
          col=self.ctx.col,
        )
      }
      ignore(self.commit_value(drop_last_one_space=true))
      self.phase = InComment
      self.last_char_is_backslash = false
      self
    }
    '\'' => {
      if self.phase is ReadingValue(ReadingValueState::DoubleQuote) {
        raise IniParseError::QuoteMismatch(line=self.ctx.line, col=self.ctx.col)
      }
      self.phase = match self.phase {
        ReadingValue(ReadingValueState::None) =>
          ReadingValue(ReadingValueState::SingleQuote)
        ReadingValue(ReadingValueState::SingleQuote) =>
          ReadingValue(ReadingValueState::None)
        _ => self.phase
      }
      self.last_char_is_backslash = false
      self
    }
    '"' => {
      if self.phase is ReadingValue(ReadingValueState::SingleQuote) {
        raise IniParseError::QuoteMismatch(line=self.ctx.line, col=self.ctx.col)
      }
      self.phase = match self.phase {
        ReadingValue(ReadingValueState::None) =>
          ReadingValue(ReadingValueState::DoubleQuote)
        ReadingValue(ReadingValueState::DoubleQuote) =>
          ReadingValue(ReadingValueState::None)
        _ => self.phase
      }
      self.last_char_is_backslash = false
      self
    }
    _ if c.is_whitespace() => {
      match self.phase {
        ReadingValue(ReadingValueState::None) =>
          if !self.ctx.buffer.is_empty() {
            self.ctx.buffer.write_char(c)
          }
        ReadingValue(ReadingValueState::SingleQuote) =>
          self.ctx.buffer.write_char(c)
        ReadingValue(ReadingValueState::DoubleQuote) =>
          self.ctx.buffer.write_char(c)
        _ => ()
      }
      self.last_char_is_backslash = false
      self
    }
    _ => {
      self.ctx.buffer.write_char(c)
      self.last_char_is_backslash = false
      self
    }
  }
}

///|
fn IniParseState::handle_comment(
  self : IniParseState,
  c : Char,
) -> IniParseState {
  match c {
    '\n' => self.reset_line()
    _ => self
  }
}

///|
fn IniParseState::reset_line(self : IniParseState) -> IniParseState {
  self.phase = Start
  self.ctx.buffer.reset()
  self
}

///|
fn IniParseState::commit_value(
  self : IniParseState,
  // If true, drop the last space in the value
  // this is used to handle the case when a comment is at the end of the line
  drop_last_one_space? : Bool = false,
) -> IniParseState raise IniParseError {
  let mut value = self.ctx.buffer.to_string()
  if drop_last_one_space && value is [.. rest, ch] && ch.is_whitespace() {
    value = rest.to_string()
  }
  let section = self.ctx.sections.get(self.ctx.current_section).unwrap()
  let key = self.ctx.key
  guard !key.is_blank() else {
    raise IniParseError::ValueWithoutSection(
      line=self.ctx.line,
      col=self.ctx.col,
    )
  }
  section.set(key, value)
  self.ctx.buffer.reset()
  self
}

///|
test "IniParseState::new/default_settings" {
  let state = IniParseState::new()
  inspect(state.is_case_sensitive, content="false")
  inspect(state.ctx.line, content="1")
  inspect(state.ctx.col, content="1")
  inspect(state.ctx.key, content="")
  inspect(state.phase, content="Start")
  inspect(state.ctx.current_section, content="Global")
}

///|
test "IniParseState::new/case_sensitive" {
  let state = IniParseState::new(is_case_sensitive=true)
  inspect(state.is_case_sensitive, content="true")
  inspect(state.ctx.current_section, content="Global")
}

///|
test "IniParseState::new/buffer_empty" {
  let state = IniParseState::new()
  inspect(state.ctx.buffer.is_empty(), content="true")
}

///|
test "IniParseState::process_char/start_phase" {
  let state = IniParseState::new()
  // Test transition from Start to ReadingSection
  let state = state.process_char('[')
  inspect(state.phase, content="ReadingSection")
  // Test transition from Start to InComment
  let state = IniParseState::new().process_char(';')
  inspect(state.phase, content="InComment")
  // Test transition from Start to ReadingKey
  let state = IniParseState::new().process_char('a')
  inspect(state.phase, content="ReadingKey")
}

///|
test "panic IniParseState::process_char/invalid_equal_sign" {
  let state = IniParseState::new()
  ignore(state.process_char('='))
}

///|
test "panic IniParseState::process_char/unclosed_section" {
  let state = IniParseState::new()
  let state = state.process_char('[')
  ignore(state.process_char('\n'))
}

///|
test "panic IniParseState::process_char/unexpected_equal_sign" {
  let state = IniParseState::new()
  ignore(state.process_char('='))
}

///|
test "IniParseState::process_char/global_section_edge_cases" {
  let state = IniParseState::new()
  inspect(state.process_char('[').phase, content="ReadingSection")
  inspect(state.process_char('G').phase, content="ReadingSection")
  let tmp = state.process_char(']')
  inspect(tmp.phase, content="Start")
  inspect(tmp.ctx.current_section, content="NamedSection(\"g\")")
  inspect(state.process_char('[').phase, content="ReadingSection")
  try {
    let _ = tmp.process_char('#')
    assert_true(false) // This shouldn't happen according to the test expectation
  } catch {
    IniParseError::UnclosedSection(_) => () // Expected behavior
    _ => assert_true(false) // Unexpected error type
  }
}

///|
test "panic IniParseState::process_char/unclosed_section_newline" {
  let state = IniParseState::new()
  ignore(state.process_char('['))
  ignore(state.process_char('\n'))
}

///|
test "IniParseState::handle_start/reading_section" {
  let state = IniParseState::new()
  let updated_state = state.handle_start('[')
  inspect(updated_state.phase, content="ReadingSection")
  inspect(updated_state.ctx.buffer.is_empty(), content="true")
}

///|
test "panic IniParseState::handle_start/unexpected_equal_sign" {
  let state = IniParseState::new()
  ignore(state.handle_start('='))
}

///|
test "IniParseState::handle_start/in_comment" {
  let state = IniParseState::new()
  let updated_state = state.handle_start('#')
  inspect(updated_state.phase, content="InComment")
}

///|
test "IniParseState::handle_section_char/basic" {
  let state = IniParseState::new()
  // Test normal section name
  let state = state
    .handle_section_char('t')
    .handle_section_char('e')
    .handle_section_char('s')
    .handle_section_char('t')
    .handle_section_char(']')
  inspect(state.ctx.current_section, content="NamedSection(\"test\")")
  inspect(state.phase, content="Start")
}

///|
test "panic IniParseState::handle_section_char/empty_section" {
  let state = IniParseState::new()
  ignore(state.handle_section_char(']'))
}

///|
test "IniParseState::handle_section_char/unclosed_section" {
  fn new_state() -> IniParseState raise IniParseError {
    IniParseState::new().handle_section_char('t')
  }

  // Test both comment characters
  assert_true(
    try {
      let _ = new_state().handle_section_char('#')
      false
    } catch {
      IniParseError::UnclosedSection(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = new_state().handle_section_char(';')
      false
    } catch {
      IniParseError::UnclosedSection(_) => true
      _ => false
    },
  )

  // Test newline
  assert_true(
    try {
      let _ = new_state().handle_section_char('\n')
      false
    } catch {
      IniParseError::UnclosedSection(_) => true
      _ => false
    },
  )
}

///|
test "IniParseState::handle_section_char/duplicate_section" {
  let state = IniParseState::new()
  let state = state.parse(
    (
      #|[test]
      #|key=foo
      #|key2=value
      #|
      #|[test]
      #|key=bar
      #|
    ),
  )
  let section = state.ctx.sections.get(Section::NamedSection("test")).unwrap()
  inspect(section.get("key"), content="Some(Value(\"bar\"))")
  inspect(section.get("key2"), content="Some(Value(\"value\"))")
}

///|
test "IniParseState::handle_key_char/basic" {
  let state = IniParseState::new()
  let state = state.handle_key_char('k')
  let state = state.handle_key_char('e')
  let state = state.handle_key_char('y')
  let state = state.handle_key_char('=')
  inspect(state.ctx.key, content="key")
  inspect(state.phase, content="ReadingValue(None)")
  inspect(state.ctx.buffer.is_empty(), content="true")
}

///|
test "panic IniParseState::handle_key_char/empty_buffer" {
  let state = IniParseState::new()
  ignore(state.handle_key_char('='))
}

///|
test "IniParseState::handle_key_char/whitespace" {
  let state = IniParseState::new()
  // Leading whitespace should be ignored
  let state = state.handle_key_char(' ')
  inspect(state.ctx.buffer.is_empty(), content="true")

  // Key characters should be recorded
  let state = state.handle_key_char('k')
  let state = state.handle_key_char('e')
  let state = state.handle_key_char('y')

  // Trailing whitespace should be recorded after first non-whitespace
  let state = state.handle_key_char(' ')
  inspect(state.ctx.buffer.to_string(), content="key ")
}

///|
test "IniParseState::handle_key_char/valueless_key" {
  let state = IniParseState::new()
  let state = state.handle_key_char('k')
  let state = state.handle_key_char('e')
  let state = state.handle_key_char('y')
  let state = state.handle_key_char('\n')
  inspect(state.ctx.key, content="key")
  inspect(state.phase, content="Start")
  let section = state.ctx.sections.get(state.ctx.current_section)
  inspect(section is Some(_), content="true")
  let value = section.unwrap().get("key")
  inspect(value, content="Some(Value(\"\"))")
}

///|
test "IniParseState::handle_key_char/comment_in_key" {
  let state = IniParseState::new()
  let state = state.handle_key_char('k')
  let state = state.handle_key_char('e')
  let state = state.handle_key_char('y')
  let state = state.handle_key_char(';')
  inspect(state.phase, content="Start")
  inspect(
    state.ctx.sections.get(Section::Global).unwrap().get("key").unwrap(),
    content="Value(\"\")",
  )
}

///|
test "panic IniParseState::handle_value_char/quote_not_closed_nl" {
  let state = IniParseState::new()
  let state = state.handle_value_char('\n')
  ignore(state)
}

///|
test "panic IniParseState::handle_value_char/quote_not_closed_comment" {
  let state = IniParseState::new()
  let state = state.handle_value_char(';')
  ignore(state)
}

///|
test "panic IniParseState::handle_value_char/quote_mismatch_single_double" {
  let state = IniParseState::new()
  let state = state.parse("[section]\nkey=")
  let state = state.handle_value_char('"')
  let state = state.handle_value_char('\'')
  ignore(state)
}

///|
test "panic IniParseState::handle_value_char/quote_mismatch_double_single" {
  let state = IniParseState::new()
  let state = state.parse("[section]\nkey=")
  let state = state.handle_value_char('\'')
  let state = state.handle_value_char('"')
  ignore(state)
}

///|
test "IniParseState::handle_comment/basic" {
  let state = IniParseState::new().parse("[section]\nkey=value#")
  // Test non-newline characters should keep the state unchanged
  let state = state.handle_comment('a')
  inspect(state.phase, content="InComment")
  let state = IniParseState::new().parse("[section]\nkey=value#")
  // Test newline should reset the line
  let state = state.handle_comment('\n')
  inspect(state.phase, content="Start")
  inspect(state.ctx.buffer.is_empty(), content="true")
}

///|
test "IniParseState::handle_comment/special_chars" {
  let state = IniParseState::new().parse("[section]\nkey=value#")
  // Test special characters should not affect the state
  inspect(state.handle_comment('#').phase, content="InComment")
  inspect(state.handle_comment(';').phase, content="InComment")
  inspect(state.handle_comment('=').phase, content="InComment")
  inspect(state.handle_comment('[').phase, content="InComment")
  inspect(state.handle_comment(']').phase, content="InComment")
}

///|
test "IniParseState::commit_value/basic" {
  let state = IniParseState::new()
  let state = state.parse("[section]\nkey=value")
  let state = state.commit_value()
  inspect(state.ctx.buffer.is_empty(), content="true")
  // Verify the section exists
  let section = state.ctx.sections.get(Section::NamedSection("section"))
  inspect(section is Some(_), content="true")
  // Verify the key exists in the section
  let value = section.unwrap().get("key")
  inspect(value is Some(_), content="true")
}

///|
test "panic IniParseState::commit_value/no_section" {
  let state = IniParseState::new()
  state.ctx.buffer.write_string("value")
  ignore(state.commit_value())
}

///|
test "IniParseState::commit_value/empty_value" {
  let state = IniParseState::new()
  let state = state.parse("[section]\nkey=")
  let state = state.commit_value()
  // Verify the section exists
  let section = state.ctx.sections.get(Section::NamedSection("section"))
  inspect(section is Some(_), content="true")
  // Verify the key exists in the section with empty value
  let value = section.unwrap().get("key")
  inspect(value is Some(_), content="true")
}
