#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 docs/images 下的界面预览图。

为什么不用无头浏览器：本机 RLIMIT_AS 被限制在 4GB，Chromium 的
PartitionAlloc 无法保留地址空间，会直接 abort。改用 SVG + cairosvg
离屏渲染，产出 2 倍分辨率的 PNG，可直接嵌进 README / 系统介绍.html。

用法：
    python tools/gen_docs_previews.py            # 生成全部
    python tools/gen_docs_previews.py home mine  # 只生成指定页面

设计 token 与 entry/src/main/ets/utils/DesignTokens.ets 保持一致。
"""

import os
import sys

import cairosvg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'docs', 'images')

# ---------- 设计 token（与 DesignTokens.ets 同步） ----------
BG = '#FFFFFF'
PRIMARY = '#3E9AA6'
PRIMARY_DARK = '#2F8C96'
PRIMARY_SOFT = '#EAF5F6'
TEXT = '#172226'
SUB = '#6E8083'
BORDER = '#E2EDED'
ONLINE = '#2AA98C'
DANGER = '#D94838'
FONT = "Noto Sans CJK SC, Noto Sans SC, Source Han Sans SC, sans-serif"

W, H = 390, 844


class Svg:
    """极简 SVG 拼装器：只保留这套界面需要的能力。"""

    def __init__(self, w=W, h=H, defs=''):
        self.w = w
        self.h = h
        self.body = []
        self.defs = defs

    def add(self, raw):
        self.body.append(raw)

    def render(self):
        defs = f'<defs>{self.defs}</defs>' if self.defs else ''
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
            f'viewBox="0 0 {self.w} {self.h}">{defs}'
            + ''.join(self.body) + '</svg>'
        )


def esc(s):
    return (str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))


def rect(x, y, w, h, r=0, fill='none', stroke='none', sw=1, opacity=1.0, extra=''):
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" ry="{r}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}" {extra}/>'
    )


def text(x, y, s, size=13, fill=TEXT, weight=400, anchor='start', opacity=1.0,
         spacing=None, extra=''):
    sp = f'letter-spacing="{spacing}"' if spacing else ''
    return (
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" fill="{fill}" '
        f'font-weight="{weight}" text-anchor="{anchor}" opacity="{opacity}" {sp} {extra}>'
        f'{esc(s)}</text>'
    )


def circle(cx, cy, r, fill='none', stroke='none', sw=1, opacity=1.0):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" '
            f'stroke-width="{sw}" opacity="{opacity}"/>')


def card(x, y, w, h, r=14, fill=BG, shadow=True):
    """白卡 + 浅描边 + 柔和阴影（阴影用双层描边模拟，避免滤镜在某些环境失真）"""
    out = ''
    if shadow:
        out += rect(x + 0.5, y + 2, w, h, r, fill=PRIMARY, opacity=0.05)
    out += rect(x, y, w, h, r, fill=fill, stroke=BORDER, sw=1)
    return out


def status_bar(svg, dark=True):
    fg = TEXT if dark else '#FFFFFF'
    svg.add(text(22, 30, '9:41', 13, fg, 600))
    # 信号 / Wi-Fi / 电池
    x = 296
    for i in range(4):
        hh = 4 + i * 2.4
        svg.add(rect(x + i * 4.4, 30 - hh, 3, hh, 1, fg))
    svg.add(circle(326, 23.5, 5.4, 'none', fg, 1.4))
    svg.add(rect(340, 18, 24, 11, 3, 'none', fg, 1.2))
    svg.add(rect(342.5, 20.5, 15, 6, 1.5, fg))
    svg.add(rect(365, 21, 2, 5, 1, fg, opacity=0.6))


def tab_bar(svg, active=0):
    labels = ['首页', '智能', '信息', '我的']
    y = H - 62
    svg.add(rect(0, y, W, 62, 0, BG))
    svg.add(rect(0, y, W, 1, 0, BORDER))
    for i, label in enumerate(labels):
        cx = W / 8 + i * (W / 4)
        on = i == active
        color = PRIMARY if on else SUB
        # 图标：用几何近似
        if i == 0:
            svg.add(f'<path d="M{cx-9} {y+26} l9 -8 l9 8 v9 h-6 v-6 h-6 v6 h-6 z" '
                    f'fill="{color}" opacity="{1 if on else 0.9}"/>')
        elif i == 1:
            svg.add(f'<path d="M{cx+1} {y+16} l-7 12 h6 l-2 8 l8 -12 h-6 z" fill="{color}"/>')
        elif i == 2:
            svg.add(f'<path d="M{cx-8} {y+18} h16 v10 l3 4 h-22 l3 -4 z" fill="{color}"/>')
        else:
            svg.add(circle(cx, y + 20, 4, color))
            svg.add(f'<path d="M{cx-8} {y+34} a8 8 0 0 1 16 0 z" fill="{color}"/>')
        svg.add(text(cx, y + 48, label, 11, color, 500 if on else 400, 'middle'))


def pill(x, y, label, active=False, w=None, h=30, size=12):
    ww = w or (len(label) * size + 26)
    fill = PRIMARY_SOFT if active else BG
    stroke = PRIMARY if active else BORDER
    color = PRIMARY_DARK if active else SUB
    return (rect(x, y, ww, h, h / 2, fill, stroke, 1)
            + text(x + ww / 2, y + h / 2 + size * 0.36, label, size, color,
                   500 if active else 400, 'middle'))


def switch(x, y, on=True, w=44, h=26):
    if on:
        return (rect(x, y, w, h, h / 2, PRIMARY)
                + circle(x + w - h / 2, y + h / 2, h / 2 - 2.5, '#FFFFFF'))
    return (rect(x, y, w, h, h / 2, '#D7E4E5')
            + circle(x + h / 2, y + h / 2, h / 2 - 2.5, '#FFFFFF'))


def power_icon(cx, cy, r, on=True, color=None):
    c = color or (PRIMARY if on else '#B9CBCD')
    return (circle(cx, cy, r, PRIMARY_SOFT if on else '#EFF4F4')
            + f'<path d="M{cx} {cy-r*0.5} v{r*0.55}" stroke="{c}" stroke-width="1.8" '
              f'stroke-linecap="round"/>'
            + f'<path d="M{cx-r*0.46} {cy-r*0.2} a{r*0.55} {r*0.55} 0 1 0 {r*0.92} 0" '
              f'fill="none" stroke="{c}" stroke-width="1.8" stroke-linecap="round"/>')


# ---------------- 页面 1：首页 ----------------
def page_home():
    svg = Svg(defs=f'''
      <linearGradient id="fog" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="{PRIMARY}" stop-opacity="0.10"/>
        <stop offset="0.35" stop-color="{PRIMARY}" stop-opacity="0.03"/>
        <stop offset="1" stop-color="{PRIMARY}" stop-opacity="0"/>
      </linearGradient>
      <linearGradient id="lamp" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#BFE6E4"/><stop offset="1" stop-color="#8FD0D2"/>
      </linearGradient>''')
    svg.add(rect(0, 0, W, 320, 0, 'url(#fog)'))
    status_bar(svg)

    # 头部
    svg.add(text(22, 74, 'MiHome', 22, TEXT, 700))
    svg.add(text(22, 96, '我的家 · 8 台设备在线', 11.5, SUB))
    svg.add(circle(348, 76, 17, '#EFF6F6'))
    svg.add(text(348, 81, '莫', 13, PRIMARY_DARK, 500, 'middle'))

    # 家庭选择入口
    svg.add(rect(22, 110, 118, 34, 17, BG, BORDER))
    svg.add(f'<path d="M33 130 l7 -6 l7 6 v6 h-4 v-4 h-6 v4 h-4 z" fill="{PRIMARY}"/>')
    svg.add(text(52, 132, '我的家', 13, TEXT, 500))
    svg.add(f'<path d="M124 126 l4 4 l4 -4" stroke="{SUB}" stroke-width="1.5" fill="none" '
            f'stroke-linecap="round"/>')
    svg.add(text(300, 132, '今天 24°  多云', 11.5, SUB, 400, 'end'))

    # 搜索框
    svg.add(rect(22, 156, W - 44, 38, 19, BG, BORDER))
    svg.add(circle(40, 175, 5, 'none', SUB, 1.5))
    svg.add(f'<path d="M44 179 l5 5" stroke="{SUB}" stroke-width="1.5" stroke-linecap="round"/>')
    svg.add(text(56, 180, '搜索设备名称、型号或房间', 13, SUB))
    svg.add(text(W - 38, 181, '≡', 15, SUB, 400, 'middle'))

    # 房间 chips
    chips = [('全部', True), ('客厅', False), ('主卧', False), ('书房', False)]
    x = 22
    for label, on in chips:
        ww = len(label) * 12 + 26
        svg.add(pill(x, 206, label, on, ww, 30))
        x += ww + 8

    # 概览两卡
    oy = 250
    cw = (W - 44 - 12) / 2
    for i, (title, value, sub, icon) in enumerate([
            ('温度', '24.5', '设定 26°C · 客厅', 'thermo'),
            ('湿度', '52', '舒适区间 · 全屋', 'drop')]):
        x = 22 + i * (cw + 12)
        svg.add(card(x, oy, cw, 96))
        if icon == 'thermo':
            svg.add(rect(x + 14, oy + 16, 3, 16, 1.5, PRIMARY))
            svg.add(circle(x + 15.5, oy + 34, 5, PRIMARY))
        else:
            svg.add(f'<path d="M{x+15} {oy+16} c8 10 8 14 0 19 c-8 -5 -8 -9 0 -19 z" fill="{PRIMARY}"/>')
        svg.add(text(x + 32, oy + 24, title, 12, SUB))
        unit = '°C' if title == '温度' else '%'
        svg.add(
            f'<text x="{x+14}" y="{oy+68}" font-family="{FONT}" font-size="26" fill="{TEXT}" '
            f'font-weight="600">{value}<tspan font-size="13" fill="{SUB}">{unit}</tspan></text>'
        )
        svg.add(text(x + 14, oy + 86, sub, 10, SUB))

    # 设备区标题
    svg.add(text(22, 380, '常用设备', 14, TEXT, 600))
    svg.add(text(W - 22, 380, '全部 12 台 ›', 11.5, SUB, 400, 'end'))

    # 设备网格 2×2
    devices = [
        ('客厅灯', '亮度 62% · 2700K', 'on', 'lamp'),
        ('空调', '制冷 26°C · 自动风', 'on', 'ac'),
        ('扫地机器人', '充电中 87%', 'off', 'robot'),
        ('空气净化器', 'PM2.5 12 · 自动', 'on', 'purifier'),
    ]
    gy = 396
    gw = (W - 44 - 12) / 2
    gh = 128
    for idx, (name, sub, state, kind) in enumerate(devices):
        col = idx % 2
        row = idx // 2
        x = 22 + col * (gw + 12)
        y = gy + row * (gh + 12)
        svg.add(card(x, y, gw, gh))
        # 星标
        svg.add(f'<path d="M{x+gw-20} {y+15} l2.6 5.4 l6 0.8 l-4.4 4.2 l1 6 l-5.2 -2.8 l-5.2 2.8 l1 -6 l-4.4 -4.2 l6 -0.8 z" '
                f'fill="none" stroke="#CBDDDD" stroke-width="1.1"/>')
        # 图标
        cx = x + 30
        cy = y + 40
        if kind == 'lamp':
            svg.add(circle(cx, cy, 18, 'url(#lamp)'))
            svg.add(f'<path d="M{cx-7} {cy+3} a7 7 0 1 1 14 0 h-5 v4 h-4 v-4 z" fill="#FFFFFF"/>')
        elif kind == 'ac':
            svg.add(circle(cx, cy, 18, PRIMARY_SOFT))
            svg.add(rect(cx - 10, cy - 5, 20, 9, 2.5, PRIMARY))
            svg.add(rect(cx - 7, cy + 6, 14, 1.6, 0.8, PRIMARY, opacity=0.5))
        elif kind == 'robot':
            svg.add(circle(cx, cy, 18, '#F0F5F5'))
            svg.add(circle(cx, cy, 12, 'none', PRIMARY, 2))
            svg.add(circle(cx, cy, 4, PRIMARY, opacity=0.35))
        else:
            svg.add(circle(cx, cy, 18, PRIMARY_SOFT))
            svg.add(rect(cx - 8, cy - 9, 16, 18, 4, 'none', PRIMARY, 1.6))
            svg.add(f'<path d="M{cx-4} {cy-2} h8 M{cx-4} {cy+3} h8" stroke="{PRIMARY}" stroke-width="1.4"/>')
        # 名称 / 状态
        svg.add(text(x + 56, y + 34, name, 13, TEXT, 500))
        svg.add(circle(x + 59, y + 48, 2.6, ONLINE if state == 'on' else '#B9CBCD'))
        svg.add(text(x + 66, y + 52, '在线' if state == 'on' else '离线', 10, SUB))
        svg.add(text(x + 14, y + 82, sub, 11, SUB))
        # 电源按钮（右下角）
        svg.add(power_icon(x + gw - 26, y + gh - 26, 15, state == 'on'))
        # 底部分隔线 + 快捷操作
        svg.add(rect(x + 14, y + gh - 44, gw - 28, 1, 0, BORDER))

    tab_bar(svg, 0)
    return svg


# ---------------- 页面 2：家庭选择 ----------------
def page_family():
    svg = Svg()
    status_bar(svg)
    svg.add(text(22, 74, 'MiHome', 22, TEXT, 700))
    svg.add(text(22, 96, '我的家 · 8 台设备在线', 11.5, SUB))
    # 背景内容（压暗）
    svg.add(rect(22, 110, 118, 34, 17, BG, BORDER))
    svg.add(f'<path d="M33 130 l7 -6 l7 6 v6 h-4 v-4 h-6 v4 h-4 z" fill="{PRIMARY}"/>')
    svg.add(text(52, 132, '我的家', 13, TEXT, 500))
    svg.add(f'<path d="M120 126 l5 5 l5 -5" stroke="{SUB}" stroke-width="1.5" fill="none" '
            f'stroke-linecap="round"/>')
    svg.add(rect(22, 156, W - 44, 38, 19, BG, BORDER))
    svg.add(circle(40, 175, 5, 'none', SUB, 1.5))
    svg.add(text(56, 180, '搜索设备名称、型号或房间', 13, SUB))
    svg.add(rect(22, 206, 62, 30, 15, PRIMARY_SOFT, PRIMARY))
    svg.add(text(53, 226, '全部', 12, PRIMARY_DARK, 500, 'middle'))
    svg.add(rect(92, 206, 62, 30, 15, BG, BORDER))
    svg.add(text(123, 226, '客厅', 12, SUB, 400, 'middle'))
    svg.add(rect(162, 206, 62, 30, 15, BG, BORDER))
    svg.add(text(193, 226, '主卧', 12, SUB, 400, 'middle'))
    svg.add(rect(22, 250, 168, 96, 14, BG, BORDER))
    svg.add(text(36, 270, '温度', 11, SUB))
    svg.add(text(36, 306, '24.5', 24, TEXT, 600))
    svg.add(text(36, 328, '设定 26°C · 客厅', 9.5, SUB))
    svg.add(rect(202, 250, 166, 96, 14, BG, BORDER))
    svg.add(text(216, 270, '湿度', 11, SUB))
    svg.add(text(216, 306, '52%', 24, TEXT, 600))
    svg.add(text(216, 328, '舒适区间 · 全屋', 9.5, SUB))
    svg.add(text(22, 380, '常用设备', 14, TEXT, 600))
    svg.add(rect(22, 396, 168, 128, 14, BG, BORDER))
    svg.add(circle(52, 436, 18, '#E4F2F2'))
    svg.add(text(78, 430, '客厅灯', 12.5, TEXT, 500))
    svg.add(text(36, 496, '亮度 62% · 2700K', 10.5, SUB))
    svg.add(power_icon(168, 498, 14, True))
    svg.add(rect(202, 396, 166, 128, 14, BG, BORDER))
    svg.add(circle(232, 436, 18, PRIMARY_SOFT))
    svg.add(text(258, 430, '空调', 12.5, TEXT, 500))
    svg.add(text(216, 496, '制冷 26°C · 自动风', 10.5, SUB))
    svg.add(power_icon(348, 498, 14, True))
    svg.add(rect(0, 0, W, H, 0, '#0F2A2E', opacity=0.28))

    # 弹层
    sy = 300
    svg.add(rect(0, sy, W, H - sy, 26, BG))
    svg.add(rect(W / 2 - 18, sy + 10, 36, 4, 2, '#DCE6E6'))
    svg.add(text(24, sy + 50, '选择家庭', 17, TEXT, 600))
    svg.add(text(W - 24, sy + 50, '管理', 12, PRIMARY_DARK, 400, 'end'))

    homes = [
        ('我的家', '3 个房间 · 12 台设备', True),
        ('父母家', '2 个房间 · 6 台设备', False),
        ('工作室', '1 个房间 · 4 台设备', False),
    ]
    y = sy + 70
    for name, sub, on in homes:
        svg.add(card(20, y, W - 40, 66, 14))
        svg.add(rect(20, y, 3, 66, 1.5, PRIMARY if on else 'none'))
        svg.add(circle(52, y + 33, 16, PRIMARY_SOFT if on else '#F2F7F7'))
        svg.add(f'<path d="M44 {y+36} l8 -7 l8 7 v8 h-5 v-5 h-6 v5 h-5 z" '
                f'fill="{PRIMARY if on else SUB}"/>')
        svg.add(text(80, y + 29, name, 14, TEXT, 500))
        svg.add(text(80, y + 47, sub, 11, SUB))
        if on:
            svg.add(circle(W - 46, y + 33, 11, PRIMARY))
            svg.add(f'<path d="M{W-51} {y+33} l3.6 3.6 l6 -7" stroke="#FFFFFF" stroke-width="1.8" '
                    f'fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            svg.add(circle(W - 46, y + 33, 10.5, 'none', '#D8E4E4', 1.3))
        y += 78

    svg.add(rect(20, y + 6, W - 40, 46, 14, PRIMARY_SOFT, BORDER))
    svg.add(text(W / 2, y + 34, '＋ 添加家庭', 13.5, PRIMARY_DARK, 500, 'middle'))
    svg.add(text(W / 2, y + 92, '切换家庭后，首页只显示该家庭的房间与设备', 11, SUB, 400, 'middle'))
    return svg


# ---------------- 页面 3：我的 ----------------
def page_mine():
    svg = Svg(defs=f'''
      <linearGradient id="fog2" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="{PRIMARY}" stop-opacity="0.09"/>
        <stop offset="1" stop-color="{PRIMARY}" stop-opacity="0"/>
      </linearGradient>''')
    svg.add(rect(0, 0, W, 300, 0, 'url(#fog2)'))
    status_bar(svg)
    svg.add(text(22, 74, '我的', 22, TEXT, 700))

    # 账号卡
    y = 96
    svg.add(card(20, y, W - 40, 104))
    svg.add(circle(52, y + 36, 24, '#E5EEEE'))
    svg.add(circle(52, y + 30, 8, '#9FB8B8'))
    svg.add(f'<path d="M40 {y+48} a12 12 0 0 1 24 0 z" fill="#9FB8B8"/>')
    svg.add(text(86, y + 32, '莫洁安', 16, TEXT, 500))
    svg.add(text(86, y + 52, '小米账号 2189 **** 7731', 11.5, SUB))
    svg.add(rect(20 + 12, y + 68, W - 64, 1, 0, BORDER))
    svg.add(text(32, y + 90, '退出登录', 13, DANGER))
    svg.add(text(W - 44, y + 90, '›', 14, SUB, 400, 'end'))

    # 桌面卡片入口（重点）
    y2 = y + 116
    svg.add(card(20, y2, W - 40, 70))
    svg.add(rect(34, y2 + 18, 34, 34, 10, PRIMARY_SOFT))
    svg.add(rect(40, y2 + 25, 12, 9, 2.5, 'none', PRIMARY, 1.4))
    svg.add(rect(48, y2 + 33, 12, 9, 2.5, 'none', PRIMARY, 1.4))
    svg.add(text(80, y2 + 30, '桌面卡片', 14.5, TEXT, 500))
    svg.add(text(80, y2 + 49, '已添加 3 张卡片 · 点此管理设备与样式', 10, SUB))
    svg.add(text(W - 36, y2 + 35, '›', 15, SUB, 400, 'middle'))

    # 功能列表
    rows = [('耗材中心', '滤芯、刷头到期提醒'), ('房间管理', '4 个房间'),
            ('设备管理', '排序、隐藏、重命名'), ('家庭成员', '3 位成员'),
            ('外观与主题', '雾玻璃浅蓝绿'), ('备份与恢复', '本地快照')]
    y3 = y2 + 84
    svg.add(card(20, y3, W - 40, len(rows) * 52))
    for i, (title, sub) in enumerate(rows):
        ry = y3 + i * 52
        svg.add(circle(48, ry + 26, 14, '#F2F7F7'))
        svg.add(circle(48, ry + 26, 4.5, PRIMARY, opacity=0.75))
        svg.add(text(72, ry + 23, title, 14, TEXT, 400))
        svg.add(text(72, ry + 39, sub, 10.5, SUB))
        svg.add(text(W - 36, ry + 30, '›', 14, SUB, 400, 'end'))
        if i < len(rows) - 1:
            svg.add(rect(72, ry + 52, W - 108, 1, 0, BORDER))

    svg.add(text(W / 2, y3 + len(rows) * 52 + 26, 'MiHome 2.1.0 · 版权 莫洁安', 10.5, SUB, 400, 'middle'))
    tab_bar(svg, 3)
    return svg


# ---------------- 页面 4：卡片管理中心 ----------------
def preview_card(x, y, w, h, name='客厅灯', value='已开启', room='客厅', big=False):
    """卡片服务预览：与 MiHomeDeviceCard.ets 的 2*2 版式一致"""
    out = card(x, y, w, h, 16)
    out += rect(x + 14, y + 14, 26, 26, 8, PRIMARY_SOFT)
    out += f'<path d="M{x+21} {y+29} a6 6 0 1 1 12 0 h-4 v3 h-4 v-3 z" fill="{PRIMARY}"/>'
    out += text(x + 48, y + 24, name, 12, TEXT, 500)
    out += circle(x + 50, y + 33, 2.4, ONLINE)
    out += text(x + 56, y + 36, room + ' · 在线', 9, SUB)
    out += power_icon(x + w - 22, y + 26, 12, True)
    out += text(x + 14, y + h - (30 if not big else 56), value, 22 if not big else 24, TEXT, 600)
    out += text(x + 14, y + h - (14 if not big else 22), '亮度 62% · 2700K', 9, SUB)
    return out


def page_card_manager():
    svg = Svg()
    status_bar(svg)
    # 导航
    svg.add(text(24, 76, '‹', 20, TEXT, 400))
    svg.add(text(195, 76, '桌面卡片', 17, TEXT, 600, 'middle'))
    svg.add(text(W - 24, 76, '说明', 11.5, PRIMARY_DARK, 400, 'end'))

    # 实时预览
    svg.add(text(22, 100, '效果预览', 11.5, SUB, 500))
    svg.add(rect(20, 108, W - 40, 142, 18, '#F4FAFA', BORDER))
    svg.add(circle(W / 2 + 44, 146, 28, PRIMARY, opacity=0.06))
    svg.add(preview_card(36, 124, W - 72, 110, '客厅灯', '已开启', '客厅', True))
    svg.add(text(W / 2, 266, '实时预览 · 2*2 标准方形', 9.5, SUB, 400, 'middle'))

    # 选择家电
    svg.add(text(22, 292, '选择家电', 13, TEXT, 600))
    svg.add(text(W - 22, 292, '在线优先', 10, SUB, 400, 'end'))
    svg.add(rect(20, 300, W - 40, 30, 15, BG, BORDER))
    svg.add(circle(37, 315, 4.2, 'none', SUB, 1.4))
    svg.add(text(48, 319, '搜索设备名或房间', 11, SUB))

    picks = [('客厅灯', '客厅', True), ('空调', '客厅', False),
             ('扫地机器人', '阳台', False), ('空气净化器', '主卧', False)]
    pw = (W - 40 - 10) / 2
    for i, (name, room, on) in enumerate(picks):
        col = i % 2
        row = i // 2
        x = 20 + col * (pw + 10)
        y = 338 + row * 50
        svg.add(rect(x, y, pw, 44, 12, PRIMARY_SOFT if on else BG,
                     PRIMARY if on else BORDER, 1.2 if on else 1))
        svg.add(circle(x + 19, y + 22, 9, '#FFFFFF' if on else PRIMARY_SOFT))
        svg.add(circle(x + 19, y + 22, 3.2, PRIMARY if on else '#A9BFBF'))
        svg.add(text(x + 34, y + 19, name, 11, TEXT, 500 if on else 400))
        svg.add(text(x + 34, y + 33, room, 8.5, SUB))
        if on:
            svg.add(f'<path d="M{x+pw-21} {y+21} l3 3 l5 -6" stroke="{PRIMARY}" stroke-width="1.8" '
                    f'fill="none" stroke-linecap="round" stroke-linejoin="round"/>')

    # 展示内容
    svg.add(text(22, 458, '展示内容', 13, TEXT, 600))
    items = [('开关状态', True), ('在线状态', False), ('设备名称', False),
             ('所在房间', False), ('设备型号', False), ('自定义文字', False)]
    x, y = 20, 468
    for label, on in items:
        ww = len(label) * 11.5 + 22
        if x + ww > W - 20:
            x = 20
            y += 38
        svg.add(pill(x, y, label, on, ww, 30, 11.5))
        x += ww + 8
    svg.add(text(22, y + 50, '主区域显示「已开启／已关闭」，状态点跟随在线情况', 9.5, SUB))

    # 规格
    sy = y + 72
    svg.add(text(22, sy, '规格', 13, TEXT, 600))
    svg.add(text(W - 22, sy, '标准方形最百搭', 9.5, SUB, 400, 'end'))
    specs = [('1*2', 60, 30, False), ('2*2', 48, 48, True), ('2*4', 66, 33, False), ('4*4', 52, 52, False)]
    cx = 20
    for label, bw, bh, on in specs:
        svg.add(rect(cx, sy + 8, 78, 92, 12, PRIMARY_SOFT if on else BG,
                     PRIMARY if on else BORDER, 1.2 if on else 1))
        bx = cx + (78 - bw) / 2
        by = sy + 16
        svg.add(rect(bx, by, bw, bh, 5, PRIMARY if on else '#DCEAEB'))
        svg.add(text(cx + 39, sy + 86, label, 10.5, PRIMARY_DARK if on else SUB,
                     600 if on else 400, 'middle'))
        cx += 78 + 8

    # 按钮
    by = sy + 112
    svg.add(rect(20, by, (W - 40) * 0.56, 44, 22, PRIMARY))
    svg.add(text(20 + (W - 40) * 0.28, by + 28, '添加到桌面', 14, '#FFFFFF', 500, 'middle'))
    svg.add(rect(20 + (W - 40) * 0.6, by, (W - 40) * 0.4 - 2, 44, 22, BG, PRIMARY, 1.2))
    svg.add(text(20 + (W - 40) * 0.8, by + 28, '设为默认', 13.5, PRIMARY_DARK, 500, 'middle'))

    # 已添加卡片
    ly = by + 62
    svg.add(text(22, ly, '已添加的卡片', 13, TEXT, 600))
    svg.add(text(W - 22, ly, '全部刷新', 10.5, PRIMARY_DARK, 400, 'end'))
    svg.add(card(20, ly + 10, W - 40, 56))
    svg.add(rect(32, ly + 22, 32, 32, 9, PRIMARY_SOFT))
    svg.add(circle(48, ly + 38, 7.5, 'none', PRIMARY, 1.6))
    svg.add(text(76, ly + 34, '客厅灯 · 开关状态', 12, TEXT, 500))
    svg.add(text(76, ly + 50, '2*2 · 桌面第 1 张 · 在线', 9, SUB))
    svg.add(rect(W - 76, ly + 26, 50, 22, 11, BG, BORDER))
    svg.add(text(W - 51, ly + 41, '刷新', 9.5, PRIMARY_DARK, 400, 'middle'))

    svg.add(text(W / 2, H - 18, '桌面长按空白 → 添加卡片，也可用这套样式', 9.5, SUB, 400, 'middle'))
    return svg


# ---------------- 页面 5：四规格卡片 ----------------
def page_widgets():
    w, h = 1200, 720
    svg = Svg(w, h, defs=f'''
      <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#E8F4F4"/><stop offset="0.5" stop-color="#F7FBFB"/>
        <stop offset="1" stop-color="#DEEDEE"/>
      </linearGradient>''')
    svg.add(rect(0, 0, w, h, 0, 'url(#desk)'))
    svg.add(circle(1100, 70, 150, PRIMARY, opacity=0.05))
    svg.add(circle(90, 690, 120, PRIMARY, opacity=0.05))
    svg.add(text(60, 72, '桌面卡片 · 四种规格', 26, TEXT, 700))
    svg.add(text(60, 102, '白底 + 深墨主值 + 浅蓝绿点缀；离线只灰化状态点，卡片本身保持可读', 13, SUB))
    svg.add(text(w - 60, 102, 'MiHome 2.1.0', 12, SUB, 400, 'end'))

    def plate(x, y, pw, ph, label):
        """每个规格一块半透明底板，底板之间不重叠"""
        svg.add(rect(x, y, pw, ph, 22, '#FFFFFF', opacity=0.5))
        svg.add(text(x + 18, y + ph - 18, label, 12.5, PRIMARY_DARK, 600))

    # ---- 1*2：扁条 ----
    px, py, pw, ph = 60, 150, 500, 210
    plate(px, py, pw, ph, '1*2 · 扁条')
    cw, ch = 240, 108
    x, y = px + (pw - cw) / 2, py + 44
    svg.add(card(x, y, cw, ch, 18))
    svg.add(rect(x + 14, y + ch / 2 - 14, 28, 28, 9, PRIMARY_SOFT))
    svg.add(f'<path d="M{x+22} {y+ch/2+1} a6 6 0 1 1 12 0 h-4 v3 h-4 v-3 z" fill="{PRIMARY}"/>')
    svg.add(text(x + 50, y + ch / 2 - 6, '客厅灯', 12.5, TEXT, 500))
    svg.add(circle(x + 52, y + ch / 2 + 8, 2.4, ONLINE))
    svg.add(text(x + 59, y + ch / 2 + 11, '在线 · 客厅', 9.5, SUB))
    svg.add(text(x + 150, y + ch / 2 + 6, '已开启', 15, PRIMARY_DARK, 600))
    svg.add(power_icon(x + cw - 24, y + ch / 2, 13, True))

    # ---- 2*2：标准方形 ----
    px, py, pw, ph = 640, 150, 500, 210
    plate(px, py, pw, ph, '2*2 · 标准方形')
    cw, ch = 176, 176
    svg.add(preview_card(px + (pw - cw) / 2, py + 14, cw, ch, '客厅灯', '已开启', '客厅', True))

    # ---- 2*4：宽卡 ----
    px, py, pw, ph = 60, 390, 500, 270
    plate(px, py, pw, ph, '2*4 · 宽卡')
    cw, ch = 396, 172
    x, y = px + (pw - cw) / 2, py + 30
    svg.add(card(x, y, cw, ch, 18))
    svg.add(rect(x + 16, y + 16, 28, 28, 9, PRIMARY_SOFT))
    svg.add(f'<path d="M{x+23} {y+33} a7 7 0 1 1 14 0 h-4 v3 h-6 v-3 z" fill="{PRIMARY}"/>')
    svg.add(text(x + 52, y + 27, '空调', 13, TEXT, 500))
    svg.add(circle(x + 54, y + 36, 2.4, ONLINE))
    svg.add(text(x + 60, y + 39, '客厅 · 在线', 9.5, SUB))
    svg.add(power_icon(x + cw - 24, y + 30, 13, True))
    svg.add(text(x + 16, y + 96, '制冷 26°C', 24, TEXT, 600))
    svg.add(text(x + 16, y + 118, '风速 自动 · 客厅', 10, SUB))
    svg.add(rect(x + cw / 2 + 8, y + 74, 1, 60, 0, BORDER))
    svg.add(text(x + cw / 2 + 24, y + 92, '室内 27.4°C', 11, SUB))
    svg.add(text(x + cw / 2 + 24, y + 110, '湿度 51%', 11, SUB))
    svg.add(text(x + cw / 2 + 24, y + 128, '运行 2 小时 12 分', 11, SUB))

    # ---- 4*4：大方卡 ----
    px, py, pw, ph = 640, 390, 500, 270
    plate(px, py, pw, ph, '4*4 · 大方卡')
    cw, ch = 232, 232
    x, y = px + (pw - cw) / 2, py + 12
    svg.add(card(x, y, cw, ch, 20))
    svg.add(rect(x + 16, y + 16, 28, 28, 9, PRIMARY_SOFT))
    svg.add(f'<path d="M{x+23} {y+33} a7 7 0 1 1 14 0 h-4 v3 h-6 v-3 z" fill="{PRIMARY}"/>')
    svg.add(text(x + 50, y + 26, '空气净化器', 12.5, TEXT, 500))
    svg.add(circle(x + 52, y + 36, 2.4, ONLINE))
    svg.add(text(x + 58, y + 39, '主卧 · 在线', 9, SUB))
    svg.add(power_icon(x + cw - 24, y + 30, 13, True))
    svg.add(text(x + 16, y + 92, '自动', 34, TEXT, 600))
    svg.add(text(x + 16, y + 112, 'PM2.5 12 · 空气优', 10, SUB))
    svg.add(rect(x + 16, y + 128, cw - 32, 1, 0, BORDER))
    svg.add(text(x + 16, y + 150, '滤芯剩余 68%', 10, SUB))
    svg.add(rect(x + 16, y + 162, cw - 32, 5, 2.5, '#E6F0F0'))
    svg.add(rect(x + 16, y + 162, (cw - 32) * 0.68, 5, 2.5, PRIMARY))
    svg.add(rect(x + 16, y + 182, cw - 32, 34, 17, PRIMARY_SOFT, BORDER))
    svg.add(text(x + cw / 2, y + 204, '打开设备', 12.5, PRIMARY_DARK, 500, 'middle'))

    svg.add(text(w / 2, h - 22, '同一套 token 渲染四种尺寸：主值字号随规格放大，1*2 仍保留设备名与在线状态', 11, SUB, 400, 'middle'))
    return svg



# ---------------- 页面 6：网页授权登录 ----------------
def page_login():
    svg = Svg(defs=f'''
      <linearGradient id="fog3" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="{PRIMARY}" stop-opacity="0.12"/>
        <stop offset="1" stop-color="{PRIMARY}" stop-opacity="0"/>
      </linearGradient>''')
    svg.add(rect(0, 0, W, 400, 0, 'url(#fog3)'))
    status_bar(svg)
    # 标题栏
    svg.add(circle(38, 76, 17, BG, BORDER))
    svg.add(f'<path d="M42 70 l-6 6 l6 6" stroke="{TEXT}" stroke-width="1.8" fill="none" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')
    svg.add(text(194, 74, '小米账号授权', 16, TEXT, 600, 'middle'))
    svg.add(text(194, 92, 'account.xiaomi.com', 10, SUB, 400, 'middle'))
    svg.add(text(W - 36, 82, '⋯', 16, SUB, 400, 'middle'))

    # 网页模拟（地址条 + 页面）
    svg.add(rect(16, 106, W - 32, 34, 10, '#F4F8F8', BORDER))
    svg.add(f'<path d="M30 128 v-9 a5 5 0 0 1 10 0 v9" stroke="{ONLINE}" stroke-width="1.5" fill="none"/>')
    svg.add(rect(27, 126, 16, 12, 2.5, 'none', ONLINE, 1.5))
    svg.add(text(52, 128, 'account.xiaomi.com/pass/serviceLogin', 9, SUB))

    svg.add(rect(16, 148, W - 32, 470, 14, BG, BORDER))
    # 品牌区
    svg.add(rect(W / 2 - 26, 178, 52, 52, 14, PRIMARY))
    svg.add(text(W / 2, 212, 'M', 24, '#FFFFFF', 700, 'middle'))
    svg.add(text(W / 2, 258, '登录小米账号', 17, TEXT, 600, 'middle'))
    svg.add(text(W / 2, 280, '用于授权 MiHome 访问你的米家设备', 10.5, SUB, 400, 'middle'))

    # 输入框
    for i, (ph, filled) in enumerate([('邮箱 / 手机号 / 小米 ID', 'mo***@qq.com'),
                                     ('密码', '••••••••••')]):
        y = 306 + i * 58
        svg.add(rect(40, y, W - 80, 46, 12, BG, BORDER))
        svg.add(text(56, y + 22, ph, 9, SUB))
        svg.add(text(56, y + 37, filled, 13, TEXT, 400 if i == 0 else 600))

    svg.add(rect(40, 428, W - 80, 46, 23, PRIMARY))
    svg.add(text(W / 2, 456, '登录', 15, '#FFFFFF', 600, 'middle'))
    svg.add(text(40, 496, '忘记密码？', 10.5, PRIMARY_DARK))
    svg.add(text(W - 40, 496, '注册账号', 10.5, PRIMARY_DARK, 400, 'end'))
    svg.add(rect(40, 516, W - 80, 1, 0, BORDER))
    svg.add(text(W / 2, 544, 'App 不接触明文账号密码，只读取登录结果', 9.5, SUB, 400, 'middle'))
    svg.add(text(W / 2, 566, '由小米官方页面完成验证码与二次验证', 9.5, SUB, 400, 'middle'))
    svg.add(text(W / 2, 596, '隐私政策 · 服务协议', 9.5, PRIMARY_DARK, 400, 'middle'))

    # 状态条
    svg.add(rect(16, 630, W - 32, 44, 12, PRIMARY_SOFT, BORDER))
    svg.add(circle(38, 652, 8, 'none', PRIMARY, 2))
    svg.add(f'<path d="M34 652 l3 3 l6 -6" stroke="{PRIMARY}" stroke-width="1.8" fill="none" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')
    svg.add(text(54, 649, '已识别登录完成', 11.5, PRIMARY_DARK, 500))
    svg.add(text(54, 664, '正在提取令牌并写入 MiHome', 9.5, SUB))

    # 底部动作
    svg.add(rect(16, 692, (W - 32 - 10) / 2, 44, 22, BG, BORDER))
    svg.add(text(16 + (W - 42) / 4, 720, '提取令牌', 12.5, TEXT, 500, 'middle'))
    svg.add(rect(16 + (W - 32 - 10) / 2 + 10, 692, (W - 32 - 10) / 2, 44, 22, BG, BORDER))
    svg.add(text(16 + (W - 42) * 0.75 + 10, 720, '返回登录方式', 12.5, TEXT, 500, 'middle'))

    svg.add(text(W / 2, 768, '网页登录默认开启 · 也可切换扫码登录', 10, SUB, 400, 'middle'))
    svg.add(rect(0, H - 56, W, 56, 0, BG))
    svg.add(rect(0, H - 56, W, 1, 0, BORDER))
    svg.add(rect(W / 2 - 60, H - 26, 120, 5, 2.5, '#D6E2E2'))
    return svg


PAGES = {
    'home': (page_home, 'home.png', '首页 · 设备网格与概览'),
    'family': (page_family, 'family.png', '家庭选择浮层'),
    'mine': (page_mine, 'mine.png', '我的 · 桌面卡片入口'),
    'card-manager': (page_card_manager, 'card-manager.png', '桌面卡片管理中心'),
    'widgets': (page_widgets, 'widgets.png', '桌面卡片四种规格'),
    'login': (page_login, 'login.png', '网页授权登录'),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    wanted = sys.argv[1:] or list(PAGES.keys())
    for key in wanted:
        if key not in PAGES:
            print(f'跳过未知页面：{key}')
            continue
        builder, filename, _ = PAGES[key]
        svg = builder()
        raw = svg.render().encode('utf-8')
        out = os.path.join(OUT_DIR, filename)
        cairosvg.svg2png(bytestring=raw, write_to=out,
                         output_width=svg.w * 2, output_height=svg.h * 2)
        size = os.path.getsize(out)
        print(f'{filename:18s} {svg.w * 2}x{svg.h * 2}  {size // 1024} KB')
    print(f'输出目录：{OUT_DIR}')


if __name__ == '__main__':
    main()
