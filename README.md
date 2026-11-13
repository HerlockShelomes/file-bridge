# file-bridge

本地 Windows 与远程 GPU 服务器之间的文件互传中转站。私有仓库，不对外。

## 落盘位置

| 端 | 路径 |
| --- | --- |
| 本地 | `F:/CodeWork/file-bridge` |
| 服务器 8703 | `/data/xyfang/file-bridge` |
| 服务器 8706 | `/data/xyfang/file-bridge` |

服务器端不落 `/home`，避免写满导致 SSH 无法登录。

## 目录约定

| 目录 | 方向 | 写入方 | 读取方 |
| --- | --- | --- | --- |
| `from-local/` | 本地 → 服务器 | 本地 | 服务器 |
| `from-server/` | 服务器 → 本地 | 服务器 | 本地 |

两边都只往自己那侧写，冲突概率接近零。

## 三条命令

### 本地发文件到服务器

```bash
cd F:/CodeWork/file-bridge
./tools/send.sh E:/some/file.zip local "备注可选"

# 服务器端取走
ssh hust-server_8703 'cd /data/xyfang/file-bridge && ./tools/pull.sh'
```

### 服务器发文件到本地

```bash
# 服务器端放进来
ssh hust-server_8703
cd /data/xyfang/file-bridge
./tools/send.sh /data/xyfang/out/result.tar.gz server "调参结果"

# 本地取走
cd F:/CodeWork/file-bridge && ./tools/pull.sh
```

### 只看有没有新文件，不落地

```bash
./tools/pull.sh --dry
```

## 硬限制

- 单文件 **100 MB**：GitHub 硬上限，超了 push 直接拒收。
- 仓库累计建议 **< 1 GB**。这是中转站不是备份盘，取走即删。
- 单次推送别塞上千个小文件，push 会慢且容易超时。

超过 100 MB 的文件走 Release 附件通道，见下节。

## 大文件通道（>100 MB）

git 不适合传 ckpt / 数据集分片。用 GitHub Release 附件，单文件上限 2 GB、不占仓库体积。

```bash
# 上传（任意一端）
./tools/bigfile.sh put /data/xyfang/ckpt/epoch_24.pth "duo epoch24"

# 取回（另一端）
./tools/bigfile.sh get "duo epoch24"
```

实现细节：`tools/bigfile.sh` 调用 GitHub API 建 release + 上传附件；`get` 按标题匹配 release 并下载。

## 认证与网络

- 凭据不进仓库。本地走系统凭据管理器；服务器凭据文件在 `/data/xyfang/.git-credentials`（权限 600）。
- 本地需要走代理才能连 GitHub（直连被 reset）。仓库级 `http.proxy` 已设为 `http://127.0.0.1:7890`，不要提交到 `.git/config` 之外的地方。
- 服务器直连 GitHub 正常，无需代理。

## 换行与二进制安全

`.gitattributes` 设了 `* -text`，除 `*.sh` / `*.py` / `*.md` 强制 LF 外，所有文件按字节原样存取。传二进制不会因为 CRLF 转换导致哈希改变。仓库级 `core.autocrlf=false`。

## 清空历史

中转站用久了历史会膨胀。`from-*` 里的内容取走后可以重建历史：

```bash
./tools/reset-history.sh
```

会把当前 `from-local/` `from-server/` 清空、重建成单个 orphan commit 并强推。操作前会二次确认。

## 迁移到另一台服务器

```bash
ssh hust-server_8706
mkdir -p /data/xyfang && cd /data/xyfang
git clone https://github.com/HerlockShelomes/file-bridge.git
cd file-bridge && ./tools/setup-server.sh
```
