# Releasing

`version.txt` holds one line: `build,path,size,crc32`

    26111828,releases/3DSC3_26111828.nex,442880,133863C8

* build  - YYMMDDxx, the same string as `s_ver` in `main.asm` (shown on the menu)
* path   - the `.nex` to download, relative to the repo root
* size   - bytes, to check the download is complete
* crc32  - upper-case hex CRC-32 of the file

Each release: add `releases/3DSC3_<build>.nex`, update `version.txt`, push.
