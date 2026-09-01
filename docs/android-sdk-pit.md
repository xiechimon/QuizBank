# Android SDK 安装坑位记录 (2026-08-31)

## 症状
```
An error occurred while preparing SDK package Google Play ARM 64 v8a System Image: Read timed out.
Downloading https://dl.google.com/.../arm64-v8a-35_r09.zip
```
后续重试可能变异为：
```
java.io.IOException: Error reading Zip content from a SeekableByteChannel
Caused by: java.util.zip.ZipException: Archive is not a ZIP archive
```

## 根因（已实测）
1. **代理未透传**：macOS 系统代理 `127.0.0.1:1082` (Clash) 能被 `curl` 和 Gradle 读到，但 `sdkmanager` (Java) 默认不读 `scutil --proxy`。必须靠 `SDKMANAGER_OPTS` 显式 `-Dhttp.proxyHost/Port`。否则走 TUN FakeIP `198.18.0.16` 直连，大文件必超时。
2. **路径分叉**：`brew` 装的 `sdkmanager` (`/opt/homebrew/share/android-commandlinetools`) 和真正的 `ANDROID_HOME=/Users/xmon/Library/Android/sdk` 是两套 SDK。`brew` 版装完看似成功，但 AS/Flutter 读的是后者，导致“装了却找不到”。
3. **残留空目录**：超时后会留下 `system-images/android-35/.../arm64-v8a` 空目录 + `.temp/PackageOperation0x`，不清理会误判为已安装或反复报 Zip 异常，不支持断点续传。

## 已验证修复（一次成功）
```bash
rm -rf /Users/xmon/Library/Android/sdk/system-images/android-35 \
       /Users/xmon/Library/Android/sdk/.temp/PackageOperation*

SDKMANAGER_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=1082 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=1082" \
/Users/xmon/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --verbose --install "system-images;android-35;google_apis_playstore;arm64-v8a"

# 若 arch 为 homebrew 路径，需同步
rsync -a /opt/homebrew/share/android-commandlinetools/system-images/android-35/google_apis_playstore/arm64-v8a \
       /Users/xmon/Library/Android/sdk/system-images/android-35/google_apis_playstore/
```

## 预防
- 永远用 `/Users/xmon/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager`，别用 `which sdkmanager` (brew)
- `~/.zshrc` 常驻：
  ```bash
  export SDKMANAGER_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=1082 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=1082"
  export ANDROID_HOME=/Users/xmon/Library/Android/sdk
  ```
- 网络基准：`curl --proxy http://127.0.0.1:1082 -I https://dl.google.com/.../arm64-v8a-35_r09.zip` 应 200，`x-identity-content-length: 1789211399`，实测 50MB 下载 ~7.6MB/s 才正常

## 兜底
- 若反复 66% 截断，用 `curl -C -` 手工续传再 `unzip` 到 `system-images/...`
- 非强依赖 API 35 时，直接用已装好的 `android-36.1` 镜像建 AVD
