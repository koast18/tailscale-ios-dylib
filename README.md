# Tailscale iOS Dylib (proxy-only embedded Tailscale)

这个仓库研究并复刻了 Tailscale 官方把核心作为嵌入式库使用的做法，并在此基础上
为 iOS 生成一个 **动态库 (`dylib`)**，用于非 App Store / 企业 / 模拟器 / 实验性场景。

> App Store 应用请继续使用官方 `libtailscale` 的静态库/Swift framework 方案；
> iOS 上动态库在 App Store 审核中通常不被允许。

## 这个仓库解决什么问题

Tailscale 的 iOS 客户端本身**没有开源**，但 Tailscale 官方开源了核心和桥接组件：

- [`tailscale/tailscale`](https://github.com/tailscale/tailscale)：核心 Go 实现，其中
  `tsnet` 包可以在进程内以 userspace 方式嵌入一个 Tailscale 节点。
- [`tailscale/libtailscale`](https://github.com/tailscale/libtailscale)：官方 C 桥接库，
  用 Go `c-archive` 把 `tsnet` 暴露成 C API，并带有 iOS/Swift framework 构建脚本。
- [`tailscale/tailscale-android`](https://github.com/tailscale/tailscale-android)：移动端
  的 Android 实现，可以印证官方移动端也是用 Go 核心 + 平台桥接层。

### 官方 iOS 的构建方式

官方 `libtailscale` 的 `Makefile` 显示：

- iOS 真机：`GOOS=ios GOARCH=arm64 ... go build -buildmode=c-archive`
- iOS 模拟器：`GOOS=ios GOARCH=arm64` / `GOOS=ios GOARCH=amd64` 的 c-archive
- 再用 Xcode 把静态库包成 `TailscaleKit.framework`

Go **不支持** `-buildmode=c-shared` 在 `ios/arm64` 上直接生成 dylib。
所以本仓库的做法是：

1. 先用官方方式构建 iOS 的 Go c-archive；
2. 在 macOS + Xcode 上用 `xcrun clang -dynamiclib -Wl,-all_load` 把该静态库链接成
   `libtailscale.dylib`；
3. 同时产出模拟器 fat dylib 和 macOS dylib，方便本地验证。

## 已实现的核心目标

| 目标 | 做法 |
| --- | --- |
| 1. 不需要路由/ACL/防火墙修改，只提供代理接入接口 | 直接使用 `tsnet`（userspace，不创建系统 TUN/路由/防火墙规则）；仅暴露 dial/listen 和 LocalAPI 读写接口 |
| 2. 像 Tailscale 客户端一样修改/读取运行参数 | 暴露 `tailscale_get_status_json`、`tailscale_get_prefs_json`、`tailscale_edit_prefs_json` 以及简单的 `tailscale_get_param` / `tailscale_set_param` |
| 3. 关闭 P2P 直连和 UDP 打洞，完全依赖 DERP | 设置 `TS_DEBUG_ALWAYS_USE_DERP=1` 和 `TS_DEBUG_NEVER_DIRECT_UDP=1`（通过 `tailscale_set_disable_p2p` 或 `tailscale_set_param("disable_p2p", "true")`） |
| 4. 所有外连（包括 DERP）走指定 HTTP 代理 | 设置 `HTTPS_PROXY` / `HTTP_PROXY` 并刷新 Tailscale 的代理缓存；DERP 的 `derphttp` 和 control client 都会走 HTTP CONNECT 代理 |

## 仓库结构

```text
.
├── tailscale.go              # Go 桥接层（基于 libtailscale 扩展，薄封装，不改 core）
├── tailscale.c               # C 友好名称包装层（tailscale_new / tailscale_set_proxy 等）
├── tailscale.h               # C 头文件（也由 go build 生成）
├── Makefile                  # 官方构建目标 + ios-dylib 目标
├── scripts/
│   ├── clangwrap-ios*.sh     # iOS SDK 的 cgo 编译器 wrapper
│   └── build-ios-dylib.sh    # 构建 iOS/macOS dylib 的脚本
└── .github/workflows/release.yml
```

## 构建

在 macOS（已安装 Xcode 和 Go）上：

```bash
# 构建 iOS 真机/模拟器 dylib + macOS dylib + 静态库
make ios-dylib

# 或只构建静态库
make c-archive-ios
make c-archive-ios-sim

# 或只构建 macOS 动态库
make shared
```

产物在 `dist/` 下：

```text
dist/ios/libtailscale.dylib          # iOS 真机 arm64 dylib
dist/ios/libtailscale_ios.a          # iOS 真机静态库
dist/ios/libtailscale.h
dist/ios-sim/libtailscale.dylib      # iOS 模拟器 fat dylib (arm64+x86_64)
dist/ios-sim/libtailscale_ios_sim.a  # iOS 模拟器静态库
dist/macos/libtailscale.dylib        # macOS dylib（方便本地测试）
```

GitHub Actions 在打 tag（例如 `v0.1.0`）或手动 `workflow_dispatch` 时自动构建，
并把产物发布到 GitHub Release。

## C 用法示例

```c
#include "tailscale.h"

tailscale sd = tailscale_new();

/* 1) 基础节点参数 */
tailscale_set_dir(sd, "/path/to/state");
tailscale_set_hostname(sd, "ios-proxy-node");
tailscale_set_authkey(sd, "tskey-auth-...");
tailscale_set_control_url(sd, "https://control.tailscale.com");

/* 2) 代理接入模式：不需要路由/ACL/防火墙 */
/* tsnet 默认就是 userspace，不添加系统路由/防火墙 */

/* 3) 完全依赖 DERP，关闭 P2P/UDP 打洞 */
tailscale_set_disable_p2p(sd, 1);

/* 4) 所有外连（control + DERP）走指定 HTTP 代理 */
tailscale_set_proxy(sd, "http://127.0.0.1:8888");

/* 启动并等待节点可用 */
tailscale_up(sd);

/* 读取状态 / 参数 */
char buf[65536];
tailscale_get_status_json(sd, buf, sizeof(buf));   /* JSON status */
tailscale_get_prefs_json(sd, buf, sizeof(buf));    /* JSON prefs  */

/* 像 tailscale set 一样修改运行参数 */
tailscale_edit_prefs_json(sd, "{\"Hostname\":\"new-name\"}");

tailscale_close(sd);
```

## 在 iOS 工程中嵌入 dylib

1. 从 Release 下载 `dist/ios/libtailscale.dylib` 和 `dist/ios/libtailscale.h`。
2. 把 dylib 拖入 Xcode 的 **Frameworks, Libraries, and Embedded Content**。
3. 如果链接器报缺少系统框架，请手动添加：
   - `CoreFoundation.framework`
   - `Security.framework`
   - `SystemConfiguration.framework`
4. 在 Bridging-Header / Objective-C / C 文件中 `#include "tailscale.h"`。
5. 签名时使用你的企业/开发证书（动态库需要签名）。

## 如何跟随官方核心更新

本仓库没有 fork/patch Tailscale 核心，只保留了一层薄桥接。更新核心只需：

```bash
go get tailscale.com@latest
go mod tidy
git commit -m "chore: bump tailscale core"
```

之后重新 `make ios-dylib` 即可。正常情况下不需要修改 `tailscale.go`。

## 注意事项

- 这些 `TS_DEBUG_*` 环境变量是 Tailscale 内部调试开关，不是公开稳定 API；
  本仓库把它们封装成稳定的 C API，但如果上游改名/移除，需要同步更新桥接层。
- `tailscale_edit_prefs_json` 会拒绝路由/退出节点/防火墙相关字段，避免误改系统网络行为。
- 动态库方式不适合上架 App Store；上架请使用官方静态 framework 方式。

## License

本仓库基于 Tailscale 的 BSD-3-Clause 许可，保留上游版权声明。
