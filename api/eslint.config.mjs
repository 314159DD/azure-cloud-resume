import { defineConfig } from "eslint/config";
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default defineConfig(
  { ignores: ["dist/**", "node_modules/**"] },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: { allowDefaultProject: ["eslint.config.mjs"] },
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Test fakes implement async interfaces without awaiting.
      "@typescript-eslint/require-await": "off",
      // node:test registers tests via returned promises the runner awaits itself.
      "@typescript-eslint/no-floating-promises": [
        "error",
        { allowForKnownSafeCalls: [{ from: "package", name: ["test", "describe", "it"], package: "node:test" }] },
      ],
    },
  },
);
