import { defineConfig, globalIgnores } from 'eslint/config'
import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

// The template's rules, in eslint-config-next 16's flat form (its FlatCompat
// bridge — `compat.extends('next/core-web-vitals')` — fails on 16).
export default defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // Rules eslint-config-next 16 brings that the template was not written
      // against, turned off by name rather than rewriting upstream code: the
      // mount-then-set-state pattern (react-hooks/set-state-in-effect) and
      // ref reads during render (react-hooks/refs) in its header, admin bar
      // and theme components.
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/refs': 'off',
      '@typescript-eslint/ban-ts-comment': 'warn',
      '@typescript-eslint/no-empty-object-type': 'warn',
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        {
          vars: 'all',
          args: 'after-used',
          ignoreRestSiblings: false,
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^(_|ignore)',
        },
      ],
    },
  },
  {
    // worker.ts imports the generated `.open-next/worker.js` the way the
    // OpenNext custom-worker howto does: `@ts-ignore` with a reason, because
    // the file does not exist before the build and an `@ts-expect-error`
    // would then be "unused" after it.
    files: ['worker.ts'],
    rules: { '@typescript-eslint/ban-ts-comment': ['error', { 'ts-ignore': 'allow-with-description' }] },
  },
  globalIgnores([
    '.next/**',
    '.open-next/**',
    '.wrangler/**',
    'next-env.d.ts',
    'cloudflare-env.d.ts',
    'src/payload-types.ts',
    'src/payload-generated-schema.ts',
    'src/app/(payload)/admin/importMap.js',
  ]),
])
