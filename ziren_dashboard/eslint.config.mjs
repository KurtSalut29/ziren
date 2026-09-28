import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  { ignores: [".next/**", "node_modules/**", "out/**", "build/**", "next-env.d.ts"] },
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  {
    // Week 6 found an HTML-injection path (station names reaching Leaflet's
    // innerHTML) and the fix relies on every call site remembering escapeHtml().
    // These make the next unescaped site a lint error instead of a code-review
    // hope. Legitimate sites carry an eslint-disable with the reason.
    rules: {
      "react/no-danger": "error",
      "no-restricted-syntax": [
        "error",
        {
          selector: "AssignmentExpression[left.property.name='innerHTML']",
          message: "Assigning innerHTML bypasses React's escaping. Use text nodes, or escapeHtml() from map-markers.ts and disable this rule with a reason.",
        },
      ],
    },
  },
];

export default eslintConfig;
