# Refine Encryption Progress and Settings Spec

## Why
在现有的加密过程中，进度条的速度和剩余时间计算存在延迟，且动画不够平滑，无法直观区分已完成文件和当前正在加密文件的进度。同时，用户需要更灵活的加密方式分配策略（仅硬件、仅软件、智能分配）。

## What Changes
- 修改加密速度和剩余时间的计算逻辑，采用 10 秒滑动窗口计算实时速度。
- 在性能设置页面中，兼容性测试下方增加三个加密分配选项：仅使用硬件加密、仅使用软件加密、智能分配加密方式（均使用）。
- 优化加密进度条 UI，确保已完成文件和当前正在加密文件之间有一条极细的白色分隔线。
- 为当前正在加密的文件进度部分添加渐变色效果，并确保进度条动画平滑更新（细化到按块更新 UI），而不是在单个大文件加密完成后突变。

## Impact
- Affected specs: 加密进度条 UI、设置界面、加密调度逻辑
- Affected code: `lib/encryption/services/encryption_task_manager.dart`, `lib/encryption/widgets/encryption_progress_panel.dart`, `lib/encryption/performance_settings_page.dart`

## ADDED Requirements
### Requirement: Encryption Mode Allocation Strategy
The system SHALL provide three options for encryption mode allocation in the performance settings:
1. 仅使用硬件加密 (Hardware Only)
2. 仅使用软件加密 (Software Only)
3. 智能分配加密方式 (Smart Allocation - Default)

#### Scenario: Success case
- **WHEN** user selects "Hardware Only"
- **THEN** the system strictly assigns hardware acceleration isolates for encryption tasks.

## MODIFIED Requirements
### Requirement: Real-time Speed Calculation
- **Logic**: 速度和剩余时间需基于最近 10 秒的数据计算。如果加密总时间小于 10 秒，则基于开始加密至今的平均速度计算。

### Requirement: Progress Bar UI & Chunk Animation
- **Visual**: 进度条必须用极细的白线分隔“已完全加密的文件总进度（绿色）”和“当前正在加密文件的已完成进度（渐变色）”。
- **Animation**: 确保底层在每个分块加密完成时更新状态并通知 UI，实现平滑地实时进度移动。
