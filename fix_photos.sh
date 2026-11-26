#!/bin/zsh
# ==============================================================================
# Project: RetimeGeo v3.2 (Turbo Interactive)
# Description: High-Speed Batch Metadata Retimer, Disk Cooldown & Interactive Sorter
# Features:
#   - Phase 1 (Auto): SafeGuard quarantine, fast batch JSON format de-masquerading,
#                     timestamp retiming, folder YYYY-MM fallback, -P EXIF embedding
#                     & sync + 5s SSD cooldown buffer
#   - Phase 2 (Interactive CLI Menu with Absolute Paths):
#       [1] Sort by Device Model (Pixel / Cameras / Social)
#       [2] Sort by City-Level GPS & 4-Tier Funnel (Classic RetimeGeo + Fujifilm date names)
#       [3] Sort by Capture Year-Month (YYYY-MM)
#       [4] Process Next Folder in-place
#       [0] Keep flat & exit
# ==============================================================================

process_folder() {
  local START_TIME=$SECONDS
  local TARGET_DIR="$1"

  # 清理拖拽路径附带的首尾引号、反斜杠转义空格与末尾斜杠
  TARGET_DIR="${TARGET_DIR%\"}"
  TARGET_DIR="${TARGET_DIR#\"}"
  TARGET_DIR="${TARGET_DIR%\'}"
  TARGET_DIR="${TARGET_DIR#\'}"
  TARGET_DIR="${TARGET_DIR//\\ / }"
  TARGET_DIR="${TARGET_DIR%/}"

  if [ -z "$TARGET_DIR" ] || [ ! -d "$TARGET_DIR" ]; then
    echo "❌ [RetimeGeo v3.2] 无效的文件夹路径：$TARGET_DIR"
    return 1
  fi

  local FOLDER_NAME=$(basename "$TARGET_DIR")
  local DL_YM=$(date "+%Y:%m:")

  # SafeGuard: 清理可能因外置硬盘中断遗留的 exiftool 临时锁文件
  find "$TARGET_DIR" -maxdepth 2 -name "*_exiftool_tmp*" -delete 2>/dev/null

  # 提取目录名中的年月线索作为无日期网图兜底
  local FALLBACK_DATE=$(python3 -c '
import re, sys
name = sys.argv[1]
m = re.search(r"(20\d{2})\s*[年.\-_]?\s*(0?[1-9]|1[0-2])(?:\s*月|\b|[^0-9])", name)
if m:
    print(f"{m.group(1)}:{int(m.group(2)):02d}:15 12:00:00")
' "$FOLDER_NAME")

  local TOTAL_FILES=$(find "$TARGET_DIR" -maxdepth 1 -type f ! -name ".*" | wc -l | tr -d ' ')

  echo "=================================================================="
  echo "🧭 [RetimeGeo v3.2 Turbo Interactive] 启动阶段 1：极速校时与防卡死质检"
  echo "📁 目标目录: $FOLDER_NAME (顶层共 $TOTAL_FILES 个文件)"
  if [ -n "$FALLBACK_DATE" ]; then
    echo "📅 检测到目录年月线索，无时间线索网图将兜底设为: $FALLBACK_DATE"
  else
    echo "⚠️ 目录未含年月线索，无日期网图将保留原状或进入待定日队列"
  fi
  echo "------------------------------------------------------------------"

  echo "  [0/5] 执行 SafeGuard 防卡死质检（隔离 0 字节、损坏视频及动态 WebP）..."
  python3 - << 'GUARD_EOF' "$TARGET_DIR"
import os, sys, shutil, subprocess, json

target = sys.argv[1]
quarantine = os.path.join(target, "异常隔离-防卡死")
files = [f for f in os.listdir(target) if os.path.isfile(os.path.join(target, f)) and not f.startswith('.')]
if not files:
    sys.exit(0)

bad_reasons = {}
non_empty = []
for f in files:
    fp = os.path.join(target, f)
    if os.path.getsize(fp) == 0:
        bad_reasons[f] = "0字节空壳文件"
    else:
        non_empty.append(f)

if non_empty:
    cmd = ['exiftool', '-j', '-FileName', '-FileType', '-Error', '-Duration', '-AnimationIterations'] + [os.path.join(target, f) for f in non_empty]
    res = subprocess.run(cmd, capture_output=True, text=True)
    try:
        items = json.loads(res.stdout)
    except Exception:
        items = []
    for item in items:
        fn = item.get('FileName')
        ftype = str(item.get('FileType', '')).upper()
        err = item.get('Error')
        dur = item.get('Duration')
        anim = item.get('AnimationIterations')
        if err:
            bad_reasons[fn] = f"元数据损坏({err})"
        elif ftype in ('MP4', 'MOV') and (dur is None or str(dur) in ('0', '0 s', '0.00 s')):
            bad_reasons[fn] = "无有效时长的损坏视频"
        elif ftype == 'WEBP' and anim is not None:
            bad_reasons[fn] = "易卡死上传队列的动态WebP"

if bad_reasons:
    os.makedirs(quarantine, exist_ok=True)
    for fn, reason in bad_reasons.items():
        src = os.path.join(target, fn)
        if os.path.exists(src):
            shutil.move(src, os.path.join(quarantine, fn))
    print(f"  🛡️ 已拦截并隔离 {len(bad_reasons)} 个高危文件至「异常隔离-防卡死」")
else:
    print("  ✅ 质检通过，未发现损坏视频或异常编码文件")
GUARD_EOF

  echo "  [1/5] 同步实拍照片时间（仅处理日期异常文件，秒跳过已正确照片）..."
  exiftool -r -q -q -api QuickTimeUTC=1 -if "\$DateTimeOriginal and \$DateTimeOriginal !~ /^$DL_YM/" "-FileModifyDate<DateTimeOriginal" "-FileCreateDate<DateTimeOriginal" -overwrite_original "$TARGET_DIR" >/dev/null 2>&1

  echo "  [2/5] 同步录像（MP4/MOV）时间..."
  exiftool -r -q -q -api QuickTimeUTC=1 -ext mp4 -ext mov -if "\$CreateDate and \$CreateDate !~ /^$DL_YM/" "-FileModifyDate<CreateDate" "-FileCreateDate<CreateDate" -overwrite_original "$TARGET_DIR" >/dev/null 2>&1

  echo "  [3/5] 毫秒级批量探测并转换伪装后缀（WebP/PNG/JPEG 纠偏）..."
  python3 - << 'FAST_STEP3' "$TARGET_DIR"
import os, sys, subprocess, json

target = sys.argv[1]
exts = ('.png', '.jpg', '.jpeg', '.webp')
files = [os.path.join(target, f) for f in os.listdir(target) if os.path.isfile(os.path.join(target, f)) and f.lower().endswith(exts)]
if not files:
    sys.exit(0)

res = subprocess.run(['exiftool', '-j', '-FileType'] + files, capture_output=True, text=True)
try:
    items = json.loads(res.stdout)
except Exception:
    items = []

fixed = 0
for item in items:
    f = item.get('SourceFile', '')
    actual = str(item.get('FileType', '')).upper()
    ext_lower = os.path.splitext(f)[1].lower().lstrip('.')
    if actual == 'WEBP':
        tmp_png = os.path.splitext(f)[0] + '.tmp.png'
        new_f = os.path.splitext(f)[0] + '.jpg'
        subprocess.run(['dwebp', f, '-o', tmp_png], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['sips', '-s', 'format', 'jpeg', tmp_png, '--out', new_f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.exists(tmp_png):
            os.remove(tmp_png)
        if f != new_f and os.path.exists(new_f):
            os.remove(f)
        fixed += 1
    elif (ext_lower == 'png' and actual != 'PNG') or (ext_lower in ('jpg', 'jpeg') and actual != 'JPEG'):
        new_f = os.path.splitext(f)[0] + '.jpg'
        subprocess.run(['sips', '-s', 'format', 'jpeg', f, '--out', new_f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if f != new_f and os.path.exists(new_f):
            os.remove(f)
        fixed += 1

if fixed:
    print(f"  ✨ 已批量纠偏 {fixed} 个伪装格式文件")
FAST_STEP3

  echo "  [4/5] 破译 13 位毫秒时间戳与文件名日期（含 Screenshot_YYYYMMDD-HHMMSS）..."
  exiftool -r -q -q -api QuickTimeUTC=1 -if "not \$DateTimeOriginal or \$DateTimeOriginal =~ /^$DL_YM/" -d %s '-FileModifyDate<${filename;m/(1\d{9})\d{3}/;$_=$1}' '-FileCreateDate<${filename;m/(1\d{9})\d{3}/;$_=$1}' -overwrite_original "$TARGET_DIR" >/dev/null 2>&1
  exiftool -r -q -q -api QuickTimeUTC=1 -if "not \$DateTimeOriginal or \$DateTimeOriginal =~ /^$DL_YM/" '-FileModifyDate<${filename;s/.*?(20\d{2})(\d{2})(\d{2})[-_](\d{2})(\d{2})(\d{2}).*/$1:$2:$3 $4:$5:$6/}' '-FileCreateDate<${filename;s/.*?(20\d{2})(\d{2})(\d{2})[-_](\d{2})(\d{2})(\d{2}).*/$1:$2:$3 $4:$5:$6/}' -overwrite_original "$TARGET_DIR" >/dev/null 2>&1
  exiftool -r -q -q -api QuickTimeUTC=1 -if "not \$DateTimeOriginal or \$DateTimeOriginal =~ /^$DL_YM/" "-FileModifyDate<filename" "-FileCreateDate<filename" -overwrite_original "$TARGET_DIR" >/dev/null 2>&1

  if [ -n "$FALLBACK_DATE" ]; then
    echo "  [4.5/5] 为无时间线索网图填入文件夹年月兜底日期..."
    exiftool -r -q -q -api QuickTimeUTC=1 -if "\$FileModifyDate =~ /^$DL_YM/" "-FileModifyDate=$FALLBACK_DATE" "-FileCreateDate=$FALLBACK_DATE" -overwrite_original "$TARGET_DIR" >/dev/null 2>&1
  fi

  echo "  [5/5] 刻录磁盘时间进缺失的内部 EXIF（启用 -P 锁定 Finder 日期不变）..."
  exiftool -r -q -q -api QuickTimeUTC=1 -P -if "(not \$DateTimeOriginal or \$DateTimeOriginal =~ /^$DL_YM/) and \$FileModifyDate !~ /^$DL_YM/" "-AllDates<FileModifyDate" -overwrite_original "$TARGET_DIR" >/dev/null 2>&1

  echo "  🧊 正在同步磁盘缓存并冷却 5 秒（防止老款 SSD 连续高负载掉盘）..."
  sync && sleep 5

  local ELAPSED=$((SECONDS - START_TIME))
  echo "------------------------------------------------------------------"
  echo "✅ 阶段 1 时间与元数据校准完成（总耗时 ${ELAPSED} 秒）！"

  # 阶段 2：全 Python 绝对路径数字交互菜单循环
  while true; do
    echo "\n🎛️  [阶段 2/2 交互归档菜单] 请选择接下来的操作（输入数字后按回车）："
    echo "  [1] 按设备型号分类（如不同型号手机 / 相机机身）"
    echo "  [2] 按国家城市 + 四层漏斗分类（GPS-国家-省州-地级市 / 相机 / 手机 / 微信 / 截图）"
    echo "  [3] 按拍摄年月自动拆夹（如 2024-06 / 2024-07，适合跨月混合相册）"
    echo "  [4] 处理下一个相册（拖入新文件夹路径）"
    echo "  [0] 保持当前平铺状态不建夹，直接结束退出"
    printf "👉 请输入选项 [0-4]: "
    read -r CHOICE

    case "$CHOICE" in
      1)
        echo "\n📱 正在按设备型号（EXIF Model）拆分子文件夹..."
        python3 - << 'MODEL_EOF' "$TARGET_DIR"
import os, sys, shutil, subprocess, json

target = sys.argv[1]
files = sorted([f for f in os.listdir(target) if os.path.isfile(os.path.join(target, f)) and not f.startswith('.')])
if not files:
    print("ℹ️ 当前顶层已无待分类文件。")
    sys.exit(0)

cmd = ['exiftool', '-j', '-FileName', '-Model'] + [os.path.join(target, f) for f in files]
res = subprocess.run(cmd, capture_output=True, text=True)
try:
    meta = {item.get('FileName'): item.get('Model', '') for item in json.loads(res.stdout) if item.get('FileName')}
except Exception:
    meta = {}

for f in files:
    model = str(meta.get(f, '')).strip()
    dest = model.replace('/', '-').strip() if model else "社交与网图"
    dest_dir = os.path.join(target, dest)
    os.makedirs(dest_dir, exist_ok=True)
    shutil.move(os.path.join(target, f), os.path.join(dest_dir, f))
print("✅ 已按设备型号完成分类！当前目录结构：")
MODEL_EOF
        find "$TARGET_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null
        ls -1d "$TARGET_DIR"/*/ 2>/dev/null
        ;;
      2)
        echo "\n🌍 正在执行全球地级市解析与四层漏斗分类..."
        local TMP_PY=$(mktemp /tmp/retimegeo_sort.XXXXXX.py)
        cat << 'PYEOF' > "$TMP_PY"
import os, sys, re, shutil, subprocess, json
import reverse_geocoder as rg

target = sys.argv[1]
dl_ym = sys.argv[2]
files = sorted([f for f in os.listdir(target) if os.path.isfile(os.path.join(target, f)) and not f.startswith('.')])
total = len(files)
if total == 0:
    print("ℹ️ 当前顶层已无待分类文件。")
    sys.exit(0)

cmd = ['exiftool', '-n', '-j', '-FileName', '-FileModifyDate', '-Make', '-GPSLatitude', '-GPSLongitude'] + [os.path.join(target, f) for f in files]
res = subprocess.run(cmd, capture_output=True, text=True)
try:
    meta_list = json.loads(res.stdout)
except Exception:
    meta_list = []

meta_map = {item.get('FileName'): item for item in meta_list if item.get('FileName')}
coords, coord_files = [], []
for f in files:
    info = meta_map.get(f, {})
    lat, lon = info.get('GPSLatitude'), info.get('GPSLongitude')
    if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
        coords.append((lat, lon))
        coord_files.append(f)

gps_dest_map = {}
if coords:
    results = rg.search(coords, mode=1)
    for fname, info in zip(coord_files, results):
        cc = info.get('cc', 'Unknown')
        admin1 = info.get('admin1', '').replace(' Shi', '').strip()
        admin2 = info.get('admin2', '').replace(' Shi', '').strip()
        parts = [p.replace('/', '-').strip() for p in [cc, admin1, admin2] if p]
        dedup_parts = []
        for p in parts:
            if not dedup_parts or p != dedup_parts[-1]:
                dedup_parts.append(p)
        gps_dest_map[fname] = "GPS-" + "-".join(dedup_parts)

for idx, fname in enumerate(files, 1):
    info = meta_map.get(fname, {})
    fdate = str(info.get('FileModifyDate', ''))
    make = str(info.get('Make', ''))
    low = fname.lower()
    if fname in gps_dest_map:
        dest = gps_dest_map[fname]
    elif fdate.startswith(dl_ym):
        dest = "待手动定日-无时间线索"
    elif low.startswith(('dsc', '_dsc')) or low.endswith(('.arw', '.raf', '.cr3', '.dng')) or (re.match(r'^20\d{2}_\d{4}_\d{6}', low) and make):
        dest = "相机相册"
    elif low.startswith(('pxl_', 'vid_')):
        dest = "手机相册"
    elif low.startswith(('mmexport', 'wx_camera_')):
        dest = "微信相册"
    elif low.startswith('screenshot_'):
        dest = "截图相册"
    else:
        dest = "第三方App与其他"

    dest_dir = os.path.join(target, dest)
    os.makedirs(dest_dir, exist_ok=True)
    shutil.move(os.path.join(target, fname), os.path.join(dest_dir, fname))
    if idx % 20 == 0 or idx == total:
        print(f"\r📦 归档进度: {int(idx * 100 / total)}% ({idx}/{total})", end="", flush=True)
print("\n✅ 已完成地级市与四层漏斗归档！当前目录结构：")
PYEOF
        python3 "$TMP_PY" "$TARGET_DIR" "$DL_YM"
        rm -f "$TMP_PY"
        find "$TARGET_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null
        ls -1d "$TARGET_DIR"/*/ 2>/dev/null
        ;;
      3)
        echo "\n📅 正在按拍摄年月（YYYY-MM）拆分子文件夹..."
        python3 - << 'YM_EOF' "$TARGET_DIR"
import os, sys, shutil, subprocess, json

target = sys.argv[1]
files = sorted([f for f in os.listdir(target) if os.path.isfile(os.path.join(target, f)) and not f.startswith('.')])
if not files:
    print("ℹ️ 当前顶层已无待分类文件。")
    sys.exit(0)

cmd = ['exiftool', '-j', '-d', '%Y-%m', '-FileName', '-FileModifyDate'] + [os.path.join(target, f) for f in files]
res = subprocess.run(cmd, capture_output=True, text=True)
try:
    meta = {item.get('FileName'): item.get('FileModifyDate', '未知年月') for item in json.loads(res.stdout) if item.get('FileName')}
except Exception:
    meta = {}

for f in files:
    ym = str(meta.get(f, '未知年月')).strip() or '未知年月'
    dest_dir = os.path.join(target, ym)
    os.makedirs(dest_dir, exist_ok=True)
    shutil.move(os.path.join(target, f), os.path.join(dest_dir, f))
print("✅ 已按拍摄年月完成拆夹！当前目录结构：")
YM_EOF
        find "$TARGET_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null
        ls -1d "$TARGET_DIR"/*/ 2>/dev/null
        ;;
      4)
        printf "\n📂 请拖入【下一个相册文件夹】路径并按回车: "
        read -r NEXT_DIR
        process_folder "$NEXT_DIR"
        return $?
        ;;
      0)
        echo "\n🎉 已完成全部操作，退出 RetimeGeo v3.2 Turbo Interactive！"
        return 0
        ;;
      *)
        echo "⚠️ 无效输入，请输入 0、1、2、3 或 4。"
        ;;
    esac
  done
}

if [ -z "$1" ]; then
  printf "📂 请拖入你要处理的相册文件夹路径并按回车: "
  read -r INIT_DIR
  process_folder "$INIT_DIR"
else
  process_folder "$1"
fi
