# Repository Guidelines

## 项目边界

`inet` 是 Ruby gem，最低支持 Ruby 3.4。公共命名空间为 `Inet`，入口为 `lib/inet.rb`。
首版只提供骨架和版本信息；新增功能应先明确输入、输出及异常契约。
加载 gem 不启动网络请求或后台任务。说明性注释和项目文档使用中文。

## 开发与验证

- 修改前检查 Git 状态，保留已有工作，只提交本次任务涉及的文件。
- 使用 Gemfile.lock 中的开发依赖，统一检查入口为 `bundle exec rake ci`。
- `test/` 使用 Minitest，`script/verify_package.rb` 检查真实 gem 的元数据、内容和隔离安装。
- 新增运行时依赖时在 gemspec 声明，同时调整隔离安装验证；开发依赖放在 Gemfile。
- gem 文件清单由 gemspec 显式限定，凭据、测试数据、构建产物不得进入发布包。

## 发布

版本来源为 `lib/inet/version.rb`，需同步 Gemfile.lock 和 CHANGELOG.md。
推送 `main` 可触发新版本发布；修改发布文件前先读 `docs/releasing.md`。
仅发布通过全部 CI 作业的原始构件，不能在发布作业中重建替换。
上传结果不明时先回读，不能自动重试上传。完成发布需确认 RubyGems、GitHub Release
与 CI 构件 SHA256 一致，并确认标签指向对应提交。
