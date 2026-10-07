# inet

[![Release](https://github.com/gatework/inet/actions/workflows/release.yml/badge.svg)](https://github.com/gatework/inet/actions/workflows/release.yml)
[![Gem Version](https://badge.fury.io/rb/inet.svg)](https://rubygems.org/gems/inet)

`inet` 的 Ruby gem 基础骨架。当前仅提供 `Inet` 命名空间和版本信息，尚未实现网络功能。

要求 Ruby 3.4 或更高版本，无运行时依赖，采用 MIT 许可证。

## 安装与使用

```sh
gem install inet
```

也可以在 Gemfile 中添加：

```ruby
gem "inet", "~> 0.1"
```

```ruby
require "inet"

puts Inet::VERSION # => "0.1.0"
```

## 开发

```sh
bundle install
bundle exec rake ci
```

`rake ci` 依次运行 Minitest、RuboCop、gem 构建与隔离安装验证；产物写入 `pkg/`。
也可以单独运行 `rake test`、`rake lint`、`rake package`。

GitHub Actions 在 Linux 和 macOS 上测试 Ruby 3.4、4.0。PR 和开发分支运行 CI；
`main` 通过同一组检查后进入发布流程。

## 自动发布

首次连接 RubyGems 的步骤见 [发布配置](docs/releasing.md)。完成后：

1. 更新 `lib/inet/version.rb`，在 `CHANGELOG.md` 中添加对应版本的说明。
2. 运行 `bundle install` 同步锁文件，再运行 `bundle exec rake ci`。
3. 提交并执行 `git push origin main`。

Actions 会发布经过 CI 验证的 gem，创建 `vX.Y.Z` 标签和 GitHub Release，并附上 gem 与 SHA256 校验文件。
版本号未变化的后续提交只运行检查，不重复发布。也可以在 `main` 上手动运行 Release 工作流。
