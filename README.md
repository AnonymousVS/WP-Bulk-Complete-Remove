# WP-Bulk-Complete-Remove

ลบ WordPress sites แบบ **completely** — ไม่เหลือขยะแม้แต่ชิ้นเดียว

รองรับทั้ง WordPress ที่สร้างด้วย **WP Toolkit** และ **Softaculous**

## สิ่งที่ลบ (9 ขั้นตอน)

```
① อ่าน wp-config.php (ดึง DB name + DB user)
② ลบ Database          ← cPanel UAPI (ไม่เหลือ ghost entry)
③ ลบ Database user     ← cPanel UAPI (ไม่เหลือ ghost entry)
④ WP Toolkit detach    ← หายจาก WP Toolkit GUI
⑤ Softaculous record   ← หายจาก Softaculous GUI
⑥ wp-cron entries      ← ลบจาก crontab ของ user
⑦ WP Toolkit log files
⑧ wordpress-backups/
⑨ rm -rf domain folder ← ทำเป็นขั้นตอนสุดท้าย
   ลบทุกอย่างรวม: WordPress files, cgi-bin/, error_log,
   .wp-toolkit/, .wp-toolkit-ignore, .lscache/, wp-content/cache/ ฯลฯ
```

## ทำไมถึงเร็ว

ไม่ใช้ `wp-toolkit --remove` (ช้า ~20 วินาที/site เพราะต้อง bootstrap WordPress)

ใช้ **Manual bash + cPanel UAPI** แทน:

```
wp-toolkit --remove:   ~20 วินาที/site → 500 sites = ~3 ชั่วโมง
Manual + UAPI:         ~1-2 วินาที/site → 500 sites = ~15 นาที
```

## ทำไมใช้ cPanel UAPI ลบ DB ไม่ใช้ mysql ตรง

```
mysql -e "DROP DATABASE..."     → DB ถูกลบ แต่ cPanel ไม่รู้ → ghost entry ค้าง
uapi Mysql delete_database      → DB ถูกลบ + cPanel อัปเดต record → สะอาด ✓
```

ส่วน files ใช้ `rm -rf` เพราะ cPanel ไม่ track files — ลบตรงเร็วที่สุดและสะอาด

## ความต้องการ

- เซิร์ฟเวอร์ cPanel/WHM
- WHM Terminal หรือ SSH root access
- มี `uapi` command (มาพร้อม cPanel)

## วิธีใช้งาน (ทุกครั้งที่จะลบ)

### ขั้นตอนที่ 1: แก้ไข remove-domains-list.csv บน GitHub

เปิดไฟล์ `remove-domains-list.csv` บน GitHub แล้วใส่ข้อมูล:

```csv
domain,cpanel_user
apple999.co,y2026m01sv01
betking99.com,y2026m02sv01
game123.net,y2026m03sv01
slot456.com,y2026m03sv01
```

เปิดใน spreadsheet จะเห็น:

```
     Column A              Column B
─────────────────────────────────────────
     domain                cpanel_user      ← header (ข้ามอัตโนมัติ)
     apple999.co           y2026m01sv01
     betking99.com         y2026m02sv01
     game123.net           y2026m03sv01
     slot456.com           y2026m03sv01
```

กด **Commit Changes**

หมายเหตุ:
- แถวแรก `domain,cpanel_user` เป็น header → script ข้ามให้อัตโนมัติ
- Column A = ชื่อ domain / Column B = ชื่อ cPanel user (บังคับใส่ทุกบรรทัด)
- บรรทัดว่าง, ช่องว่างหน้า/หลัง → script จัดการให้อัตโนมัติ
- ใส่ `https://domain.com/` มาก็ได้ → script ตัดเหลือแค่ชื่อ domain
- บรรทัดที่ขึ้นต้นด้วย `#` คือ comment → ถูกข้าม
- ถ้าไม่ใส่ cPanel user → script แจ้ง error หยุดทันที

### ขั้นตอนที่ 2: Login เข้า WHM Terminal

เข้า WHM → Search "Terminal" → เปิด Terminal

### ขั้นตอนที่ 3: รัน script

```bash
bash <(curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh)
```

ไม่ต้องดาวน์โหลดมาก่อน — คำสั่งนี้ดึงทั้ง script + domain list ล่าสุดจาก GitHub ทุกครั้งที่รัน

> **Note:** หากรันครั้งที่ 2 เป็นต้นไป โปรดตรวจสอบรายชื่อ domain ที่แสดงให้ถูกต้อง GitHub อาจ cache ไฟล์เก่าไว้ หากรายชื่อไม่ตรง ให้รอ 5 นาทีแล้วรันใหม่

Script จะ:
1. ดึง CSV ล่าสุดจาก GitHub
2. ตรวจสอบ format (domain + cPanel user ครบทุกบรรทัด)
3. แสดงรายชื่อ domain + cPanel user ให้ดู
4. ถามว่า "ลบทั้ง 500 domains?" → พิมพ์ `yes`
5. ไล่ลบทีละ domain แบบ completely (มี progress bar)
6. แสดง report สรุป

### ขั้นตอนที่ 4: ดูผลลัพธ์

```
  ══════════════════════════════════════
    RESULTS                   elapsed: 12m15s
  ══════════════════════════════════════

  Total domains:     500

  ✓ Removed:           487
  ✗ Failed:            3
  → Not found:         10

  ✓ ลบเรียบร้อย 487 domains — ไม่เหลือขยะ
```

### ขั้นตอนที่ 5: เช็คว่าลบเกลี้ยงจริง

เช็คทีเดียวทุก domain (เปลี่ยนชื่อ domain ตามจริง):

```bash
D="balen1688.com"
echo "=== ตรวจ ${D} ==="

echo "① Domain folder:"
find /home/ -path "*${D}*" -type d 2>/dev/null && echo "  ⚠ folder ค้าง!" || echo "  ✓ สะอาด"

echo "② Files:"
find /home/ -path "*${D}*" -type f 2>/dev/null && echo "  ⚠ files ค้าง!" || echo "  ✓ สะอาด"

echo "③ WP Toolkit:"
wp-toolkit --list 2>/dev/null | grep -qi "$D" && echo "  ⚠ ยังเห็น!" || echo "  ✓ สะอาด"

echo "④ Softaculous:"
find /var/softaculous/installations/ -name "*.ini" -exec grep -l "$D" {} \; 2>/dev/null | grep -q . && echo "  ⚠ ค้าง!" || echo "  ✓ สะอาด"

echo "⑤ Database:"
mysql -N -e "SHOW DATABASES;" 2>/dev/null | grep -qi "${D%%.*}" && echo "  ⚠ DB ยังอยู่!" || echo "  ✓ สะอาด"

echo "⑥ DB user:"
mysql -N -e "SELECT User FROM mysql.user;" 2>/dev/null | grep -qi "${D%%.*}" && echo "  ⚠ user ค้าง!" || echo "  ✓ สะอาด"

echo "⑦ Cron:"
grep -r "$D" /var/spool/cron/ 2>/dev/null && echo "  ⚠ cron ค้าง!" || echo "  ✓ สะอาด"
```

ต้องขึ้น ✓ ทั้ง 7 ข้อ = ลบเกลี้ยง

หรือเช็คหลาย domains ทีเดียว:

```bash
for D in domain1.com domain2.com domain3.com; do
  echo "=== ${D} ==="
  find /home/ -path "*${D}*" 2>/dev/null && echo "  ⚠ ยังค้าง!" || echo "  ✓ สะอาด"
  wp-toolkit --list 2>/dev/null | grep -qi "$D" && echo "  ⚠ WP Toolkit!" || echo "  ✓ WP Toolkit สะอาด"
  find /var/softaculous/installations/ -name "*.ini" -exec grep -l "$D" {} \; 2>/dev/null | grep -q . && echo "  ⚠ Softaculous!" || echo "  ✓ Softaculous สะอาด"
  echo ""
done
```

### ขั้นตอนที่ 6: รัน script ลบ addon domain (ตัวที่มีอยู่แล้ว)

เมื่อ WordPress ถูกลบเกลี้ยงแล้ว ค่อยรัน script ลบ addon domain ตัวที่มีอยู่แล้ว

**ลำดับไม่สำคัญ** — จะลบ addon domain ก่อนหรือหลังก็ได้ script จัดการให้ทั้ง 2 กรณี

## คำสั่งทั้งหมด (สรุปรวม)

```bash
# 1) Login เข้า WHM Terminal

# 2) รัน (ดึง script + CSV จาก GitHub อัตโนมัติ)
bash <(curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh)

# 3) ตรวจสอบรายชื่อ domain ให้ถูกต้อง → พิมพ์ yes

# 4) รอจนเสร็จ → ดู report

# 5) รัน script ลบ addon domain (ตัวที่มีอยู่แล้ว)
```

## ตารางคำสั่ง

รันจาก GitHub โดยตรง (แนะนำ — ได้ script + CSV ล่าสุดเสมอ):

| คำสั่ง | คำอธิบาย |
|---|---|
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh)` | ดึง CSV จาก GitHub แล้วลบ (ถาม confirm) |
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh) --dry-run` | ทดสอบก่อน ไม่ลบจริง |
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh) --yes` | ไม่ถาม confirm (ระวัง!) |

หรือดาวน์โหลดมาก่อน:

```bash
curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh -o /usr/local/sbin/wp-bulk-complete-remove.sh && chmod +x /usr/local/sbin/wp-bulk-complete-remove.sh && echo "✓ Installed"
```

จากนั้นรัน:

```bash
wp-bulk-complete-remove.sh
wp-bulk-complete-remove.sh --dry-run
wp-bulk-complete-remove.sh --local     # ใช้ไฟล์ /usr/local/sbin/remove-domains-list.csv แทน GitHub
```

> **Note:** หากรันครั้งที่ 2 เป็นต้นไป GitHub อาจ cache ไฟล์เก่าไว้ หากรายชื่อไม่ตรงกับที่ Commit ไป ให้รอ 5 นาทีแล้วรันใหม่

## CSV Format

```csv
domain,cpanel_user
ambking123.com,y2026m03sv01
balen1688.com,y2026m03sv01
game456.net,y2026m02sv01
slot789.com,y2026m01sv01
```

| Column | ข้อมูล | บังคับ |
|---|---|---|
| A | ชื่อ domain | ✓ |
| B | ชื่อ cPanel user | ✓ |

ถ้า domain เดียวกันอยู่ใน cPanel อื่นด้วย → **ไม่ถูกลบ** เพราะ script ลบเฉพาะ cPanel user ที่ระบุใน Column B

Script รองรับ input หลายรูปแบบ:

```
domain.com,y2026m03sv01             → ✓ ปกติ
  domain.com , y2026m03sv01         → ✓ trim whitespace
https://domain.com/,y2026m03sv01   → ✓ ตัด protocol + slash
domain.com                          → ✗ ERROR ไม่มี cPanel user
# comment                           → ข้าม
(บรรทัดว่าง)                         → ข้าม
domain,cpanel_user                  → ข้าม (header row)
```

## รองรับ 2 โครงสร้าง path

```
/home/USERNAME/DOMAIN/
/home/USERNAME/public_html/DOMAIN/
```

Script เช็คทั้ง 2 path ให้อัตโนมัติ

## รองรับหลาย cPanel accounts ต่อ server

```
Server
├── y2026m01sv01 (cPanel #1) — 200+ addon domains
├── y2026m02sv01 (cPanel #2) — 300+ addon domains
└── y2026m03sv01 (cPanel #3) — 200+ addon domains
```

ระบุ cPanel user ใน Column B ของ CSV → script รู้ทันทีว่า domain อยู่ cPanel ไหน ไม่มีทางลบผิดคน

## หลักการทำงาน

```
remove-domains-list.csv (จาก GitHub)
  ↓
อ่าน CSV: Column A = domain, Column B = cPanel user
  ↓
แต่ละ domain:
  ↓
① อ่าน wp-config.php ดึง DB name + DB user
  ↓
② cPanel UAPI: ลบ Database (ไม่เหลือ ghost entry ใน cPanel GUI)
  ↓
③ cPanel UAPI: ลบ DB User (ไม่เหลือ ghost entry ใน cPanel GUI)
  ↓
④ wp-toolkit --detach (หายจาก WP Toolkit GUI)
  ↓
⑤ ลบ Softaculous .ini record (หายจาก Softaculous GUI)
  ↓
⑥ ลบ wp-cron entries จาก crontab
  ↓
⑦ ลบ WP Toolkit log files
  ↓
⑧ ลบ wordpress-backups/
  ↓
⑨ rm -rf domain folder ทั้งหมด (ขั้นตอนสุดท้าย)
   ลบรวม: WordPress files, cgi-bin/, error_log,
   .wp-toolkit/, .wp-toolkit-ignore, .lscache/ ฯลฯ
  ↓
Report + Log
```

## ดู Log

```bash
# report ล่าสุด
ls -lt /var/log/wp-bulk-remove/report-*.txt | head -5

# อ่าน report
cat /var/log/wp-bulk-remove/report-20260401_160000.txt

# detailed log
cat /var/log/wp-bulk-remove/remove-20260401_160000.log
```

Log เก่ากว่า 1 วันถูกลบอัตโนมัติทุกครั้งที่รัน script

## ทำไมไม่ใช้ WP Toolkit GUI ลบ

WP Toolkit GUI ไม่เหมาะกับการลบ 500+ sites เพราะ:
- **Memory exhausted** — WP Toolkit ใช้ PHP memory ของ WHM ที่จำกัด 128MB
- **Timeout 60 วินาที** — bulk operation เกิน timeout แล้วค้าง
- **Cloudflare 524** — ตัด connection หลัง 100 วินาที
- **ไม่ลบ DB user** — เหลือ orphaned DB users สะสม
- **ไม่ cleanup .wp-toolkit dirs** — สะสมได้ถึง 19GB ต่อ site
- **ไม่ลบ folder ทั้งหมด** — เหลือ cgi-bin/, error_log ค้าง
- **ค้างบ่อย** — "backend API failed with status code 500"

Script นี้ใช้ cPanel UAPI + bash ตรง → ไม่มีปัญหาเหล่านี้

## License

MIT
