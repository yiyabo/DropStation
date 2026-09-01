# DropStation · 文件中转站

<p align="center"><img src=".github/assets/banner.png" alt="DropStation banner" width="720"></p>

一个 macOS 菜单栏小工具：在任何应用里拖拽文件时快速晃动鼠标，把文件暂存到悬浮的"中转站"面板里，之后随时再拖出去。

## 功能

- **晃动暂存**：拖拽文件时快速左右（或上下）晃动鼠标（约 1.2 秒内反向 3 次），中转站面板就会出现在鼠标旁边，直接把手里拖着的文件投进去。
- **拖入暂存**：也可以把文件直接拖到面板上。
- **拖出发送**：按住面板里的文件行即可重新发起拖拽，把文件投到任何地方；文件可重复拖出，投到多处。

## 安装

到 [Releases](https://github.com/yiyabo/DropStation/releases) 页面下载最新的 `DropStation-x.x.x.dmg`，打开后把 DropStation 拖入 Applications 文件夹即可。

首次使用：

1. 应用无 Developer ID 签名，若被 Gatekeeper 拦截：到「系统设置 → 隐私与安全性」点击「仍要打开」。
2. 在「系统设置 → 隐私与安全性 → 辅助功能」中为 DropStation 授权（未授权时菜单栏会出现引导项）。

从源码构建：`git clone` 后运行 `./create-dmg.sh` 生成 DMG（需要 `pip install Pillow`）；或 `./build-app.sh` 只构建应用本体。

## License

MIT
