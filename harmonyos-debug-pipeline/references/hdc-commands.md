## 命令速查

### hilog（可用于日志）

```powershell
hilog -h                      # 查看参数
hilog -x -t app              # 非阻塞读取 app 日志
hilog -x -t app -T <tag>     # 按 tag 过滤
hilog -x -t app -P <pid>     # 按 pid 过滤
```

### 截图（snapshot_display）

```powershell
snapshot_display -f /data/local/tmp/<name>.jpeg
snapshot_display -f <file> -i <displayId> -w <w> -h <h>
```

### 拉取文件

```powershell
hdc file recv <device_path> <local_path>
hdc file send <local_path> <device_path>
```

### 安装

```powershell
hdc -t <target> install <hap_path>
```
