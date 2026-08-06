# Catalog tooling evidence

### XRCatTool v1.11 selected-file interface
- X4: 9.00 compatible (the v1.11 readme states X4 uses the X Rebirth catalog format)
- Status: documented-public
- Source: `XTools_1.11.zip!Readme.txt`
- Tool: XRCatTool 1.11; SHA-256 `4ec0db79670edba7d1568ef04eb1666d712fc1b4bd7222e723d67011c59f15ec`
- Live test: yes — selected five schema files from the X4 9.00 base catalogs
  on WSL2 on 2026-08-03
- Finding: the documented console form is `-in <paths> -out <path>` with
  repeatable include/exclude regex lists; later inputs override earlier ones,
  and v1.11 supports the X4/XR catalog format. A 2026-08-03 WSL smoke test
  additionally confirmed that directory output must exist before execution;
  the wrapper therefore creates its already-validated new directory immediately
  before launching the tool.
- Limitations: this repository's wrapper accepts only existing `.cat` inputs,
  a new directory output, and include/exclude filters. It forbids `-append`,
  `-diff`, catalog output, X4 installation output, and execution of unverified
  tool archives. Do not run an untrusted Windows executable without separate
  review.

### WSL ZIP extraction may omit the executable bit
- X4: tool workflow; independent of game version
- Status: live-tested
- Source: `scripts/extract-selected-xrcat.sh` smoke test on WSL2
- Live test: yes — XRCatTool 1.11 cache preparation on 2026-08-03
- Finding: a Windows-created tool ZIP can extract `XRCatTool.exe` without its
  POSIX executable bit. Mark only the ignored tool-cache copy executable before
  WSL interop; never modify the source ZIP or game files.
