# Checklist

- [x] 在底部导航（IndexedStack）切换与 `Navigator.push`/`pop` 转场过程中，自定义背景不闪回默认底色
- [x] 打开/关闭 Dialog 与 ModalBottomSheet 时，自定义背景不闪回默认底色
- [x] 背景图片使用无缝渲染策略（gapless/预缓存），且在路由动画期间不出现可见留白帧
- [x] 新增的版本号正则注入脚本在本地与 CI 中均可执行，且能检测并阻断“残留旧版本号”的发布
- [x] build workflow 与 release workflow 已接入版本同步 gate（失败时给出可定位输出）
- [x] README.md 中存在自动更新的“本版本摘要”区，并包含指向完整明细的链接（Release 或详细 changelog）
