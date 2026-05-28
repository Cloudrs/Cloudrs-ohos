import { connection } from '@kit.NetworkKit';

export class NetworkStateUtil {
  static isWifiConnected(): boolean {
    try {
      if (!connection.hasDefaultNetSync()) {
        return false;
      }
      const netHandle = connection.getDefaultNetSync();
      const capabilities = connection.getNetCapabilitiesSync(netHandle);
      return (capabilities.bearerTypes ?? []).indexOf(connection.NetBearType.BEARER_WIFI) >= 0;
    } catch (_) {
      return false;
    }
  }
}
