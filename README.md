# <img width="32" height="32" alt="ClassPath_256" src="https://github.com/user-attachments/assets/d9f56747-8dbe-47c2-8bfa-d63100a6e746" /> 课途 ClassPath ![Release](https://img.shields.io/github/v/release/DaHedan/ClassPath?include_prereleases) ![License](https://img.shields.io/github/license/DaHedan/ClassPath) ![平台](https://img.shields.io/badge/平台-Android%20%7C%20Windows-blue) ![Downloads](https://img.shields.io/github/downloads/DaHedan/ClassPath/total) ![Last Commit](https://img.shields.io/github/last-commit/DaHedan/ClassPath)

_多端课程表软件_ — 管理课程、安排考试、到点提醒，一份课表在手机与电脑间随时同步。数据完全保存在本地，无需账号登录。

__想要了解关于课途的详细信息（构建方法、技术说明等），请前往 [ClassPath v1.0 Wiki](https://github.com/DaHedan/ClassPath/wiki/ClassPath-v1.0-Wiki) 。__

## 📜 许可协议

本项目采用 [GPL-3.0](LICENSE) 开源协议。

## 📦 获取工具  ![支持](https://img.shields.io/badge/支持-Android_ARM32%2F64%20|%20Windows_x64-blue)

如果你的需求是下载这个软件去使用，而不是需要源代码，请到 [Releases ClassPath v1.0](https://github.com/DaHedan/ClassPath/releases/tag/v1.0.0) 下载对应的安装包，无需下载源代码。

- **Android**：下载适用于 ARM 64位的 APK 安装
- **Windows**：下载适用于 Windows 64位 安装包或便携版压缩包，解压 / 安装即用

## 🖥️ 功能介绍

### 课程表

1. **多份课表**：可为不同学期创建多份课表，随时切换使用。
2. **双视图**：单周模式逐周查看（可跳转任意周次），本学期模式一览整学期安排。
3. **自定义节次时间**：按楼宇配置每节的上课时间，午餐 / 晚餐时段按节次标注。
4. **节假日与调休**：自动接入国务院节假日安排，放假自动停课、调休补班日照常排课。

### 课程管理

1. 课程卡片自定义：**颜色、编号、名称、教师、周次、地点**（楼宇 + 房号）。
2. 上课时间用**双圈表盘**选择，精确到分钟；同一门课可分多个时间段，各自单独设置周次与地点。
3. **考试安排**：为课程登记考试日期、时间、地点与座位号，主页底部自动汇总、按时间排序。
4. 支持添加**备注**，记录老师联系方式、教材等额外信息。

### 上课提醒

1. 每门课可单独设置**提前提醒**时间，到点通过系统通知提醒。
2. Android 使用系统精确闹钟，Windows 使用系统 Toast 通知。

### 导入导出与分享

1. **二维码**：扫码 / 生成二维码快速导入导出课表，手机端可调起系统分享面板发送给同学。
2. **文件备份**：导出 JSON 文件本地备份，随时恢复，跨平台格式一致。

### 界面

1. 支持浅色、深色、跟随系统三种主题模式。

## ⚠️ 用户须知

1. 所有数据仅保存在本机（Android / Windows 为应用本地存储，Web 为浏览器 localStorage），**不收集、不上传任何个人信息**。
2. 上课提醒依赖系统通知服务：Android 需要允许通知权限；Windows 受系统限制，预约提醒最多提前 3 天，且到点需电脑保持开机。
3. 本软件为开源软件（GPL-3.0），可自由使用、修改与分发，请遵循开源协议。使用过程中如出现异常，作者不对由此产生的直接或间接损失负责。
4. 建议定期使用「导出」功能备份课表数据。
