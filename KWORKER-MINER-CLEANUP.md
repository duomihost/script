# Fake kworker/XMRig cleanup

用于检查和清理由以下组件组成的已知挖矿感染链：

- `/var/local/kworker`：伪装成 `kworker` 的 XMRig 矿工
- `/var/local/kthreadd`：关联守护程序
- `kworker.service`、`kthread.service`
- `/etc/cron.d/kthread`

脚本默认仅检查。只有传入 `--apply` 才会修改系统；清理前会将配置文本和文件哈希保存到
`/var/backups/kworker-miner-cleanup/`，不会备份恶意二进制。

## 一键清理

需要使用 `root` 或 `sudo`：

```bash
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT && curl -fsSL https://raw.githubusercontent.com/duomihost/script/master/cleanup-kworker-miner.sh -o "$tmp" && bash -n "$tmp" && sudo bash "$tmp" --apply
```

## 只检查

```bash
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT && curl -fsSL https://raw.githubusercontent.com/duomihost/script/master/cleanup-kworker-miner.sh -o "$tmp" && bash -n "$tmp" && bash "$tmp"
```

## 注意

此脚本只针对上述已确认的感染路径和持久化方式，不是通用杀毒软件。清理后还应轮换
`root` 密码，检查 SSH 登录记录，并优先改用密钥登录。
