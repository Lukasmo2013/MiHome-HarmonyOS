/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 莫洁安
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * 全局页面底图。
 * 用户设置自定义背景后直接展示背景图片，不叠加蒙版；
 * 未设置背景时使用纯白底，卡片靠描边和柔和阴影与底色区分。
 * 注意：背景 Image 上不添加边框/圆角/裁剪等修饰，避免触发渲染服务异常。
 */
@Component
export struct AppBackground {
  @StorageLink('backgroundImage') wallpaperImage: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.wallpaperImage.length > 0) {
        Image(this.wallpaperImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#FFFFFF')
      }
    }
    .width('100%')
    .height('100%')
  }
}
