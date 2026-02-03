import {
  AbilityAware,
  AbilityPluginBinding,
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
} from '@ohos/flutter_ohos';
import {
  IQQOpenApi,
  QQOpenApiFactory,
  ApiCallback,
  AuthResponse,
  ShareData,
  ShareResult,
} from '@tencent/qq-open-sdk'
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

/** 分享到空间 shareJson 结构 */
class ShareJsonQZone {
  title: string = "";
  summary: string = "";
  targetUrl: string = "";
  imageUrls: string[] = [];
}

/** ark 图文 shareJson 结构 */
class ShareJsonArk {
  msg_style: number = 0;
  title: string = "";
  summary: string = "";
  brief: string = "";
  url: string = "";
  picture_url: string = "";
}

/** ark 大图 shareJson 结构 */
class ShareJsonArkImage {
  msg_style: number = 6;
  share_uris: string[] = [];
}

enum TencentRetCode {
  RET_SUCCESS = 0,
  RET_FAILED = 1,
  RET_COMMON = -1,
  RET_CANCEL = -2
}

/** HarmonyOS ShareResult.resultType */
const SHARE_RESULT_SUCCESS = 1;
const SHARE_RESULT_CANCEL = 2;
const SHARE_RESULT_ERROR = 3;

/** HarmonyOS share type: ark 图文/大图 */
const SHARE_TYPE_ARK = 2;
/** HarmonyOS share type: 分享到空间 */
const SHARE_TYPE_QZONE = 3009;

const KEY_RET_CODE = "ret";
const KEY_RET_MSG = "msg";

/** Base64 编码表 */
const BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function getByte(data: Uint8Array, index: number): number {
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  return view.getUint8(index);
}

function base64Encode(data: Uint8Array): string {
  let result = "";
  for (let i = 0; i < data.length; i += 3) {
    const b0: number = getByte(data, i);
    const b1: number = i + 1 < data.length ? getByte(data, i + 1) : 0;
    const b2: number = i + 2 < data.length ? getByte(data, i + 2) : 0;
    result += BASE64_CHARS.charAt(b0 >> 2);
    result += BASE64_CHARS.charAt(((b0 & 3) << 4) | (b1 >> 4));
    result += i + 1 < data.length ? BASE64_CHARS.charAt(((b1 & 15) << 2) | (b2 >> 6)) : "=";
    result += i + 2 < data.length ? BASE64_CHARS.charAt(b2 & 63) : "=";
  }
  return result;
}

/** TencentKitPlugin **/
export default class TencentKitPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware, NewWantListener {
  private channel: MethodChannel | null = null;
  private binding: AbilityPluginBinding | null = null;
  private tencent: IQQOpenApi | null = null;
  private modeServerSide: boolean = false;
  private shareAppId: number = 0;
  private shareAppKey: string | null = null;

  getUniqueClassName(): string {
    return "TencentKitPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "v7lin.github.io/tencent_kit");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.binding = binding;
    binding.addOnNewWantListener(this);
  }

  onDetachedFromAbility(): void {
    this.binding = null;
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    this.tencent?.handleResult(want)
  }

  authListener: ApiCallback<AuthResponse> = {
    onComplete: (response: AuthResponse): void => {
      const resp: Map<string, Any> = new Map();
      try {
        if (response.ret == TencentRetCode.RET_SUCCESS) {
          // 服务端模式时, access_token 设置为为 authCode, 当前 SDK 不支持客户端模式(因此 null)
          const accessToken: string | null = this.modeServerSide ? response.authCode : null;
          resp.set(KEY_RET_CODE, TencentRetCode.RET_SUCCESS);
          resp.set("openid", response.openId);
          resp.set("access_token", accessToken);
          resp.set("expires_in", response.expiresIn);
          resp.set("create_at", response.authTime);
        } else {
          resp.set("ret", TencentRetCode.RET_COMMON);
        }
      } catch (e) {
        resp.set(KEY_RET_CODE, TencentRetCode.RET_COMMON);
        resp.set(KEY_RET_MSG, `${e}`);
      }
      this.channel?.invokeMethod("onLoginResp", resp);
    },
    onError: (msg: string | null): void => {
      const resp: Map<string, Any> = new Map();
      resp.set(KEY_RET_CODE, TencentRetCode.RET_FAILED);
      resp.set(KEY_RET_MSG, msg);
      this.channel?.invokeMethod("onLoginResp", resp);
    },
    onCancel: (msg: string | null): void => {
      const resp: Map<string, Any> = new Map();
      resp.set(KEY_RET_CODE, TencentRetCode.RET_CANCEL);
      resp.set(KEY_RET_MSG, msg);
      this.channel?.invokeMethod("onLoginResp", resp);
    }
  }

  private invokeShareResp(resultType: number, message: string | null, detail: string | null): void {
    const resp: Map<string, Any> = new Map();
    if (resultType === SHARE_RESULT_SUCCESS) {
      resp.set(KEY_RET_CODE, TencentRetCode.RET_SUCCESS);
    } else if (resultType === SHARE_RESULT_CANCEL) {
      resp.set(KEY_RET_CODE, TencentRetCode.RET_CANCEL);
    } else {
      resp.set(KEY_RET_CODE, TencentRetCode.RET_COMMON);
    }
    if (message != null) {
      resp.set(KEY_RET_MSG, message);
    }
    if (detail != null) {
      resp.set("detail", detail);
    }
    this.channel?.invokeMethod("onShareResp", resp);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "setIsPermissionGranted":
        // 当前 SDK 不支持此方法，暂时返回 null
        result.success(null);
        break;
      case "registerApp":
        this.registerApp(call, result);
        break;
      case "isQQInstalled":
        result.success(this.tencent != null && this.tencent.isQQInstalled());
        break;
      case "isTIMInstalled":
        // TIM 并未适配 harmonyOS, 暂时返回 false
        result.success(false);
        break;
      case "login":
        this.login(call, result);
        break;
      case "loginServerSide":
        this.loginServerSide(call, result);
        break;
      case "shareMood":
        this.shareMood(call, result);
        break;
      case "shareText":
        this.shareText(call, result);
        break;
      case "shareImage":
        this.shareImage(call, result);
        break;
      case "shareMusic":
        this.shareMusic(call, result);
        break;
      case "shareWebpage":
        this.shareWebpage(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  /** 按 QQ 互联分享签名方案计算 shareJsonSign：HMAC-SHA1(原文, appKey) 再 Base64 */
  private async buildShareDataAsync(shareJsonStr: string): Promise<ShareData> {
    if (this.shareAppKey == null || this.shareAppKey.length === 0) {
      throw new Error("appKey not set, call registerApp with appKey for share");
    }
    const tsSec = Math.floor(Date.now() / 1000);
    const nonce = Math.floor(Math.random() * 999999999) + 1;
    const srcStr = "POSTconnect.qq.com/share?appid=" + this.shareAppId + "&nonce=" + nonce + "&ts=" + tsSec + "&" + shareJsonStr;
    const keyData = new Uint8Array(buffer.from(this.shareAppKey, 'utf-8').buffer);
    const symKeyBlob: cryptoFramework.DataBlob = { data: keyData };
    const symKeyGen = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = await symKeyGen.convertKey(symKeyBlob);
    const mac = cryptoFramework.createMac('SHA1');
    await mac.init(symKey);
    await mac.update({ data: new Uint8Array(buffer.from(srcStr, 'utf-8').buffer) });
    const macResult = await mac.doFinal();
    const shareJsonSign = base64Encode(macResult.data);
    const data = new ShareData();
    data.shareJson = shareJsonStr;
    data.timestamp = tsSec;
    data.nonce = nonce;
    data.shareJsonSign = shareJsonSign;
    return data;
  }

  private doShare(type: number, shareData: ShareData, openId?: string): void {
    if (this.tencent == null) {
      this.invokeShareResp(SHARE_RESULT_ERROR, "tencent not initialized", null);
      return;
    }
    this.tencent.share(type, shareData, openId)
      .then((shareResult: ShareResult) => {
        this.invokeShareResp(shareResult.resultType, shareResult.message ?? null, shareResult.detail ?? null);
      })
      .catch((err: Error) => {
        this.invokeShareResp(SHARE_RESULT_ERROR, err.message, null);
      });
  }

  private shareMood(call: MethodCall, result: MethodResult): void {
    const scene: number = call.argument("scene") as number;
    if (scene !== 1) {
      result.success(null);
      return;
    }
    const summary: string | undefined = call.argument("summary") as string | undefined;
    const imageUris: string[] | undefined = call.argument("imageUris") as string[] | undefined;
    const j = new ShareJsonQZone();
    j.title = summary ?? "";
    j.summary = summary ?? "";
    j.targetUrl = "https://www.qq.com";
    j.imageUrls = imageUris ?? [];
    this.buildShareDataAsync(JSON.stringify(j)).then((shareData: ShareData) => {
      this.doShare(SHARE_TYPE_QZONE, shareData);
      result.success(null);
    }).catch((err: Error) => {
      this.invokeShareResp(SHARE_RESULT_ERROR, err.message, null);
      result.success(null);
    });
  }

  private shareText(call: MethodCall, result: MethodResult): void {
    // HarmonyOS SDK 未提供纯文本分享接口，与 Android 系统 Intent 行为不一致，直接返回
    result.success(null);
  }

  private shareImage(call: MethodCall, result: MethodResult): void {
    const imageUri: string = call.argument("imageUri") as string;
    const j = new ShareJsonArkImage();
    j.msg_style = 6;
    j.share_uris = [imageUri];
    this.buildShareDataAsync(JSON.stringify(j)).then((shareData: ShareData) => {
      this.doShare(SHARE_TYPE_ARK, shareData);
      result.success(null);
    }).catch((err: Error) => {
      this.invokeShareResp(SHARE_RESULT_ERROR, err.message, null);
      result.success(null);
    });
  }

  private shareMusic(call: MethodCall, result: MethodResult): void {
    const title: string = call.argument("title") as string;
    const summary: string | undefined = call.argument("summary") as string | undefined;
    const imageUri: string | undefined = call.argument("imageUri") as string | undefined;
    const targetUrl: string = call.argument("targetUrl") as string;
    const j = new ShareJsonArk();
    j.msg_style = 0;
    j.title = title;
    j.summary = summary ?? "";
    j.brief = "互联分享";
    j.url = targetUrl;
    j.picture_url = imageUri ?? "";
    this.buildShareDataAsync(JSON.stringify(j)).then((shareData: ShareData) => {
      this.doShare(SHARE_TYPE_ARK, shareData);
      result.success(null);
    }).catch((err: Error) => {
      this.invokeShareResp(SHARE_RESULT_ERROR, err.message, null);
      result.success(null);
    });
  }

  private shareWebpage(call: MethodCall, result: MethodResult): void {
    const scene: number = call.argument("scene") as number;
    const title: string = call.argument("title") as string;
    const summary: string | undefined = call.argument("summary") as string | undefined;
    const imageUri: string | undefined = call.argument("imageUri") as string | undefined;
    const targetUrl: string = call.argument("targetUrl") as string;
    const onSignDone = (shareData: ShareData, type: number): void => {
      this.doShare(type, shareData);
      result.success(null);
    };
    const onSignErr = (err: Error): void => {
      this.invokeShareResp(SHARE_RESULT_ERROR, err.message, null);
      result.success(null);
    };
    if (scene === 0) {
      const j = new ShareJsonArk();
      j.msg_style = 0;
      j.title = title;
      j.summary = summary ?? "";
      j.brief = "";
      j.url = targetUrl;
      j.picture_url = imageUri ?? "";
      this.buildShareDataAsync(JSON.stringify(j)).then((shareData: ShareData) => onSignDone(shareData, SHARE_TYPE_ARK)).catch(onSignErr);
    } else if (scene === 1) {
      const imageUrls: string[] = imageUri != null && imageUri.length > 0 ? [imageUri] : [];
      const j = new ShareJsonQZone();
      j.title = title;
      j.summary = summary ?? "";
      j.targetUrl = targetUrl;
      j.imageUrls = imageUrls;
      this.buildShareDataAsync(JSON.stringify(j)).then((shareData: ShareData) => onSignDone(shareData, SHARE_TYPE_QZONE)).catch(onSignErr);
    } else {
      result.success(null);
    }
  }

  private registerApp(call: MethodCall, result: MethodResult) {
    const appId: number = parseInt(call.argument("appId") as string);
    this.shareAppId = appId;
    this.shareAppKey = call.argument("appKey") as string;
    this.tencent = QQOpenApiFactory.createApi(appId, {
      forceEnableWeb: false,
    });
    result.success(null);
  }

  private login(call: MethodCall, result: MethodResult) {
    // this.modeServerSide = false; // 客户端授权
    // 当前 SDK 仅支持 ServerSide 授权，暂时不处理
    result.success(null);
  }

  private loginServerSide(call: MethodCall, result: MethodResult) {
    this.modeServerSide = true; // 服务端授权
    const scope: string = call.argument("scope");
    const qrcode: boolean = call.argument("qrcode");
    this.tencent?.login({
      scope: scope,
      useQrCode: qrcode,
      forceWebLogin: qrcode || !this.tencent!.isQQInstalled(), // H5 授权, 二维码登录或 QQ 未安装时强制启用
      networkTimeout: 0, // 不限制, 由 SDK 自行决定
    }, this.authListener);
    result.success(null);
  }
}