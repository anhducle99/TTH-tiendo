import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, '.', ['VERCEL', 'VITE_'])
  return {
    plugins: [react()],
    base: env.VERCEL ? '/' : (env.VITE_BASE_PATH || (command === 'build' ? '/tien-do-phong-kham/' : '/')),
  }
})
