/*
 * 网页登录（ArkWeb 承载小米官方登录页）。
 *
 * 本轮关键修复：
 * 1. 顶部关闭按钮增加状态栏安全高度，不再与状态栏重合；同时提供底部返回按钮。
 * 2. 注入 __miSnapshot，定时读取页面 URL / 标题 / 正文 / document.cookie / extension-pragma，
 *    即使小米跳到只显示 “ok” 的空白回调页，也能自动识别登录完成并提取令牌。
 * 3. “提取令牌”始终可点；失败时给出明确提示，不会永久卡在白屏。
 */

import { webview } from '@kit.ArkWeb';
import { HwColor, HwRadius, HwSpace } from '../utils/DesignTokens';

/** document-start 注入：保留 pragma，并提供页面快照给 ArkTS 轮询 */
const PRAGMA_HOOK: string = '(function(){'
  + 'if(window.__miPragma===undefined){window.__miPragma="";}'
  + 'function keep(h){try{if(h){window.__miPragma=h;}}catch(e){}}'
  + 'try{var S=XMLHttpRequest.prototype.send;'
  + 'XMLHttpRequest.prototype.send=function(){var self=this;'
  + 'this.addEventListener("readystatechange",function(){'
  + 'if(self.readyState===4){try{keep(self.getResponseHeader("extension-pragma"));}catch(e){}}'
  + '});return S.apply(this,arguments);};}catch(e){}'
  + 'try{var F=window.fetch;if(F){window.fetch=function(){'
  + 'return F.apply(this,arguments).then(function(r){'
  + 'try{keep(r.headers.get("extension-pragma"));}catch(e){}return r;});};}}catch(e){}'
  + 'var N=String.fromCharCode(10);'
  + 'window.__miSnapshot=function(){'
  + 'var u="";var t="";var b="";var c="";'
  + 'try{u=location.href||"";}catch(e){}'
  + 'try{t=document.title||"";}catch(e){}'
  + 'try{b=(document.body&&document.body.innerText||"").substring(0,1500);}catch(e){}'
  + 'try{c=document.cookie||"";}catch(e){}'
  + 'return "URL="+u+N+"TITLE="+t+N+"TEXT="+b+N+"COOKIE="+c+N+"PRAGMA="+(window.__miPragma||"");'
  + '};'
+ '})();';

const STS_HOST: string = 'sts.api.io.mi.com';
const LOGIN_END_PATH: string = 'serviceLoginAuth2/end';

@Component
export struct WebLoginView {
  @Prop initialUrl: string = '';
  @State progress: number = 0;
  @State status: string = '正在加载小米官方登录页…';
  @State harvesting: boolean = false;
  @State lastUrl: string = '';
  @Prop @Watch('onHintChanged') hint: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  controller: webview.WebviewController = new webview.WebviewController();
  onHarvest: (cookies: string, pragma: string, finalUrl: string) => void =
    (cookies: string, pragma: string, finalUrl: string): void => {};
  onClose: () => void = (): void => {};

  private probeTimer: number = -1;
  private watchdogTimer: number = -1;
  private reported: boolean = false;
  private pendingAuthUrl: string = '';

  private onHintChanged(): void {
    if (this.hint.length > 0) {
      this.harvesting = false;
      this.reported = false;
      this.status = this.hint;
    }
  }

  aboutToDisappear(): void {
    this.clearProbe();
  }

  private clearProbe(): void {
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
    if (this.watchdogTimer >= 0) {
      clearTimeout(this.watchdogTimer);
      this.watchdogTimer = -1;
    }
  }

  private scheduleProbe(delay: number): void {
    if (this.reported || this.harvesting) {
      return;
    }
    this.clearProbe();
    this.probeTimer = setTimeout((): void => {
      this.probeTimer = -1;
      this.probeAfterLogin();
    }, delay);
  }

  private hooks(): Array<ScriptItem> {
    const item: ScriptItem = { script: PRAGMA_HOOK, scriptRules: ['*'] };
    return [item];
  }

  /** ssecurity / userId 在 account 域，serviceToken 在 sts / api 域 */
  private cookieUrls(): Array<string> {
    return [
      'https://account.xiaomi.com',
      'https://account.xiaomi.com/pass/serviceLogin',
      'https://sts.api.io.mi.com',
      'https://sts.api.io.mi.com/sts',
      'https://api.io.mi.com',
      'https://www.xiaomi.com',
      'https://xiaomi.com'
    ];
  }

  private readCookies(): string {
    const parts: Array<string> = [];
    const urls: Array<string> = this.cookieUrls();
    for (let i = 0; i < urls.length; i++) {
      try {
        const c: string = webview.WebCookieManager.fetchCookieSync(urls[i]);
        if (c.length > 0) {
          parts.push(c);
        }
      } catch (err) {
        // 单域读取失败不影响其它域
      }
    }
    return parts.join('; ');
  }

  private isAuthUrl(url: string): boolean {
    return url.indexOf(STS_HOST) >= 0 || url.indexOf(LOGIN_END_PATH) >= 0
      || url.indexOf('ssecurity=') >= 0 || url.indexOf('serviceToken=') >= 0;
  }

  /** 小米成功页正文常见 "ok" / "success" / "登录成功" */
  private looksFinished(text: string): boolean {
    const lower: string = text.trim().toLowerCase();
    return lower === 'ok' || lower.indexOf('success') >= 0
      || text.indexOf('成功') >= 0 || text.indexOf('已登录') >= 0;
  }

  private currentUrl(): string {
    try {
      const url: string = this.controller.getUrl();
      if (url.length > 0 && url !== 'about:blank') {
        return url;
      }
    } catch (err) {
      // 控制器尚未绑定
    }
    if (this.lastUrl.length > 0) {
      return this.lastUrl;
    }
    return this.pendingAuthUrl;
  }

  private async readPragma(): Promise<string> {
    try {
      return await this.controller.runJavaScript('window.__miPragma || ""');
    } catch (err) {
      return '';
    }
  }

  private async readSnapshot(): Promise<string> {
    try {
      const value: string = await this.controller.runJavaScript(
        'window.__miSnapshot ? window.__miSnapshot() : ""');
      return value === undefined ? '' : value;
    } catch (err) {
      return '';
    }
  }

  private snapshotField(snap: string, key: string): string {
    if (snap.length === 0) {
      return '';
    }
    const marker: string = key + '=';
    const lines: Array<string> = snap.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.indexOf(marker) === 0) {
        return line.substring(marker.length);
      }
    }
    return '';
  }

  private deliver(raw: string, pragma: string, finalUrl: string): void {
    if (this.reported || this.harvesting) {
      return;
    }
    this.clearProbe();
    this.reported = true;
    this.harvesting = true;
    this.status = '正在提取登录令牌…';
    //  watchdog：父层若长时间未回传结果，自动解锁界面，避免“提取中”永久卡死
    if (this.watchdogTimer >= 0) {
      clearTimeout(this.watchdogTimer);
    }
    this.watchdogTimer = setTimeout((): void => {
      this.watchdogTimer = -1;
      if (this.harvesting) {
        this.harvesting = false;
        this.reported = false;
        this.status = '令牌提取超时，请重新点「提取令牌」或返回登录方式';
      }
    }, 6000);
    this.onHarvest(raw, pragma, finalUrl);
  }

  /** 登录后定时兜底：哪怕页面只剩 "ok"，也靠快照 + Cookie 完成提取 */
  private async probeAfterLogin(): Promise<void> {
    if (this.reported || this.harvesting) {
      return;
    }
    const snap: string = await this.readSnapshot();
    const snapUrl: string = this.snapshotField(snap, 'URL');
    const snapCookie: string = this.snapshotField(snap, 'COOKIE');
    const snapPragma: string = this.snapshotField(snap, 'PRAGMA');
    const snapText: string = this.snapshotField(snap, 'TEXT');

    let finalUrl: string = this.currentUrl();
    if (finalUrl.length === 0 || finalUrl === 'about:blank') {
      finalUrl = snapUrl;
    }
    const raw: string = this.readCookies()
      + (snapCookie.length > 0 ? '; ' + snapCookie : '');
    const directPragma: string = await this.readPragma();
    const pragma: string = directPragma.length > 0 ? directPragma : snapPragma;

    const hasToken: boolean = raw.indexOf('serviceToken=') >= 0
      || finalUrl.indexOf('serviceToken=') >= 0 || snap.indexOf('serviceToken=') >= 0;
    const hasSec: boolean = finalUrl.indexOf('ssecurity=') >= 0
      || pragma.indexOf('ssecurity') >= 0 || snap.indexOf('ssecurity') >= 0;
    const pageOk: boolean = this.isAuthUrl(finalUrl) || this.isAuthUrl(snapUrl)
      || this.looksFinished(snapText);

    if (hasToken && hasSec) {
      this.deliver(raw, pragma, finalUrl);
      return;
    }
    if (hasToken && pageOk) {
      this.deliver(raw, pragma, finalUrl);
      return;
    }
    if (pageOk && snapCookie.indexOf('=') > 0) {
      // 页面显示已登录但 Cookie 尚未同步到 ArkWeb CookieManager，仍交给转换器判断
      this.deliver(raw, pragma, finalUrl);
      return;
    }
    this.status = '等待登录完成…若页面显示 ok 仍不动，请点右下角「提取令牌」';
    this.scheduleProbe(500);
  }

  /** auto=true 时只在检测到登录完成迹象后自动上报；false 为用户手动提取 */
  private async report(auto: boolean): Promise<void> {
    if (this.reported || this.harvesting) {
      return;
    }
    const snap: string = await this.readSnapshot();
    const snapCookie: string = this.snapshotField(snap, 'COOKIE');
    const snapPragma: string = this.snapshotField(snap, 'PRAGMA');
    const snapText: string = this.snapshotField(snap, 'TEXT');
    let finalUrl: string = this.currentUrl();
    const snapUrl: string = this.snapshotField(snap, 'URL');
    if (finalUrl.length === 0 || finalUrl === 'about:blank') {
      finalUrl = snapUrl;
    }
    const raw: string = this.readCookies()
      + (snapCookie.length > 0 ? '; ' + snapCookie : '');
    const directPragma: string = await this.readPragma();
    const pragma: string = directPragma.length > 0 ? directPragma : snapPragma;

    if (raw.length === 0) {
      this.status = '还没读到登录 Cookie，请先在页面内完成账号验证';
      return;
    }
    if (auto) {
      const hasToken: boolean = raw.indexOf('serviceToken=') >= 0
        || finalUrl.indexOf('serviceToken=') >= 0 || snap.indexOf('serviceToken=') >= 0;
      const hasSec: boolean = finalUrl.indexOf('ssecurity=') >= 0
        || pragma.indexOf('ssecurity') >= 0 || snap.indexOf('ssecurity') >= 0;
      const pageOk: boolean = this.isAuthUrl(finalUrl) || this.isAuthUrl(snapUrl)
        || this.looksFinished(snapText);
      if (!hasToken || (!hasSec && !pageOk)) {
        this.status = '页面仍在跳转，完成后点「提取令牌」；若已显示 ok 也可直接点';
        this.scheduleProbe(500);
        return;
      }
    }
    this.deliver(raw, pragma, finalUrl);
  }

  private close(): void {
    this.clearProbe();
    this.onClose();
  }

  build() {
    // 关键：ArkWeb 是原生 surface，控制条必须作为同层覆盖层放在 Web 之上。
    // 覆盖容器用 Transparent，让空白区域继续透传给网页；按钮自身正常接收点击。
    Stack() {
      Web({ src: this.initialUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .backgroundColor('#FFFFFF')
        .domStorageAccess(true)
        .databaseAccess(true)
        .fileAccess(false)
        .geolocationAccess(false)
        .mixedMode(MixedMode.All)
        .javaScriptOnDocumentStart(this.hooks())
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          try {
            const url: string = event.data.getRequestUrl();
            if (url.length > 0) {
              this.pendingAuthUrl = url;
              this.lastUrl = url;
              if (this.isAuthUrl(url)) {
                this.status = '登录完成，正在提取令牌…';
                this.scheduleProbe(250);
              }
            }
          } catch (err) {
            // 拦截失败不阻断页面
          }
          return false;
        })
        .onProgressChange((event: OnProgressChangeEvent): void => {
          this.progress = event.newProgress;
          if (event.newProgress >= 100 && !this.reported) {
            this.scheduleProbe(300);
          }
        })
        .onPageEnd((event: OnPageEndEvent): void => {
          this.lastUrl = event.url;
          if (this.isAuthUrl(event.url)) {
            this.status = '登录完成，正在提取令牌…';
            this.scheduleProbe(200);
          } else {
            this.status = '页面已加载；验证完成后若停留在 ok 页，请点「提取令牌」';
            this.scheduleProbe(400);
          }
        })

      if (this.progress < 100) {
        Row() {
          Text('加载中 ' + this.progress.toString() + '%')
            .fontSize(11).fontColor(HwColor.textSecondary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(HwRadius.card)
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E3ECEE' })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(5)
      }

      Column() {
        Column() {
          // 状态栏安全高度：关闭按钮绝不再与状态栏重合
          Row()
            .width('100%')
            .height(Math.max(this.statusBarHeight, 32))
            .backgroundColor('#FFFFFF')

          Row() {
            Column({ space: 3 }) {
              Text('网页登录')
                .fontSize(16).fontWeight(FontWeight.Medium).fontColor(HwColor.textPrimary)
              Text('由小米官方页面完成验证，不经过本应用')
                .fontSize(11).fontColor(HwColor.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('关闭')
              .fontSize(14)
              .fontColor(HwColor.primary)
              .height(36)
              .padding({ left: 16, right: 16 })
              .borderRadius(HwRadius.pill)
              .backgroundColor('#FFFFFF')
              .border({ width: 1, color: '#E3ECEE' })
              .shadow({ radius: 12, color: '#123E9AA6', offsetY: 2 })
              .onClick((): void => {
                this.close();
              })
          }
          .width('100%')
          .height(58)
          .padding({ left: HwSpace.xl, right: HwSpace.xl })
          .backgroundColor('#FFFFFF')
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        Blank()

        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Text(this.hint.length > 0 ? this.hint : this.status)
              .fontSize(11)
              .fontColor(this.hint.length > 0 ? HwColor.danger : HwColor.textSecondary)
              .layoutWeight(1)
              .maxLines(3)

            Button(this.harvesting ? '提取中…' : '提取令牌')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .height(36)
              .padding({ left: 16, right: 16 })
              .borderRadius(HwRadius.pill)
              .backgroundColor(HwColor.primary)
              .enabled(!this.harvesting)
              .onClick((): void => {
                this.report(false);
              })
          }
          .width('100%')

          Button('返回登录方式')
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .height(32)
            .width('100%')
            .borderRadius(HwRadius.control)
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E3ECEE' })
            .shadow({ radius: 10, color: '#123E9AA6', offsetY: 2 })
            .onClick((): void => {
              this.close();
            })
        }
        .width('100%')
        .padding({
          left: HwSpace.xl,
          right: HwSpace.xl,
          top: 10,
          bottom: Math.max(this.statusBarHeight, 16)
        })
        .backgroundColor('#FFFFFF')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
