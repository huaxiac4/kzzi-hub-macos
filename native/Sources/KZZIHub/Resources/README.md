# 资源文件说明

这个目录里只提交了从官方 layout XML 里整理出来的功能数据：

- `k98_layout.json`：96 个键的坐标 + LED 索引
- `modes.json`：17 种灯效
- `keymap.json`：Windows / macOS 键位名称 + Fn 组合

下面两个图片资源**没有**提交（版权属于 KZZI 官方，请从你自己购买的键盘的官方
Windows 驱动里提取），缺失时应用会自动降级为纯色背景 / 占位图：

- `k98.png`：设备中心的键盘渲染图
- `bg-stars.png`：星空背景

提取方法（需要 `innoextract`）：

```bash
brew install innoextract
innoextract -e -d kzzi-driver KzziHub_Setup.exe
cp kzzi-driver/app/skins/theme1/device/k98_connected.png  k98.png
cp kzzi-driver/app/skins/theme1/main_bkg_1.png            bg-stars.png
```

把这两个文件放到本目录，重新构建即可。
