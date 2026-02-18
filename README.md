# checksum.yazi

Features:
- Get `sha1sum`, `sha256sum`, `md5sum`, etc. for multiple files
- Yank the hash to use elsewhere (only xclip is supported at the moment)
- Searches for `file.shaXsum` to verify integrity (status report `OK`/`NG`)

Keymaps:
| key                     | function  | notes                                                 |
|-------------------------|-----------|-------------------------------------------------------|
| `<Esc>`/`q`             | quit      |                                                       |
| `<Up>`/`k`              | up        |                                                       |
| `<Down>`/`j`            | down      |                                                       |
| `<Enter>`/`<Right>`/`l` | select    |                                                       |
| `y`                     | yank hash | `y` is actually bound to<br>the same action as select |
| `<Back>`/`<Left>`/`h`   | back      | go from hash list back to<br>command selection        |
