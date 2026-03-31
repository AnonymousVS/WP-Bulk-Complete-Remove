# WP-Bulk-Complete-Remove

ลบ WordPress sites แบบ **completely** — ไม่เหลือขยะแม้แต่ชิ้นเดียว

รองรับทั้ง WordPress ที่สร้างด้วย **WP Toolkit** และ **Softaculous**

## สิ่งที่ลบ

```
✓ WordPress files ทั้งหมด
✓ WordPress database
✓ Database user (orphaned)
✓ WP Toolkit instance record + log files
✓ .wp-toolkit/ directories (สะสมได้ถึง 19GB)
✓ .wp-toolkit-ignore file
✓ Softaculous installation record
✓ .lscache/ (LiteSpeed cache)
✓ wordpress-backups/
✓ wp-content/cache/, upgrade/, tmp/, ai1wm-backups/, updraft/
✓ wp-cron entries จาก crontab ของ user
✗ Addon domain (ใช้ script อีกตัวแยก)
```

## ความต้องการ

- เซิร์ฟเวอร์ cPanel/WHM
- WHM Terminal หรือ SSH root access
- มี `/etc/userdomains` (มาพร้อม cPanel)

## วิธีใช้งาน (ทุกครั้งที่จะลบ)

### ขั้นตอนที่ 1: แก้ไข remove-domains-list.txt บน GitHub

เปิดไฟล์ `remove-domains-list.txt` บน GitHub แล้วใส่ชื่อ domain ที่ต้องการลบ:

```
apple999.co
betking99.com
game123.net
slot456.com
```

กด **Commit Changes**

หมายเหตุ:
- บรรทัดละ 1 domain
- บรรทัดว่าง, ช่องว่างหน้า/หลัง domain → script จัดการให้อัตโนมัติ
- ใส่ `https://domain.com/` มาก็ได้ → script ตัดเหลือแค่ชื่อ domain
- บรรทัดที่ขึ้นต้นด้วย `#` คือ comment → ถูกข้าม

### ขั้นตอนที่ 2: Login เข้า WHM Terminal

เข้า WHM → Search "Terminal" → เปิด Terminal

### ขั้นตอนที่ 3: รัน script

```bash
bash <(curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh)
```

ไม่ต้องดาวน์โหลดมาก่อน — คำสั่งนี้ดึงทั้ง script + domain list ล่าสุดจาก GitHub ทุกครั้งที่รัน

Script จะ:
1. ดึง domain list ล่าสุดจาก GitHub
2. แสดงรายชื่อ domain ให้ดู
3. ถามว่า "ลบทั้ง 500 domains?" → พิมพ์ `yes`
4. ไล่ลบทีละ domain แบบ completely
5. แสดง report สรุป

### ขั้นตอนที่ 4: ดูผลลัพธ์

```
  ══════════════════════════════════════
    RESULTS                   elapsed: 16m32s
  ══════════════════════════════════════

  Total domains:     500

  ✓ Removed:           487
  ✓ Items cleaned:     2,431
  ✗ Failed:            3
  → Not found:         10
```

### ขั้นตอนที่ 5: เช็คว่าลบเกลี้ยงจริง

เช็คทีเดียวทุก domain ที่ลบไป (เปลี่ยนชื่อ domain ตามจริง):

```bash
for D in domain1.com domain2.com domain3.com; do
  echo "=== ${D} ==="
  find /home/ -path "*${D}*" -name "wp-config.php" 2>/dev/null && echo "  ⚠ FILES ยังอยู่!" || echo "  ✓ files สะอาด"
  find /home/ -path "*${D}*" -name ".wp-toolkit" -type d 2>/dev/null | grep -q . && echo "  ⚠ .wp-toolkit ค้าง!" || echo "  ✓ .wp-toolkit สะอาด"
  wp-toolkit --list 2>/dev/null | grep -qi "$D" && echo "  ⚠ WP Toolkit ยังเห็น!" || echo "  ✓ WP Toolkit สะอาด"
  find /var/softaculous/installations/ -name "*.ini" -exec grep -l "$D" {} \; 2>/dev/null | grep -q . && echo "  ⚠ Softaculous ค้าง!" || echo "  ✓ Softaculous สะอาด"
  echo ""
done
```

ทุกบรรทัดต้องขึ้น ✓ = ลบเกลี้ยง

### ขั้นตอนที่ 6: รัน script ลบ addon domain (ตัวที่มีอยู่แล้ว)

เมื่อ WordPress ถูกลบเกลี้ยงแล้ว ค่อยรัน script ลบ addon domain ตัวที่มีอยู่แล้ว

## คำสั่งทั้งหมด (สรุปรวม)

```bash
# 1) Login เข้า WHM Terminal

# 2) รัน (ดึง script + list จาก GitHub อัตโนมัติ)
bash <(curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh)

# 3) พิมพ์ yes เพื่อยืนยัน

# 4) รอจนเสร็จ → ดู report

# 5) รัน script ลบ addon domain (ตัวที่มีอยู่แล้ว)
```

## ตารางคำสั่ง

รันจาก GitHub โดยตรง (แนะนำ — ได้ script + list ล่าสุดเสมอ):

| คำสั่ง | คำอธิบาย |
|---|---|
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh)` | ดึง list จาก GitHub แล้วลบ (ถาม confirm) |
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh) --dry-run` | ทดสอบก่อน ไม่ลบจริง |
| `bash <(curl -sL URL/wp-bulk-complete-remove.sh) --yes` | ไม่ถาม confirm (ระวัง!) |

หรือดาวน์โหลดมาก่อน (สำหรับคนที่ต้องการเก็บไว้ในเครื่อง):

```bash
curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh -o /usr/local/sbin/wp-bulk-complete-remove.sh && chmod +x /usr/local/sbin/wp-bulk-complete-remove.sh && echo "✓ Installed"
```

จากนั้นรัน:

```bash
wp-bulk-complete-remove.sh
wp-bulk-complete-remove.sh --dry-run
wp-bulk-complete-remove.sh --local     # ใช้ไฟล์ /usr/local/sbin/remove-domains-list.txt แทน GitHub
```

**ข้อแตกต่าง**: รันจาก GitHub ตรงจะได้ทั้ง script + domain list เวอร์ชันล่าสุดทุกครั้ง ถ้าดาวน์โหลดมาก่อนจะใช้ script ตัวในเครื่อง (ถ้ามี update บน GitHub ต้อง curl ใหม่)

## รองรับ 2 โครงสร้าง path

```
/home/USERNAME/DOMAIN/
/home/USERNAME/public_html/DOMAIN/
```

Script จะเช็คทั้ง 2 path ให้อัตโนมัติ

## รองรับหลาย cPanel accounts ต่อ server

```
Server
├── y2026m01sv01 (cPanel #1) — 200+ addon domains
├── y2026m02sv01 (cPanel #2) — 300+ addon domains
└── y2026m03sv01 (cPanel #3) — 200+ addon domains
```

Script หา cPanel username จาก `/etc/userdomains` ให้อัตโนมัติ ข้าม cPanel boundaries ได้

## รองรับ input หลายรูปแบบ

```
domain.com              → domain.com ✓
  domain.com            → domain.com ✓  (ช่องว่างข้างหน้า)
domain.com    ···       → domain.com ✓  (ช่องว่างข้างหลัง)
domain.com/             → domain.com ✓  (มี / ต่อท้าย)
https://domain.com      → domain.com ✓  (มี https://)
http://domain.com/      → domain.com ✓  (มี http:// และ /)
https://domain.com/path → domain.com ✓  (มี path)
# comment               → ข้าม ✓
(บรรทัดว่าง)             → ข้าม ✓
(แต่ space)              → ข้าม ✓
```

## หลักการทำงาน

```
remove-domains-list.txt (จาก GitHub)
  ↓
แต่ละ domain:
  ↓
หา cPanel username จาก /etc/userdomains
  ↓
หา WordPress root (เช็ค 2 paths)
  ↓
อ่าน DB name + DB user จาก wp-config.php
  ↓
Step 1 — Remove (sequential, ทีละตัว):
  ลอง wp-toolkit --remove ก่อน
    สำเร็จ → ลบ files + DB + WP Toolkit record ครบ
    ล้มเหลว → fallback ลบ manual (DROP DB + rm -rf)
  ↓
Step 2 — Deep Cleanup:
  ① .wp-toolkit/ dirs        ⑥ Softaculous record
  ② .wp-toolkit-ignore       ⑦ wp-cron entries
  ③ .lscache/                ⑧ WP Toolkit logs
  ④ wordpress-backups/       ⑨ orphaned DB user
  ⑤ cache/upgrade/tmp dirs   ⑩ empty leftover directory
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

## ทำไมไม่ใช้ WP Toolkit GUI ลบ

WP Toolkit GUI ไม่เหมาะกับการลบ 500+ sites เพราะ:
- **Memory exhausted** — WP Toolkit ใช้ PHP memory ของ WHM ที่จำกัด 128MB
- **Timeout 60 วินาที** — bulk operation เกิน timeout แล้วค้าง
- **Cloudflare 524** — ตัด connection หลัง 100 วินาที
- **ไม่ลบ DB user** — เหลือ orphaned DB users สะสม
- **ไม่ cleanup .wp-toolkit dirs** — สะสมได้ถึง 19GB ต่อ site
- **ค้างบ่อย** — "backend API failed with status code 500"

Script นี้ทำงานที่ shell level โดยตรง ไม่ผ่าน UI → ไม่มีปัญหาเหล่านี้

## License

MIT
