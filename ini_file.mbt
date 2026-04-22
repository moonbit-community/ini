///|
priv enum Section {
  Global
  NamedSection(String)
} derive(Eq, Hash)

///|
impl Show for Section with output(self, logger) {
  match self {
    Section::Global => logger.write_string("Global")
    Section::NamedSection(name) => {
      logger.write_string("NamedSection(")
      name.output(logger)
      logger.write_string(")")
    }
  }
}

///|
priv struct Key(String) derive(Eq, Hash)

///|
priv struct Value(String)

///|
impl Show for Value with output(self, logger) {
  let Value(value) = self
  logger.write_string("Value(")
  value.output(logger)
  logger.write_string(")")
}

///|
struct IniFile {
  sections : @hashmap.HashMap[Section, @hashmap.HashMap[Key, Value]]
  // default not case sensitive
  is_case_sensitive : Bool
}

///|
pub fn IniFile::new(is_case_sensitive? : Bool = false) -> IniFile {
  IniFile::{ sections: @hashmap.new(), is_case_sensitive }
}

///|
fn IniFile::new_with_sections(
  sections : @hashmap.HashMap[Section, @hashmap.HashMap[Key, Value]],
  is_case_sensitive? : Bool = false,
) -> IniFile {
  IniFile::{ sections, is_case_sensitive }
}

///|
fn IniFile::lower_if_needed(self : IniFile, s : String) -> String {
  if self.is_case_sensitive {
    s
  } else {
    s.to_lower()
  }
}

///|
/// get is a alias for get_string
pub fn IniFile::get(
  self : IniFile,
  section? : String = "",
  key : String,
) -> String? {
  self.get_string(section~, key)
}

///|
pub fn IniFile::get_string(
  self : IniFile,
  section? : String = "",
  key : String,
) -> String? {
  let section_map = self.get_section(
    match section {
      "" => Section::Global
      _ => Section::NamedSection(self.lower_if_needed(section))
    },
    create_if_not_exists=false,
  )
  guard section_map is Some(_) else { None }
  let section_map = section_map.unwrap()
  let value = section_map.get(self.lower_if_needed(key))
  guard value is Some(_) else { None }
  let value = value.unwrap()
  let Value(v) = value
  Some(v)
}

///|
pub fn IniFile::get_bool(
  self : IniFile,
  section? : String = "",
  key : String,
) -> Bool? {
  let value = self.get_string(section~, key)
  guard value is Some(_) else { None }
  let value = value.unwrap()
  match value.to_lower() {
    "true" | "yes" | "on" => Some(true)
    "false" | "no" | "off" => Some(false)
    _ => Some(false)
  }
}

// TODO: Add support for other types like Int, Float, etc.

///|
fn IniFile::get_section(
  self : IniFile,
  section : Section,
  create_if_not_exists? : Bool = false,
) -> @hashmap.HashMap[Key, Value]? {
  let section_map = self.sections.get(section)
  match section_map {
    None =>
      if create_if_not_exists {
        let new_section = @hashmap.new()
        self.sections.set(section, new_section)
        Some(new_section)
      } else {
        None
      }
    Some(_) => section_map
  }
}

///|
fn IniFile::get_section_or_create(
  self : IniFile,
  section : Section,
) -> @hashmap.HashMap[Key, Value] {
  let section_map = self.get_section(section, create_if_not_exists=true)
  section_map.unwrap()
}

///|
pub fn IniFile::set(
  self : IniFile,
  section? : String = "",
  key : String,
  value : String,
) -> Unit {
  let section_map = self.get_section_or_create(
    match section {
      "" => Section::Global
      _ => Section::NamedSection(self.lower_if_needed(section))
    },
  )
  section_map.set(self.lower_if_needed(key), Value(value))
}

///|
/// Converts the IniFile to a standard INI format string
pub fn IniFile::to_string(self : IniFile) -> String {
  fn escape_char(c : Char) -> String {
    match c {
      '\\' => "\\\\"
      '\'' => "\\\'"
      '"' => "\\\""
      '\u0000' => "\\0"
      '\u0007' => "\\a"
      '\b' => "\\b"
      '\t' => "\\t"
      '\r' => "\\r"
      '\n' => "\\n"
      ';' => "\\;"
      '#' => "\\#"
      '=' => "\\="
      ':' => "\\:"
      _ if c.is_control() || c.is_whitespace() || !c.is_printable() => {
        let unicode = c.to_int().to_string(radix=16)
        guard unicode.length() <= 4 else {
          abort("Unicode escape sequence too long")
        }
        return if unicode.length() < 4 {
          let padding = "0".repeat(4 - unicode.length())
          "\\x" + padding + unicode
        } else {
          "\\x" + unicode
        }
      }
      _ => c.to_string()
    }
  }

  fn escape_value(value : String) -> String {
    let str_list = value.iter().collect().map(escape_char)
    let builder = StringBuilder::new()
    str_list.each(fn(c) { builder.write_string(c) })
    builder.to_string()
  }

  let buf = StringBuilder::new()
  // Global section first
  let global_section = self.sections.get(Section::Global)
  if global_section is Some(_) {
    global_section
    .unwrap()
    .iter()
    .each(fn(kv) {
      let (key, value) = kv
      let Key(key) = key
      let Value(value) = value
      buf.write_string(key)
      buf.write_char('=')
      buf.write_string(escape_value(value))
      buf.write_char('\n')
    })
  }
  // Other sections
  self.sections
  .iter()
  .each(fn(section) {
    let (section, map) = section
    match section {
      Section::Global => return
      Section::NamedSection(name) => {
        buf.write_char('[')
        buf.write_string(name)
        buf.write_char(']')
        buf.write_char('\n')
        map
        .iter()
        .each(fn(kv) {
          let (key, value) = kv
          let Key(key) = key
          let Value(value) = value
          buf.write_string(key)
          buf.write_char('=')
          buf.write_string(escape_value(value))
          buf.write_char('\n')
        })
      }
    }
  })
  buf.to_string()
}

///|
test "INIFile::new/default_case_sensitivity" {
  let ini = IniFile::new()
  inspect(ini.is_case_sensitive, content="false")
}

///|
test "INIFile::new/case_sensitive_true" {
  let ini = IniFile::new(is_case_sensitive=true)
  inspect(ini.is_case_sensitive, content="true")
}

///|
test "INIFile::new/case_sensitive_false" {
  let ini = IniFile::new(is_case_sensitive=false)
  inspect(ini.is_case_sensitive, content="false")
}

///|
test "INIFile::get/basic_functionality" {
  let ini = {
    let temp = IniFile::new()
    temp.set(section="section1", "key1", "value1")
    temp.set("key2", "value2")
    temp
  }
  inspect(ini.get(section="section1", "key1"), content="Some(\"value1\")")
  inspect(ini.get("key2"), content="Some(\"value2\")")
  inspect(ini.get(section="nonexistent", "key1"), content="None")
  inspect(ini.get("nonexistent"), content="None")
}

///|
test "INIFile::get/case_sensitivity" {
  let ini = {
    let temp = IniFile::new(is_case_sensitive=true)
    temp.set(section="Section", "Key", "value")
    temp
  }
  inspect(ini.get(section="Section", "Key"), content="Some(\"value\")")
  inspect(ini.get(section="section", "Key"), content="None")
  inspect(ini.get(section="Section", "key"), content="None")
}

///|
test "INIFile::get/empty_strings" {
  let ini = {
    let temp = IniFile::new()
    temp.set(section="", "key", "value")
    temp.set(section="section", "", "value")
    temp
  }
  inspect(ini.get(section="", "key"), content="Some(\"value\")")
  inspect(ini.get(section="section", ""), content="Some(\"value\")")
}

///|
test "INIFile::get_bool/true_values" {
  let ini = {
    let obj = IniFile::new()
    obj.set("key1", "true")
    obj.set("key2", "yes")
    obj.set("key3", "on")
    obj.set(section="test", "key4", "TRUE")
    obj.set(section="test", "key5", "Yes")
    obj.set(section="test", "key6", "ON")
    obj
  }
  inspect(ini.get_bool("key1"), content="Some(true)")
  inspect(ini.get_bool("key2"), content="Some(true)")
  inspect(ini.get_bool("key3"), content="Some(true)")
  inspect(ini.get_bool(section="test", "key4"), content="Some(true)")
  inspect(ini.get_bool(section="test", "key5"), content="Some(true)")
  inspect(ini.get_bool(section="test", "key6"), content="Some(true)")
}

///|
test "INIFile::get_bool/false_values" {
  let ini = {
    let ini = IniFile::new()
    ini.set("key1", "false")
    ini.set("key2", "no")
    ini.set("key3", "off")
    ini.set("key4", "invalid")
    ini
  }
  inspect(ini.get_bool("key1"), content="Some(false)")
  inspect(ini.get_bool("key2"), content="Some(false)")
  inspect(ini.get_bool("key3"), content="Some(false)")
  inspect(ini.get_bool("key4"), content="Some(false)")
}

///|
test "INIFile::get_bool/nonexistent_values" {
  let ini = IniFile::new()
  inspect(ini.get_bool(section="nonexistent", "key"), content="None")
  inspect(ini.get_bool("nonexistent"), content="None")
}

///|
test "INIFile::set/basic_functionality" {
  let ini = {
    let ini = IniFile::new()
    ini.set("key", "value")
    ini
  }
  inspect(ini.get("key"), content="Some(\"value\")")
  ini.set(section="section", "key", "value")
  inspect(ini.get(section="section", "key"), content="Some(\"value\")")
}

///|
test "INIFile::set/case_sensitivity" {
  let ini = {
    let ini = IniFile::new(is_case_sensitive=true)
    ini.set(section="Section", "Key", "value1")
    ini.set(section="section", "key", "value2")
    ini
  }
  inspect(ini.get(section="Section", "Key"), content="Some(\"value1\")")
  inspect(ini.get(section="section", "key"), content="Some(\"value2\")")
}

///|
test "INIFile::set/overwrite" {
  let ini = {
    let temp = IniFile::new()
    temp.set("key", "value1")
    temp.set("key", "value2")
    temp
  }
  inspect(ini.get("key"), content="Some(\"value2\")")
  ini
  ..set(section="section", "key", "value1")
  .set(section="section", "key", "value2")
  inspect(ini.get(section="section", "key"), content="Some(\"value2\")")
}

///|
/// Test IniFile::to_string covers escaping special characters in key and value.
/// This test ensures that keys and values containing special INI characters
/// (such as '=', ';', '#', '\n', quotes, and leading/trailing spaces) are correctly output.
test "INIFile::to_string/escape_special_characters" {
  let kvs = [
    ("key1", "\\value1"),
    ("key2", "value2\'"),
    ("key3", "value3\""),
    ("key4", "value4\n"),
    ("key5", "value5\r"),
    ("key6", "value6\t"),
    ("key7", "value7;"),
    ("key8", "value8#"),
    ("key9", "value9:"),
    ("key10", "value10="),
    ("key11", "value11 \t"),
    ("key12", " value12"),
    ("key13", "\u0000"),
    ("key14", "\u0007"),
  ]
  let sections = [
    // "" => Section::Global
    "", "sec1=", "k", "v",
  ]
  let ini1 = IniFile::new()
  kvs
  .iter()
  .each((kv) => {
    let (key, value) = kv
    sections.iter().each(fn(section) { ini1.set(section~, key, value) })
  })
  let output = ini1.to_string()
  let ini2 = parse(output)
  kvs
  .iter()
  .each((kv) => {
    let (key, _) = kv
    sections
    .iter()
    .each((section) => {
      let ini1_value = ini1.get(section~, key)
      let ini2_value = ini2.get(section~, key)
      inspect(ini1_value == ini2_value, content="true")
    })
  })
}
