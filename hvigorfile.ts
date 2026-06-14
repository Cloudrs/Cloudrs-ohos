import { appTasks, OhosAppContext, OhosPluginId, AppJson } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 仅 release 构建时自动生成 versionCode,格式为 YYMMdd + index。
 * - 日期(YYMMdd)在构建时自动取当天。
 * - index 为手动维护的"当日序号",默认 1;同一天需要发布多个版本时改大(2、3…)。
 *   例:2026-06-14 当天 index=1 -> 2606141。
 *
 * YYMMdd 天然递增,保证 versionCode 单调递增(满足华为应用市场上架要求)。
 * 由于 versionCode 仅由「当天日期 + 固定 index」决定,取值是幂等的:一次构建的
 * 多轮评估、以及 daemon 复用进程的多次构建都会算出并写入相同的值,无需额外去重。
 *
 * 生成值写回 AppScope/app.json5(让其反映真实发布号)并使能到本次构建,关于页通过
 * BuildProfile.VERSION_CODE 自动显示。debug 构建不做任何改动,关于页沿用 app.json5 现值。
 *
 * 注意:app.json5 的 versionCode 由本脚本自动生成,无需手动修改;要调整当日序号请改
 *      下方的 VERSION_INDEX。versionCode 是 32 位整数(上限 ~21.4 亿),YYMMdd 占 6 位,
 *      index 建议保持 1~3 位。
 */
const VERSION_INDEX = 1;

hvigor.nodesEvaluated(() => {
  const appContext = hvigor.getRootNode().getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  if (appContext.getBuildMode() !== 'release') {
    return;
  }

  const now = new Date();
  const yymmdd = `${String(now.getFullYear()).slice(2)}`
    + `${String(now.getMonth() + 1).padStart(2, '0')}`
    + `${String(now.getDate()).padStart(2, '0')}`;
  const newCode = Number(`${yymmdd}${VERSION_INDEX}`);

  // 使能到本次构建:GenerateBuildProfile 读取该值生成 BuildProfile.VERSION_CODE
  const appJson: AppJson.AppOptObj = appContext.getAppJsonOpt();
  appJson.app.versionCode = newCode;
  appContext.setAppJsonOpt(appJson);

  // 写回磁盘:仅替换数字,保留 app.json5 原有格式(同日同 index 为幂等写入)
  const appJsonPath = path.resolve(appContext.getProjectPath(), 'AppScope', 'app.json5');
  try {
    const text = fs.readFileSync(appJsonPath, 'utf-8');
    const replaced = text.replace(/("versionCode"\s*:\s*)\d+/, `$1${newCode}`);
    if (replaced !== text) {
      fs.writeFileSync(appJsonPath, replaced, 'utf-8');
    }
  } catch (e) {
    console.warn(`[versionCode] write back app.json5 failed: ${String(e)}`);
  }

  console.log(`[versionCode] release build -> ${newCode}`);
});

export default {
  system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []        /* Custom plugin to extend the functionality of Hvigor. */
}
