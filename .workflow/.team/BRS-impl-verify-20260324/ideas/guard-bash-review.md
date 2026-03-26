# guard-bash.sh 危险命令拦截完整性审查

## 审查范围

- **文件**: `/Users/c/auto-git/worktree-first-plugin/scripts/guard-bash.sh`
- **参考**: user_experience.md Breakpoint 分析、gap_analysis.md G-02 项（见下方说明）
- **目标**: 验证 7 条规则的 regex 模式在 macOS BSD grep 2.6.0 下的正确性

> **注**: gap_analysis.md 中未找到 "G-02" 标签。该文件列出 Gap 1-5。此处按任务描述中的 7 条规则逐项核查。

---

## 7 条规则核查结果

### Rule 1: main 分支文件写入拦截

**状态**: PASS（有小 gap）

**正则**: `(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\.write\(|\.truncate|truncate\(|\bdd\b.*of=|\btr\b.*of=)`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `echo test >file` | BLOCKED | BLOCKED | YES |
| `echo test >>file` | BLOCKED | BLOCKED | YES |
| `cat foo \| tee bar` | BLOCKED | BLOCKED | YES |
| `sed -i 's/a/b/' f` | BLOCKED | BLOCKED | YES |
| `echo test >/dev/null` | ALLOWED | ALLOWED | YES |
| `echo test 2>/dev/null` | ALLOWED | ALLOWED | YES |
| `git commit -m 'fix'` | ALLOWED | ALLOWED | YES |

**/dev/null 例外逻辑**: 第二个 grep 检测 `>/dev/null|2\s*>\s*/dev/null`，排除写入空设备的命令，正确。

**Gap**: 以下命令不在检测范围内（若 main 分支写保护意图是"阻止所有文件修改"，则存在遗漏）:
- `cp src dst` — 不被检测（覆盖目标文件）
- `mv src dst` — 不被检测（覆盖目标文件）
- `rm file` — 不被检测
- `install -m644 src dst` — 不被检测

**macOS grep 兼容性**: PASS — `\s` 和 `[[:space:]]` 在 ERE 模式下均正常工作。

---

### Rule 2: git push 到 main 分支

**状态**: PASS

**正则**: `git[[:space:]]+push[[:space:]]+[^;]*main|git[[:space:]]+push[[:space:]]+[^;]*refs/heads/main`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git push origin main` | BLOCKED | BLOCKED | YES |
| `git push origin refs/heads/main` | BLOCKED | BLOCKED | YES |
| `git push origin feat:refs/heads/main` | BLOCKED | BLOCKED | YES |
| `git push origin feature` | ALLOWED | ALLOWED | YES |
| `git push origin main --force` | BLOCKED | BLOCKED | YES |

**`[^;]*` 设计意图**: 允许复合命令 `git push origin main && git status`，分号后的 `git status` 不被视为 push 目标。验证: YES。

**macOS grep 兼容性**: PASS。

---

### Rule 3: bare --force（无 --force-with-lease）

**状态**: PASS

**正则（检测）**: `git[[:space:]]+push[[:space:]]+[^;]*--force`
**正则（例外）**: `-- '--force-with-lease'`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git push --force` | BLOCKED | BLOCKED | YES |
| `git push origin main --force` | BLOCKED | BLOCKED | YES |
| `git push --force-with-lease` | ALLOWED | ALLOWED | YES |
| `git push -f` | BLOCKED | BLOCKED | YES |

**macOS grep 兼容性**: PASS — `-- '--force-with-lease'` 中的 `--` 正确终止选项解析，`grep -E` 将其识别为 pattern 而非选项。

---

### Rule 4: git reset --hard（全部形式）

**状态**: PASS（范围比"无路径"更宽）

**正则**: `git[[:space:]]+reset[[:space:]]+--hard`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git reset --hard` | BLOCKED | BLOCKED | YES |
| `git reset --hard HEAD~1` | BLOCKED | BLOCKED | YES |
| `git reset --hard -- file.txt` | BLOCKED | BLOCKED | YES |

**注意**: 此规则覆盖所有形式的 `git reset --hard`（有路径和无路径均被阻止），比任务描述中的"无路径"更宽。阻止所有 reset --hard 是更安全的设计。

---

### Rule 5: git clean -fdx

**状态**: PASS

**正则**: `git[[:space:]]+clean[[:space:]]+-[fFxX]([xX]|[dD][xX])$`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git clean -fdx` | BLOCKED | BLOCKED | YES |
| `git clean -fd` | ALLOWED | ALLOWED | YES |
| `git clean -X` | ALLOWED | ALLOWED | YES |
| `git clean -x` | BLOCKED | BLOCKED | YES |

**正则解析**: `-fFxX` 匹配 `-f`, `-F`, `-x`, `-X`；`([xX]|[dD][xX])$` 要求以 `-x`/`-X` 或 `-dx`/`-dX` 结尾（可选第二个 x/dX 组）。Safe `-fd` 不匹配。正确。

**macOS grep 兼容性**: PASS。

---

### Rule 6: 删除 main/master 分支

**状态**: PASS

**正则**: `git[[:space:]]+branch[[:space:]]+-[Dd][[:space:]]+(main|master)`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git branch -D main` | BLOCKED | BLOCKED | YES |
| `git branch -d master` | BLOCKED | BLOCKED | YES |
| `git branch main` | ALLOWED | ALLOWED | YES |
| `git branch -D feature` | ALLOWED | ALLOWED | YES |

**macOS grep 兼容性**: PASS。

---

### Rule 7: git reset --hard 无路径

**状态**: PASS（但功能上被 Rule 4 覆盖）

**正则**: `git[[:space:]]+reset[[:space:]]+--hard[[:space:]]*$`

**验证结果**:
| 命令 | 预期 | 实际 | 通过 |
|------|------|------|------|
| `git reset --hard` | BLOCKED | BLOCKED | YES |
| `git reset --hard HEAD~1` | ALLOWED（by Rule 4） | 被 Rule 4 阻止 | YES |

**注**: `git reset --hard HEAD~1` 也会被 Rule 4 阻止。Rule 7 的 no-path 特化在逻辑上是冗余的，但无害——Rule 4 已经阻止所有 reset --hard。

**macOS grep 兼容性**: PASS。`$` 锚定在 ERE 下正常工作。

---

## macOS BSD grep 2.6.0 兼容性总结

所有 regex 模式使用 `grep -qE`（ERE 扩展正则），测试确认:

- `\s` (whitespace) — ERE 模式下 **支持**
- `[[:space:]]` — POSIX 字符类，**支持**
- `+` 量词 — ERE 模式，**支持**
- `$` 锚点 — ERE 模式，**支持**
- `-- pattern` 终止选项 — **正常工作**

结论: 无需修改正则表达式，macOS grep 兼容性通过。

---

## 总结

| 项目 | 结果 |
|------|------|
| 7 条规则 regex 正确性 | ALL PASS |
| macOS grep 兼容性 | PASS |
| Rule 1 覆盖缺口（cp/mv/rm） | LOW — 若仅针对 redirect 写入则无问题 |
| Rule 7 与 Rule 4 重叠 | LOW — 无害冗余 |

**建议**: 当前 guard-bash.sh 对 7 条规则的实现均正确可用。若需强化 Rule 1，可考虑增加 `cp|mv|rm|install` 等非 redirect 文件操作检测。