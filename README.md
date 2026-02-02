# PhotoCleaner

一款专注于快速清理手机照片的 iOS App，通过简单的滑动手势帮助用户高效整理相册。

## 功能特性

### 核心功能

- **滑动浏览** - 左右滑动切换照片，流畅的过渡动画
- **上滑删除** - 上滑将照片加入待删除列表，照片向上飞出
- **下滑批量** - 下滑进入批量选择模式，支持拖动多选
- **暂存机制** - 照片先暂存，统一确认后才真正删除
- **撤销操作** - 误操作后 4 秒内可撤销

### Live Photo 支持

- 批量选择和单张浏览模式均显示 **LIVE** 标识
- 单张浏览时**长按**可播放 Live Photo 动态效果
- 松开手指自动停止播放

### 批量选择模式

- 4 列网格展示所有照片
- 点击选择/取消，支持全选
- **拖动多选** - 手指滑过的照片自动选中或取消
- 双击照片跳转到单张浏览

### 待删除列表

- 点击待删除计数进入列表查看
- **长按拖动移除** - 长按照片拖到底部感应区可移除
- 确认删除后照片进入系统「最近删除」

## 技术栈

- **SwiftUI** - 主要 UI 框架
- **Photos Framework** - 相册访问和管理
- **PhotosUI** - Live Photo 播放
- **MVVM** 架构模式

## 系统要求

- iOS 15.6+
- Xcode 15+

## 项目结构

```
PhotoCleaner/
├── PhotoCleanerApp.swift          # App 入口
├── ContentView.swift              # 主视图路由
├── ViewModels/
│   └── PhotoLibraryViewModel.swift # 核心业务逻辑
├── Views/
│   ├── PhotoBrowserView.swift     # 单张浏览模式
│   ├── BatchSelectView.swift      # 批量选择模式
│   ├── DeleteConfirmView.swift    # 待删除确认页
│   ├── LivePhotoPlayerView.swift  # Live Photo 播放
│   ├── PhotoAssetImageView.swift  # 高清图片显示
│   ├── PhotoAssetThumbnailView.swift # 缩略图显示
│   ├── PermissionView.swift       # 权限请求页
│   ├── ToastView.swift            # Toast 提示
│   └── EmptyStateView.swift       # 空状态页
└── Services/
    └── PendingDeleteStore.swift   # 待删除列表持久化
```

## 交互说明

### 单张浏览模式

| 手势 | 操作 |
|------|------|
| 左滑 | 下一张照片 |
| 右滑 | 上一张照片 |
| 上滑 | 加入待删除 |
| 下滑 | 进入批量选择 |
| 长按 | 播放 Live Photo |

### 批量选择模式

| 手势 | 操作 |
|------|------|
| 点击 | 选择/取消选择 |
| 双击 | 跳转到该照片 |
| 拖动 | 批量选择/取消 |

### 待删除列表

| 手势 | 操作 |
|------|------|
| 点击 | 全屏预览 |
| 长按拖动 | 拖到底部移除 |

## 安装运行

1. 克隆项目
```bash
git clone https://github.com/Galaxy-wbh/PhotoCleaner.git
```

2. 打开 Xcode 项目
```bash
cd PhotoCleaner
open PhotoCleaner.xcodeproj
```

3. 选择目标设备，运行项目

## 权限说明

App 需要相册读写权限才能正常工作：
- **读取权限** - 浏览和显示照片
- **写入权限** - 删除照片

## License

MIT License
