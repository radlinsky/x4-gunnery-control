# Source policy

## Order of proof

1. Project code and tests establish the question's integration context.
2. Current unpacked game files and XSD establish shipped behavior/signatures.
3. Installed extension sources establish a third-party technique only.
4. Official Egosoft documentation establishes documented public intent.
5. Community sources provide leads only until corroborated.

## Classifications

| Status | Meaning |
|---|---|
| `documented-public` | Current official documentation names the public API/behavior. |
| `shipped-source` | Current game catalog source or XSD demonstrates it. |
| `third-party-technique` | An installed mod uses it; verify independently before relying on it. |
| `inference` | A bounded conclusion from evidence; state the uncertainty. |
| `live-tested` | Reproduced in a recorded game build/save; include date and conditions. |

Do not describe a missing search result as an API guarantee. Write it as
`inference`, scope the files/build searched, and add a live test where it
affects player interaction.

## Update rule

Update a durable claim only after checking its version, source path/URL, and
classification. Include `X4`, `Status`, `Source`, and `Live test` fields. Keep
paraphrases short; proprietary unpacked source stays outside the repository.

## Reference index rule

Keep `references/index.md` focused on durable technical provenance. Index rows
may summarize the technical subject, evidence boundary, applicable X4/source
version, source/cache/parser or tool provenance, evidence classification, and
an accepted or live-tested SHA when that SHA is technically useful. Do not put
GitHub issue numbers, task labels, or workstream identifiers in index-row
titles or descriptions. GitHub issues carry that project-management history.
