# 更新记录

## 0.2.0

1. **地址与服务运算**：从 algosec-rb 迁入 IPv4、IPv6 地址规范化、范围解析、CIDR 拆分、端口及协议服务编码，公共入口为 `Inet::IPAddr`、`Inet::IPv6`。
2. **区间集合**：提供不可变 `Inet::Set`，支持合并、交集、差集、包含、重叠、关系判断和 Marshal 持久化；无需 ActiveSupport 或其他运行时依赖。
3. **验证**：补充边界、非法输入、集合运算对照测试和真实 gem 隔离安装验证。

## 0.1.1

1. **自动发布**：接通 RubyGems Trusted Publishing，由 GitHub Actions 发布通过全部检查的同一份 gem，并提供对应的 GitHub Release 和 SHA256 校验文件。

## 0.1.0

1. **基础骨架**：提供可安装的 `inet` gem、`Inet` 命名空间和版本信息，要求 Ruby 3.4 及以上版本。
2. **自动发布**：更新版本号并推送 `main` 后，检查通过即可发布到 RubyGems 和 GitHub Releases。
