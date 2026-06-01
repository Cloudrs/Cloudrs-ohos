import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import Constant from '../model/Constant';
import { CloudThemeToken } from '../model/CloudTheme';

const TAG: string = 'SystemAuthUtil';

class SystemAuthConfig {
  authTypes: userAuth.UserAuthType[];
  trustLevel: userAuth.AuthTrustLevel;

  constructor(authTypes: userAuth.UserAuthType[], trustLevel: userAuth.AuthTrustLevel) {
    this.authTypes = authTypes;
    this.trustLevel = trustLevel;
  }
}

export class SystemAuthResult {
  success: boolean;
  message: string;

  constructor(success: boolean, message: string = '') {
    this.success = success;
    this.message = message;
  }
}

export class SystemAuthUtil {
  static async authenticate(
    context: common.UIAbilityContext,
    title: string = '验证身份'
  ): Promise<SystemAuthResult> {
    const hasPermission = await SystemAuthUtil.ensureBiometricPermission(context);
    if (!hasPermission) {
      return new SystemAuthResult(false, '未授权系统认证权限');
    }

    const authConfig = SystemAuthUtil.getAvailableAuthConfig();
    if (!authConfig) {
      return new SystemAuthResult(false, '当前设备未录入可用的人脸或指纹');
    }

    return SystemAuthUtil.startAuth(authConfig, title);
  }

  private static async ensureBiometricPermission(context: common.UIAbilityContext): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.ACCESS_BIOMETRIC';
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, [permission]);
      if (!result.authResults || result.authResults.length <= CloudThemeToken.zero) {
        return true;
      }
      return result.authResults[Constant.FIRST_ARRAY_INDEX] === Constant.PERMISSION_AUTH_GRANTED;
    } catch (err) {
      const error = err as BusinessError;
      console.warn(TAG, `request biometric permission failed: ${error.code}, ${error.message}`);
      return true;
    }
  }

  private static getAvailableAuthConfig(): SystemAuthConfig | undefined {
    const trustLevels: userAuth.AuthTrustLevel[] = [
      userAuth.AuthTrustLevel.ATL3,
      userAuth.AuthTrustLevel.ATL2,
      userAuth.AuthTrustLevel.ATL1
    ];
    const candidateTypes: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.FACE,
      userAuth.UserAuthType.FINGERPRINT
    ];

    for (let levelIndex = 0; levelIndex < trustLevels.length; levelIndex++) {
      const trustLevel = trustLevels[levelIndex];
      const availableTypes: userAuth.UserAuthType[] = [];
      for (let typeIndex = 0; typeIndex < candidateTypes.length; typeIndex++) {
        const authType = candidateTypes[typeIndex];
        try {
          userAuth.getAvailableStatus(authType, trustLevel);
          availableTypes.push(authType);
        } catch (err) {
          const error = err as BusinessError;
          console.info(TAG, `auth type unavailable: ${authType}, level: ${trustLevel}, code: ${error.code}`);
        }
      }
      if (availableTypes.length > CloudThemeToken.zero) {
        return new SystemAuthConfig(availableTypes, trustLevel);
      }
    }
    return undefined;
  }

  private static startAuth(authConfig: SystemAuthConfig, title: string): Promise<SystemAuthResult> {
    return new Promise<SystemAuthResult>((resolve) => {
      let completed = false;
      let authInstance: userAuth.UserAuthInstance | undefined = undefined;
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          if (completed) {
            return;
          }
          completed = true;
          try {
            authInstance?.off('result', callback);
          } catch (err) {
            const error = err as BusinessError;
            console.warn(TAG, `off auth callback failed: ${error.code}, ${error.message}`);
          }
          resolve(new SystemAuthResult(
            result.result === userAuth.UserAuthResultCode.SUCCESS,
            SystemAuthUtil.getResultMessage(result.result)
          ));
        }
      };

      try {
        authInstance = userAuth.getUserAuthInstance({
          challenge: SystemAuthUtil.createChallenge(),
          authType: authConfig.authTypes,
          authTrustLevel: authConfig.trustLevel
        }, {
          title,
          navigationButtonText: '取消'
        });
        authInstance.on('result', callback);
        authInstance.start();
      } catch (err) {
        const error = err as BusinessError;
        console.error(TAG, `system auth start failed: ${error.code}, ${error.message}`);
        resolve(new SystemAuthResult(false, SystemAuthUtil.getErrorMessage(error)));
      }
    });
  }

  private static createChallenge(): Uint8Array {
    const challenge = new Uint8Array(16);
    for (let index = 0; index < challenge.length; index++) {
      challenge[index] = Math.floor(Math.random() * 256);
    }
    return challenge;
  }

  private static getResultMessage(resultCode: number): string {
    switch (resultCode) {
      case userAuth.UserAuthResultCode.SUCCESS:
        return '认证成功';
      case userAuth.UserAuthResultCode.CANCELED:
      case userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET:
        return '已取消系统认证';
      case userAuth.UserAuthResultCode.TIMEOUT:
        return '系统认证超时';
      case userAuth.UserAuthResultCode.NOT_ENROLLED:
        return '当前设备未录入人脸或指纹';
      case userAuth.UserAuthResultCode.LOCKED:
        return '系统认证已锁定，请稍后再试';
      case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
        return '当前设备不支持人脸或指纹认证';
      case userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT:
        return '当前系统认证安全等级不支持';
      default:
        return '系统认证失败';
    }
  }

  private static getErrorMessage(error: BusinessError): string {
    switch (error.code) {
      case 201:
        return '未授权系统认证权限';
      case userAuth.UserAuthResultCode.NOT_ENROLLED:
        return '当前设备未录入人脸或指纹';
      case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
        return '当前设备不支持人脸或指纹认证';
      case userAuth.UserAuthResultCode.LOCKED:
        return '系统认证已锁定，请稍后再试';
      default:
        return error.message && error.message.length > CloudThemeToken.zero ? error.message : '系统认证失败';
    }
  }
}
