## Software Architecture

- Channel YAGNI in everything you do. When in doubt, ask.
- Do not do premature optimizations.
- Always look and opt for the simplest solution.
- Respect DRY - extract duplicated code.
- Respect SOLID principles.
- Write functions that do exactly one thing.
- Extract pure functions that can be easily tested.
- Extract business rules to separate functions. The naming of the function alone justifies the extraction.
- Put all functions and files in appropriate packages/folders/files.
- Do not optimize for or handle theoretical or near-theoretical edge cases. Tell the user if in doubt.
- Do not use type casting (`as`, `as?`, `as!`).
- Do not write comments. The code should be self-explanatory. Only add comments if something is genuinely hard to understand or there's a weird reason something needs to be done in a special way.

## Testing

- Write tests when it makes sense. Do not over-test.
- Do not write tautological tests
- Think of tests bottom-up. Rather many small and fast unit tests, than large and slow e2e tests.

## Git / GitHub

- Work trunk-based: finish a feature, then commit it straight to `main` and push. Don't create branches or pull requests.
- Give branches short and descriptive names. Do not include "claude/" or random id's.
- Always run the test suite (`swift test`) before pushing, and only push when it passes.
