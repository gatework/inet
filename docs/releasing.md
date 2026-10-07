# 发布配置

## 首次设置

本项目通过 [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
使用 GitHub Actions 的短期 OIDC 凭据发布，不需要保存 RubyGems API key。

首次发布前，登录 RubyGems，打开 [Pending trusted publishers](https://rubygems.org/profile/oidc/pending_trusted_publishers)，
新建以下配置：

| 字段 | 值 |
| --- | --- |
| Gem name | `inet` |
| Repository owner | `gatework` |
| Repository name | `inet` |
| Workflow filename | `release.yml` |
| Environment | `release` |

工作流仓库的可选字段留空，因为发布作业就在当前仓库。
首次成功发布后，RubyGems 会自动把 pending publisher 转为该 gem 的 trusted publisher。
若 gem 已存在，应从 gem 页面进入 Trusted publishers 配置。

在 GitHub 仓库中创建名为 `release` 的 Environment，将 Deployment branches and tags
设置为 Selected branches and tags，仅允许名为 `main` 的分支，不添加标签规则。
自动发布使用这个环境；如需人工审批，可以自行添加 required reviewers。

## 日常发布

更新 `Inet::VERSION` 为新的 `X.Y.Z` 版本，并添加 `CHANGELOG.md` 同名标题。
运行 `bundle install` 更新 Gemfile.lock 中的本地 gem 版本，然后执行 `bundle exec rake ci`。
提交并推送 `main` 后，Release 工作流会：

1. 在 Linux/macOS、Ruby 3.4/4.0 上运行测试、静态检查、打包和隔离安装。
2. 下载本次 Linux/Ruby 4.0 作业的构件，校验 SHA256、包元数据和源码内容。
3. 确认版本和标签没有冲突，取得仅用于 `inet` 的短期发布凭据。
4. 上传该 gem，回读 RubyGems 版本信息和下载内容，确认 SHA256 一致。
5. 创建对应标签和 GitHub Release，上传同一份 gem 与 `SHA256SUMS`，下载比对后公开发布。

首次推送 `main` 会发布 `0.1.0`。同版本的后续提交会跳过发布；后续更改需要提升版本号。
发布只在 `main` 上运行，标签由工作流自动创建。

## 失败恢复

测试或包校验失败时修复后重新推送。OIDC 失败时核对上表，完成配置后重跑失败作业。

RubyGems 上传结果不明时，先查看版本页面和 SHA256，等待索引更新；不要立即重新上传或本地重建。
确认 RubyGems 已有相同 SHA256 后，使用 Actions 的 **Re-run failed jobs**，保留同一运行中的原始构件。
工作流会识别已发布的相同构件，继续完成 GitHub Release。
同版本存在不同 SHA256 时停止发布，需要检查冲突并使用新版本。

`script/release.rb` 是 Actions 内部入口，要求 `gatework/inet` 的 `main`、干净工作区和对应的触发提交。
本地可以运行 `bundle exec ruby script/verify_package.rb pkg/inet-0.1.0.gem` 验证已有构件。
