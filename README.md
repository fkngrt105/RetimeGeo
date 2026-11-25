# 🧭 RetimeGeo v3.1 (Turbo Interactive)
![Shell](https://img.shields.io/badge/Shell-zsh-89e051?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white)
![Version](https://img.shields.io/badge/Version-v3.1-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

> **拨正时光指针，锚定全球坐标，交互按需归档。**  
> 一款运行于 macOS 终端的轻量级相册元数据修复与交互式多维度归档引擎。先全自动静默完成防卡死质检、批量格式纠偏、真实时间线还原与内部 EXIF 刻录，随后通过终端数字交互菜单按拍摄设备型号、国家地级市或拍摄年月按需分拣，支持单次会话连续接力处理多个相册。

---

## 💡 项目背景

云端相册按月批量导出时，照片/视频的磁盘时间会全部变成“下载当天”，而微信、小红书、截屏等社交存图又被剥离了内部 EXIF，直接传回手机会导致时间线彻底错乱。**RetimeGeo** 专为在 macOS 本地一站式修复时间戳、纠偏伪装格式并按需归档而打造。

## 📈 演进里程碑

- **v1.0 – v1.5（原型破局）**：实现 ExifTool 全格式时间还原、13 位毫秒戳破译、`-P` 防回弹锁定与早期东亚地理围栏分拣。
- **v2.0 `Atlas`（首个双核完整版）**：正式定名 **RetimeGeo**，引入 `reverse_geocoder` 离线空间引擎，支持全球多级行政区划自动建夹。
- **v2.4 `Atlas`（智能兜底重点版）**：新增提取外层文件夹年月自动兜底定日（当月 15 日 `12:00:00`），彻底消灭纯哈希网图手工残留。
- **v2.6 – v2.8 `SafeGuard`（体验与稳定性打磨）**：加入已知日期秒跳过、`-q -q` 静默输出、地级市聚合及 `[0/5]` 防卡死质检护盾。
- **v3.0 – v3.1 `Turbo Interactive`（交互控制台跃迁）**：解耦“全自动校时”与“终端数字交互分拣”，支持按设备型号、城市或拍摄年月拆夹，以及批量 JSON 纠偏与 SSD 5 秒冷却缓冲。

---

## ✨ 核心工作流

### 阶段一：全自动无感元数据修复流水线（6 步闭环）

| 步骤 | 模块名称 | 核心处理逻辑 |
| :--- | :--- | :--- |
| **`[0/5]`** | **SafeGuard 防卡死质检拦截** | 自动清理遗留的 `*_exiftool_tmp` 锁文件，扫描剔除 0 字节空壳文件、无有效时长的损坏 MP4/MOV 视频及异常编码图片，提前隔离至 `异常隔离-防卡死/`。 |
| **`[1/5]`** | **实拍照片时间同步** | 读取相机与手机照片内部的 `DateTimeOriginal`，直接还原当地拍摄墙上时间（跳过日期已正常的照片，启用 `-api QuickTimeUTC=1` 缓冲优化）。 |
| **`[2/5]`** | **实拍录像时间同步** | 读取 MP4 / MOV 视频内部的 `CreateDate`，还原录像真实创建时间。 |
| **`[3/5]`** | **伪装后缀深度纠偏** | 批量 JSON 探测文件底层真实编码（`FileType`），联动 `dwebp` 与原生 `sips` 将内部实为 WebP 或 PNG 但后缀为 `.jpg`/`.png` 的文件无损重编码为标准 JPEG。 |
| **`[4/5]`** | **时间戳与目录年月兜底** | 提取 13 位毫秒级 Unix 时间戳（微信 `mmexport*`、小红书 `Camera_XHS_*`、运动软件 `strava*`）及 `Screenshot_YYYYMMDD-HHMMSS` 截屏日期；无时间线索网图自动套用外层文件夹年月（当月 15 日 `12:00:00`）。 |
| **`[5/5]`** | **防回弹 EXIF 刻录** | 将修好的磁盘时间反向刻录进缺失 `DateTimeOriginal` 的图片内部 `AllDates`，同时启用 `-P` 参数锁定 macOS Finder 修改时间不刷新为“今天”。 |

### 阶段二：终端数字交互控制台（`[0-4]` 按需分拣）

- **`[1]` 按拍摄设备型号分类**：自动读取内部 EXIF `Model` 标签，将混杂的不同设备原片拆进各自机身子文件夹（如不同型号手机与相机机身），无设备标签的截屏与社交网图统一归入 `社交与网图/`。
- **`[2]` 按国家城市（GPS 地级市）+ 四层漏斗分类**：调用离线 `reverse_geocoder` 单进程安全空间索引引擎（`mode=1`），自动生成 `GPS-国家-省州-地级市/`（直辖市自动去除 `Shi` 后缀）、`相机相册/`、`手机相册/`、`微信相册/`、`截图相册/`、`第三方App与其他/`。
- **`[3]` 按拍摄年月拆分文件夹**：读取每个文件修复后的真实拍摄年月，自动按 `YYYY-MM/`（如 `2024-06/`、`2024-07/`）拆分归档，适合整理跨越多月的混合备份文件夹。
- **`[4]` 处理下一个相册**：无需退出脚本或重新敲命令，直接在当前终端提示符下拖入新文件夹路径，立即开启新一轮流水线接力。
- **`[0]` 不分类（保持平铺），直接完成并退出**：仅完成时间线校准与内部 EXIF 写入，保持原文件夹扁平结构干净退出。

---

## 🛠️ 环境依赖与部署指南

### 1. 安装基础命令行依赖（macOS Homebrew）
```bash
brew install exiftool webp
```



### 2. 安装 Python 离线地理编码引擎
```bash
pip3 install --user reverse_geocoder
```



### 3. 注册系统级全局指令
```bash
chmod +x ~/fix_photos.sh
sudo ln -sf "$HOME/fix_photos.sh" /usr/local/bin/retimegeo
sudo ln -sf "$HOME/fix_photos.sh" /usr/local/bin/rt
```



---

## 🚀 快速使用

```bash
retimegeo "~/Downloads/目标相册文件夹"
```
---

*Co-crafted with Gemini ✨*
