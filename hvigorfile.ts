import { appTasks, OhosAppContext, OhosHapContext, OhosPluginId, AppJson } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

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

/**
 * 把构建时的 git 短哈希注入 BuildProfile.GIT_COMMIT，关于页点一下版本号就能看到。
 *
 * 用途是拿到一个上架的包能回溯它从哪个 commit 构建。工作区有未提交改动时追加
 * -dirty：带这个后缀的包说明发的不是一个干净的 commit，正是最该警惕的情况。
 *
 * 不落任何文件到仓库，所以没有 git 噪音。取不到 git 信息（比如从压缩包解出来构建）
 * 就保持 build-profile.json5 里的 unknown，不让构建失败。
 */
function resolveGitCommit(projectPath: string): string | undefined {
  const run = (cmd: string): string =>
    execSync(cmd, { cwd: projectPath, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  try {
    const hash = run('git rev-parse --short HEAD');
    if (!hash) {
      return undefined;
    }
    const dirty = run('git status --porcelain').length > 0;
    return dirty ? `${hash}-dirty` : hash;
  } catch (e) {
    console.warn(`[gitCommit] skipped: ${String(e)}`);
    return undefined;
  }
}

hvigor.nodesEvaluated(() => {
  const entryNode = hvigor.getNodeByName('entry');
  if (entryNode) {
    const hapContext = entryNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
    const commit = resolveGitCommit(hvigor.getRootNode().getNodePath());
    if (hapContext && commit) {
      const profile = hapContext.getBuildProfileOpt();
      profile['buildOption'] = profile['buildOption'] ?? {};
      profile['buildOption']['arkOptions'] = profile['buildOption']['arkOptions'] ?? {};
      profile['buildOption']['arkOptions']['buildProfileFields'] = {
        ...profile['buildOption']['arkOptions']['buildProfileFields'],
        GIT_COMMIT: commit
      };
      hapContext.setBuildProfileOpt(profile);
      console.log(`[gitCommit] ${commit}`);
    }
  }
});

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
