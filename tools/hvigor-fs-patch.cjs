'use strict';
/*
 * HarmonyOS hvigor build workaround for sandboxed / restricted environments.
 *
 * Problem: the sandbox blocks copy_file_range(2). ets-loader calls
 * fs.copyFileSync() to cache source maps, which then fails with
 *   EPERM: operation not permitted, copyfile ... sourceMaps.map -> sourceMaps.json
 * and hvigor reports "Error Code: 00308018 Unknown Error".
 *
 * Fix: fall back to a plain readFileSync + writeFileSync copy on the
 * filesystem errors that indicate an unsupported copy_file_range.
 *
 * Usage (see README.md section "命令行真实构建"):
 *   export NODE_OPTIONS="--jitless --require=$(pwd)/tools/hvigor-fs-patch.cjs"
 *
 * This file is intentionally dependency-free and only patches the sync API.
 */
const fs = require('fs');
const path = require('path');

const origCopyFileSync = fs.copyFileSync;

fs.copyFileSync = function copyFileSyncFallback(from, to, mode) {
  try {
    return origCopyFileSync.call(fs, from, to, mode);
  } catch (err) {
    const code = err && err.code;
    if (code === 'EPERM' || code === 'EXDEV' || code === 'ENOSYS' ||
        code === 'EINVAL' || code === 'EOPNOTSUPP') {
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.writeFileSync(to, fs.readFileSync(from));
      return undefined;
    }
    throw err;
  }
};
