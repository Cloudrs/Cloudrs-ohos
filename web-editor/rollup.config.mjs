import { nodeResolve } from '@rollup/plugin-node-resolve'
import terser from '@rollup/plugin-terser'

// 产物直接落到 rawfile 下并提交入库，日常构建不需要 Node 工具链。
// 同 entry/libs 里预编译 .so 的做法。
export default {
  input: 'src/main.js',
  output: {
    file: '../entry/src/main/resources/rawfile/editor/editor.js',
    format: 'iife',
    name: 'CloudrsEditor'
  },
  plugins: [nodeResolve(), terser()]
}
