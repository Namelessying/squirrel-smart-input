# 隐私说明

## 默认状态

公开版默认关闭云候选。离线状态下，本项目不包含遥测代码，不会主动向外部服务器发送输入内容。

本地学习可能产生以下文件：

- `rime_ice.userdb/`：Rime 自带的中文词频学习；
- `melt_eng.userdb/`：Rime 自带的英文词频学习；
- `predict.userdb/`：本地上下文预测数据；
- `quick_memory.tsv`：本项目的快速学习记录；
- `sogou_cloud_cache.tsv`：开启云候选后保存的本地候选缓存。

它们均位于用户自己的 Rime 数据目录，不包含在仓库中，也没有上传逻辑。

## 开启云候选后发送什么

云候选开启时，`privacy_cloud_sogou.lua` 会通过 HTTPS POST 请求：

`https://shouji.sogou.com/web_ime/mobile.php`

发送内容仅为当前尚未上屏、长度 2–32、由小写字母与 `'` 组成的拼音串。代码不会读取或附带 `custom_phrase.txt`、任何 userdb、`quick_memory.tsv` 或其他个人词典。

第三方服务仍然可能看到访问 IP、请求时间和本次拼音串。该接口不是本项目控制的正式稳定 API，隐私政策、可用性与返回内容均由第三方决定。因此，本项目使用“隐私优先”而不是“绝对不泄露”的表述。

## 本地缓存与延迟控制

- 最多缓存每个编码的前 5 个云候选；
- 缓存文件为 `sogou_cloud_cache.tsv`；
- 网络超时为 0.20 秒；
- 网络失败后暂停请求 30 秒；
- 成功但没有结果的编码在内存中负缓存 60 秒。

缓存只用于降低延迟，不会由本项目上传。退出鼠须管后删除该文件即可清空。

## 发布保护

仓库的 `.gitignore` 与 `scripts/privacy_audit.sh` 会拒绝个人词典、学习数据库、缓存、同步目录、安装标识、构建产物和本机路径。GitHub Actions 会重复执行相同检查。
