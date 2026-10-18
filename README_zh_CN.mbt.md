# 📝 ini: MoonBit INI 解析器

[English](https://github.com/moonbit-community/ini/blob/main/README.md) | [简体中文](https://github.com/moonbit-community/ini/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/moonbit-community/ini/check.yaml)](https://github.com/moonbit-community/ini/actions)
[![License](https://img.shields.io/github/license/moonbit-community/ini)](LICENSE)
[![codecov](https://codecov.io/gh/moonbit-community/ini/branch/main/graph/badge.svg)](https://codecov.io/gh/moonbit-community/ini)

**ini** 是一个用于 MoonBit 应用程序的高性能 INI 解析器。它提供了一种简单而高效的方式来解析和访问 INI 配置文件，具有清晰直观的 API。

🚀 **主要特性**

- 🔍 **INI 解析** – 解析 INI 文件，具有全面的错误处理
- 🛡️ **类型安全** – 对配置值进行强类型访问
- 🔄 **大小写敏感选项** – 可配置的节和键名大小写敏感性
- 🎯 **简单 API** – 直观的方法名称，易于使用
- 📦 **零依赖** – 纯 MoonBit 实现，无外部依赖

---

## 📥 安装

```
moon add moonbit-community/ini
```

## **🚀 `ini` 使用指南**

ini 提供了在 MoonBit 应用程序中解析和访问 INI 配置文件的简单方法。

---

### **📝 什么是 INI 文件？**

*INI 文件*是一种由节和键值对组成的配置文件格式：

_config.ini_

```ini
[server]
host=localhost
port=3000

[database]
url=mysql://user:pass@localhost/dbname
max_connections=100
```

---

### **🔍 基本用法**

使用 `ini` 最简单的方法是使用 `parse` 函数：

```mbt check
///|
test {
  let config_str =
    #|[server]
    #|host=localhost
    #|port=3000
  let ini = @ini.parse(config_str)
  let host = ini.get(section="server", "host").unwrap()
  inspect(host, content="localhost")
}
```

### **⚙️ 配置选项**

ini 在解析时提供配置选项：

```mbt check
///|
test {
  let content =
    #|[server]
    #|host=localhost
    #|port=3000
    #|[Server]
    #|host=remote

  // 大小写敏感解析
  let ini = @ini.parse(content, is_case_sensitive=true)
  inspect(ini.get(section="server", "host").unwrap(), content="localhost")
  inspect(ini.get(section="Server", "host").unwrap(), content="remote")

  // 创建空的 INI 文件对象
  let ini = @ini.IniFile::new(is_case_sensitive=true)
  ignore(ini)
}
```

---

### **🔄 值访问**

解析后，您可以使用各种方法访问值：

```mbt check
///|
test {
  let content =
    #|[server]
    #|host=localhost
    #|port=3000
    #|[feature]
    #|foo=true
  let ini = @ini.parse(content)
  let host = ini.get(section="server", "host")
  debug_inspect(
    host,
    content=(
      #|Some("localhost")
    ),
  )
  let foo_enabled = ini.get_bool(section="feature", "foo")
  debug_inspect(foo_enabled, content="Some(true)")
}
```

---

### **🛠️ 完整示例**

```mbt check
///|
test {
  let content =
    #|[server]
    #|host=localhost
    #|port=3000
    #|enabled=true
    #|
    #|[database]
    #|url=mysql://localhost/db

  // 解析 INI 内容
  let ini = @ini.parse(content)

  // 访问各种值
  let host = ini.get(section="server", "host").unwrap()
  let port = ini.get(section="server", "port").unwrap_or("8080")
  let enabled = ini.get_bool(section="server", "enabled").unwrap()
  inspect(
    if enabled {
      "\{host}:\{port}"
    } else {
      ""
    },
    content="localhost:3000",
  )
}
```

## 📜 许可证

本项目根据 Apache-2.0 许可证获得许可。 有关详细信息，请参见 [LICENSE](https://github.com/moonbit-community/ini/blob/main/LICENSE)。

## 📢 联系方式 & 支持

- GitHub Issues: [报告问题](https://github.com/moonbit-community/ini/issues)

👋 如果你喜欢这个项目，给它一个 ⭐! 祝你编码愉快! 🚀
