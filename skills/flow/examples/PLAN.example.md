---
flow: plan
task_slug: csv-to-json-cli
created: 2026-01-15
requirements: [R-01, R-02, R-03]
must_haves:
  truths:
    - "Running `csv2json sample.csv` prints a valid JSON array with one object per row"
    - "Invalid input exits with code 1 and a readable error message"
  artifacts:
    - path: "csv2json.py"
      provides: "CLI entry point and conversion logic"
    - path: "tests/test_csv2json.py"
      provides: "Automated tests for the happy path and error cases"
  key_links:
    - from: "tests/test_csv2json.py"
      to: "csv2json.py"
      via: "imports convert() and main()"
---

# Plan: CSV to JSON command-line tool

## Original user task (verbatim)
> Build a small CLI that converts a CSV file to JSON. It must handle quoted
> fields, fail clearly on bad input, and have tests.

## Requirements (coverage audit)
| ID | Requirement (quote) | Criticality | Tasks |
|----|---------------------|-------------|-------|
| R-01 | "converts a CSV file to JSON" | mandatory | T1 |
| R-02 | "handle quoted fields, fail clearly on bad input" | mandatory | T1, T2 |
| R-03 | "have tests" | mandatory | T2 |

## Tasks
<task id="T1" wave="1" requirements="R-01,R-02">
  <name>Implement the converter and CLI</name>
  <files>csv2json.py</files>
  <action>Create convert(path) that reads the CSV with the standard csv module
  (header row = keys, quoted fields and embedded commas supported) and returns a
  list of dicts. Create main(argv) that prints json.dumps(result, indent=2) and
  returns 0; on missing file or empty input print a one-line error to stderr and
  return 1.</action>
  <verify>python csv2json.py tests/fixtures/sample.csv | python -m json.tool</verify>
  <done>Valid JSON is printed for the sample; a missing file exits with code 1.</done>
</task>

<task id="T2" wave="2" requirements="R-02,R-03">
  <name>Add tests and a fixture</name>
  <files>tests/test_csv2json.py, tests/fixtures/sample.csv</files>
  <action>Write tests for: plain rows, a quoted field containing a comma, a
  missing file (exit code 1), an empty file (exit code 1).</action>
  <verify>python -m pytest tests -q</verify>
  <done>All four tests pass.</done>
</task>

## Automatic acceptance
The executor runs the CLI against the fixture and a missing file, captures the
stdout/stderr and exit codes into `.flow/.../acceptance.log`, and asserts on them.
No manual checks are left to the user.

## Risks
- Encoding differences in CSV files (assume UTF-8, document it).

## Open Questions
None.
