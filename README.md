# inet

[![Release](https://github.com/gatework/inet/actions/workflows/release.yml/badge.svg)](https://github.com/gatework/inet/actions/workflows/release.yml)
[![Gem Version](https://badge.fury.io/rb/inet.svg)](https://rubygems.org/gems/inet)

`inet` 提供 IPv4、IPv6 地址与服务范围运算，以及不可变整数区间集合。加载时不发起网络请求或启动后台任务。

要求 Ruby 3.4 或更高版本，无运行时依赖，采用 MIT 许可证。

## 安装与使用

```sh
gem install inet
```

也可以在 Gemfile 中添加：

```ruby
gem "inet", "~> 0.2"
```

```ruby
require "inet"

Inet::IPAddr.host_cidr("192.0.2.9/24")    # => "192.0.2.9/24"
Inet::IPAddr.network_cidr("192.0.2.9/24") # => "192.0.2.0/24"
Inet::IPAddr.cidrs(Inet::IPAddr.parse("192.0.2.0/24")) # => [["192.0.2.0", 24]]
Inet::IPv6.canonical("2001:0db8::9/64")   # => "2001:db8::/64"
Inet::IPv6.canonical("2001:db8::9/64", host: true) # => "2001:db8::9/64"

allowed = Inet::Set.new(1..10) - Inet::Set.new(3..7)
allowed.ranges      # => [1..2, 8..10]
allowed.cardinality # => 5
```

## 接口约定

- `Inet::IPAddr` 继承标准库 `IPAddr`，只接受 IPv4 字符串或整数；设备格式中的前导零按十进制处理，`any` 表示 `0.0.0.0`，全部 IPv4 地址使用 `any/0`。
- `host_cidr` 保留主机位，`network_cidr` 归一化网络地址；可传第二个参数指定前缀长度或连续网络掩码。`host` 返回主机文本，`to_i` / `from_i` 转换整数，`prefix_length` / `netmask` / `wildcard_mask` 转换掩码。
- `parse` 接受主机、CIDR、点分掩码或 `起点-终点`，返回 `Inet::Set`。IPv4 的范围端点自动排序；`between` 接受两个端点，`subnet` / `network` 接受地址及掩码。`cidrs` 接受合法 IPv4 整数集合并返回 `[地址, 前缀]` 数组；`format_range` 接受合法闭区间并返回单个 CIDR 或端点表达式。
- `ports` 接受端口整数、区间、单个端口文本或以连字符/空格分隔的范围，限制为 `0..65535`。`protocol_number` 接受名称、符号或 `0..255` 的编号；`icmp?` 判断 ICMP/ICMPv6。`service("tcp/80-90")` 返回服务整数集合，高八位为协议号，低十六位为端口；省略端口使用零，`any` 或协议 `0` 表示整个 24 位服务空间。
- `Inet::IPv6.address` 返回标准库 `IPAddr`；`canonical` 规范化主机或 CIDR，`parse` 返回整数集合，`normalize` 输出规范文本。范围必须按从小到大排列且不带前缀；拒绝带区域标识 `%` 的地址。`from_i` 转换 128 位非负整数，`ranges` 把合法 IPv6 整数集合转换为地址文本端点对。
- `Inet::Set.new(*ranges)` 接受非负整数区间，自动合并重叠及相邻区间；半开区间转换为闭区间，拒绝空或逆序区间。`each` 遍历区间，`size` 是区间段数，`cardinality` 是整数元素总数。空集合的 `min` / `max` 返回 `nil`。
- 集合支持 `|`、`&`、`-`、`include?(整数)`、`cover?(整数或集合)`、`subset?`、`overlap?`、`relation`。关系返回 `:equal`、`:contains`、`:within` 或 `:other`。集合和值数组冻结，`to_a` 返回数组副本；相等性、哈希和 Marshal 恢复保持值语义。

非法地址、超范围值和不支持的类型抛出 `ArgumentError`（包括标准库 `IPAddr` 的对应子类）。集合自身不区分 IPv4、IPv6、端口或服务，调用方须保持同一数值空间，避免跨类型混算。
可分别 `require "inet/ipaddr"`、`require "inet/ipv6"` 或 `require "inet/set"`。

这三个模块迁自 Gatework 的 algosec-rb，保留其公共方法与运算行为；最低 Ruby 版本自带的 `Range#overlap?` 替代原 ActiveSupport 加载。源代码采用 MIT 许可证，版权声明见 [LICENSE](LICENSE)。

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
