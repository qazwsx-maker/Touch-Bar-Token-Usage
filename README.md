# Touch Bar Token Usage 🐾

แสดง **AI token usage (Claude Code)** บน **Touch Bar** ของ MacBook Pro — พร้อมปุ่ม **Accept / Deny** คำขอสิทธิ์ของ Claude ได้จาก Touch Bar โดยตรง มี **theme สี** และ **pet พิกเซล** ที่วิ่งเร็วขึ้นตามอัตราการเผา token 🔥

> Shows Claude Code token usage on the MacBook Pro Touch Bar, with one-tap
> Accept/Deny for Claude permission prompts, color themes, and a pixel pet
> that runs faster while your tokens burn. English section below.

![build](https://github.com/qazwsx-maker/Touch-Bar-Token-Usage/actions/workflows/build.yml/badge.svg)

---

## ฟีเจอร์

- **Widget บน Control Strip** (มุมขวาของ Touch Bar): **bar แสดง % ของ 5-hour block และ weekly limit** + **model ที่ใช้งานอยู่** + token/ค่าใช้จ่าย/burn rate วันนี้ — แตะเพื่อเปิดแถบเต็มพร้อมรายละเอียด (เวลารีเซ็ต block ฯลฯ)
- **Accept / Deny จาก Touch Bar**: เมื่อ Claude Code ขอสิทธิ์ใช้ tool (เช่น `Bash`, `Edit`, `Write`) แถบจะเด้งขึ้นมาให้กด ✓ Accept / ✕ Deny / Pass ได้ทันที (ผ่าน PreToolUse hook อย่างเป็นทางการของ Claude Code — ไม่ใช่การ inject คีย์บอร์ด)
- **Pets 🐧🐲👻**: สัตว์เลี้ยงพิกเซลบน Touch Bar วิ่งเร็วตามความแรงของการใช้ token (เพนกวิน/มังกร/ผี หรือปิด)
- **Themes**: Midnight / Matrix / Neon Sunset / Ocean / Mono + custom สีเองได้ทุกส่วน
- **เมนูบาร์**: สรุป token วันนี้/เดือนนี้, ค่าใช้จ่าย, burn rate, model ล่าสุด — ใช้ได้แม้เครื่องไม่มี Touch Bar
- **แผงลอยบนจอ (optional)**: ปุ่ม Accept/Deny แบบ on-screen เผื่อไว้ทดสอบหรือใช้กับเครื่องที่ไม่มี Touch Bar
- อ่านข้อมูลจาก transcript ของ Claude Code (`~/.claude/projects/**/*.jsonl`) ในเครื่อง — **ไม่มีการส่งข้อมูลออกนอกเครื่อง**

## ติดตั้ง

รองรับ: MacBook Pro ที่มี Touch Bar (2016–2020, รวม M1/M2 13"), macOS 12 Monterey ขึ้นไป

### วิธีที่ 1 — โหลดไฟล์ที่ build แล้ว (แนะนำ)

1. ไปที่แท็บ **Releases** ของ repo นี้ (หรือแท็บ **Actions** → เลือก run ล่าสุด → โหลด **Artifact** `TouchBarTokenUsage-*`)
2. แตกไฟล์ได้ `TouchBarTokenUsage.app` → ลากไปไว้ใน `/Applications`
3. แอปยังไม่ได้ notarize กับ Apple — ครั้งแรกให้ปลดล็อกก่อน:
   ```bash
   xattr -cr /Applications/TouchBarTokenUsage.app
   ```
   (หรือคลิกขวาที่แอป → Open → Open)
4. เปิดแอป จะเห็นไอคอน 🐾 บนเมนูบาร์ และ widget โผล่บน Touch Bar

### วิธีที่ 2 — build เองจาก source

ต้องมี Xcode หรือ Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/qazwsx-maker/Touch-Bar-Token-Usage.git
cd Touch-Bar-Token-Usage
make install        # build + คัดลอกไป /Applications
```

> เครื่อง Intel ที่ build ไม่ผ่านแบบ universal: `make install ARCH_FLAGS=""`

## เปิดใช้ปุ่ม Accept จาก Touch Bar

1. เปิดแอป → หน้าต่าง Preferences จะเปิดเองครั้งแรก (หรือคลิก 🐾 → Preferences…)
2. แท็บ **Setup** → กด **Install Claude Code hook**
   - แอปจะเขียนสคริปต์ไว้ที่ `~/.claude/touchbar-usage/hook.sh` และเพิ่ม hook ใน `~/.claude/settings.json` (merge อย่างระวัง ไม่ทับของเดิม)
3. กด **Send test approval request** — ต้องเห็นแถบ Accept/Deny เด้งบน Touch Bar
4. เปิด session ใหม่ของ Claude Code แล้วลองสั่งงานที่ต้องขอสิทธิ์ เช่นให้รัน `git push`

**การทำงาน**: ก่อน Claude ใช้ tool ที่เข้าเงื่อนไข (ค่าเริ่มต้น: `Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch`) hook จะถามแอปนี้ก่อน แอปโชว์ปุ่มบน Touch Bar **รอสูงสุดตามที่ตั้งไว้ (ค่าเริ่มต้น 20 วินาที)**
- กด **✓ Accept** → tool รันทันที
- กด **✕ Deny** → Claude ถูกปฏิเสธพร้อมเหตุผล "Denied from Touch Bar"
- กด **Pass** หรือปล่อยหมดเวลา → เด้งกลับไปถามใน terminal ตามปกติ (ไม่มีอะไรเสียหาย)

> หมายเหตุ: ระหว่างรอ การถามใน terminal จะยังไม่ขึ้น (hook ต้องตอบก่อน) ถ้ารู้สึกช้าไป ลดเวลารอได้ในแท็บ Approvals หรือจำกัด tools ด้วย regex — คำสั่งที่ auto-allow ด้วย permission rules อยู่แล้วก็จะโดนถามบน Touch Bar ด้วย แก้ได้ด้วยช่อง "Auto-pass Bash prefixes"

## ปรับแต่ง

คลิก 🐾 → **Preferences…**

| แท็บ | ตั้งค่าได้ |
|---|---|
| Setup | สถานะระบบ, ติดตั้ง hook, ส่ง test request, preview Touch Bar |
| Appearance | **Theme สี** (5 preset + custom), **Pet** (เพนกวิน/มังกร/ผี/ปิด), ความเร็วอนิเมชัน |
| Approvals | เปิด/ปิด, เวลารอ, regex เลือก tools, auto-pass prefixes, port, เสียง, on-screen panel |
| General | เปิด/ปิด limit bars + model บน widget, **ตั้งค่า 5-hour / weekly limit (tokens)**, metric ของ info line, เมนูบาร์, launch at login |

### Limit bars ทำงานยังไง

- **5h** = หน้าต่าง 5 ชั่วโมงแบบเดียวกับ session block ของ Claude (เริ่มนับจากข้อความแรก ปัดลงเป็นชั่วโมงเต็ม, เว้นว่างเกิน 5 ชม. = block ใหม่) พร้อมเวลารีเซ็ตในเมนู/แถบเต็ม
- **7d** = ผลรวมแบบ rolling 7 วัน
- ค่า limit: ตั้งเป็นจำนวน token เองได้ใน General → Usage limits หรือปล่อย **auto** (เทียบกับสถิติการใช้สูงสุดของคุณเอง — ครั้งแรกที่ใช้งาน bar จะดูเต็มไว เพราะ block ปัจจุบันคือสถิติสูงสุด พอมีประวัติสักพักจะนิ่งขึ้น)
- token ที่นับ: input + output + cache write (ไม่รวม cache read เพราะปริมาณมหาศาลจะกลบตัวเลข) — เป็นการ**ประมาณ**ฝั่ง local ไม่ได้อ่านโควตาจริงจากเซิร์ฟเวอร์ Anthropic

## ความปลอดภัย

- เซิร์ฟเวอร์ approval ฟังที่ `127.0.0.1` เท่านั้น และเช็ค token ลับ (`~/.claude/touchbar-usage/token`, สิทธิ์ 600) ที่แชร์กับ hook script — โปรเซสอื่นยิงคำขอปลอมไม่ได้
- hook script ล้มเหลว/แอปไม่ได้เปิด → exit เงียบ ๆ แล้ว Claude ใช้ flow ปกติ ไม่มีทางค้าง
- แอปไม่ sandbox (จำเป็นสำหรับ private Touch Bar API) และไม่ notarize — ต้อง `xattr -cr` ตอนติดตั้ง

## Troubleshooting

- **ไม่เห็น widget บน Touch Bar** — เครื่องต้องมี Touch Bar จริง, อย่ารัน Pock/MTMR พร้อมกัน (ใช้ Control Strip ชนกัน), ลองปิด-เปิดแอปใหม่
- **กด Install hook แล้ว Claude ไม่ถามบน Touch Bar** — ต้องเปิด **session ใหม่** ของ Claude Code (hook โหลดตอนเริ่ม session), เช็คว่าแอปเปิดอยู่, ดูสถานะ server ในแท็บ Setup
- **ตัวเลขเป็น 0** — ยังไม่มีข้อมูลใน `~/.claude/projects` (เครื่องนั้นต้องเคยรัน Claude Code), ตัวเลขนับเฉพาะ ~35 วันล่าสุด
- **ค่าใช้จ่ายไม่ตรง** — เป็นการประมาณจากตาราง pricing ต่อ model; ถ้าใช้แผน subscription ตัวเลขนี้คือ "มูลค่าเทียบ API"

## Uninstall

1. Preferences → Approvals → **Remove Hook**
2. Quit แอป แล้วลบ `/Applications/TouchBarTokenUsage.app`
3. `rm -rf ~/.claude/touchbar-usage`

---

# English

## What it is

A menu-bar app for Touch Bar MacBook Pros (2016–2020 incl. M1/M2 13", macOS 12+) that:

- shows **5-hour-block and weekly usage-limit bars**, the **active model**, plus today's tokens/cost/burn rate in the Control Strip (limits are estimated locally ccusage-style: custom token limits or auto = your highest usage on record; counted tokens are input + output + cache writes),
- lets you **Accept / Deny Claude Code permission prompts right on the Touch Bar** (via the official PreToolUse hook protocol — the hook long-polls this app over localhost; no keyboard injection),
- has **5 color themes + custom colors** and **3 pixel pets** (penguin 🐧 / dragon 🐲 / ghost 👻) whose run speed follows your token burn rate,
- keeps everything **local** — it only reads `~/.claude/projects/**/*.jsonl`.

## Install

- Download `TouchBarTokenUsage.zip` from **Releases** (or the latest **Actions** artifact), unzip to `/Applications`, then `xattr -cr /Applications/TouchBarTokenUsage.app` (unsigned app), launch.
- Or build from source: `make install` (needs Xcode CLT).

Then open Preferences (first launch opens it), click **Install Claude Code hook**, and **Send test approval request** to verify. Start a fresh Claude Code session to pick up the hook.

## How the approval flow works

The installed PreToolUse hook forwards each matching tool call (default `Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch`) to the app, which shows Accept/Deny/Pass on the Touch Bar (and an optional floating panel) for up to N seconds (default 20). Accept/Deny answer Claude directly with the official hook JSON; Pass or timeout falls back to the normal terminal prompt. If the app isn't running, the hook exits silently — zero risk to your workflow. Requests are authenticated with a private token shared between the app and the hook script, and the server only listens on `127.0.0.1`.

## Notes

- The Control Strip widget uses the same private `DFRFoundation` API as Pock/MTMR — don't run those simultaneously.
- The app is ad-hoc signed, not notarized; hence the `xattr -cr` step.
- Cost figures are estimates from a built-in per-model price table (lines that carry `costUSD` use it directly).

## Development

```bash
swift test        # core logic tests (parser, pricing, hook merger) — also runs on Linux
make zip          # universal build + .app bundle + zip (macOS)
```

CI builds a universal (arm64 + x86_64) `.app` on every push; tags `v*` (or the manual **Run workflow** button with a tag) publish a GitHub Release.

## License

MIT
