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
- SSH เข้าด้วย root
- มี `/etc/userdomains` (มาพร้อม cPanel)

## ติดตั้ง (ครั้งเดียว)

```bash
curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh -o /usr/local/sbin/wp-bulk-complete-remove.sh && chmod +x /usr/local/sbin/wp-bulk-complete-remove.sh && echo "✓ Installed"
```

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

### ขั้นตอนที่ 2: SSH เข้าเซิร์ฟเวอร์

```bash
ssh root@IP_เซิร์ฟเวอร์
```

### ขั้นตอนที่ 3: รัน script

```bash
wp-bulk-complete-remove.sh
```

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

### ขั้นตอนที่ 5: รัน script ลบ addon domain (ตัวที่มีอยู่แล้ว)

เมื่อ WordPress ถูกลบเกลี้ยงแล้ว ค่อยรัน script ลบ addon domain ตัวที่มีอยู่แล้ว

## ตารางคำสั่ง

| คำสั่ง | คำอธิบาย |
|---|---|
| `wp-bulk-complete-remove.sh` | ดึง list จาก GitHub แล้วลบ (ถาม confirm) |
| `wp-bulk-complete-remove.sh --dry-run` | ทดสอบก่อน ไม่ลบจริง |
| `wp-bulk-complete-remove.sh --yes` | ไม่ถาม confirm (ระวัง!) |
| `wp-bulk-complete-remove.sh --local` | ใช้ไฟล์ local แทน GitHub |

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
  ลบ .wp-toolkit/ dirs
  ลบ .wp-toolkit-ignore
  ลบ orphaned DB user
  ลบ Softaculous record
  ลบ .lscache/
  ลบ wordpress-backups/
  ลบ cache/upgrade/tmp dirs
  ลบ wp-cron entries
  ลบ WP Toolkit logs
  ลบ empty leftover directory
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

## อัปเดต

```bash
curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh -o /usr/local/sbin/wp-bulk-complete-remove.sh && chmod +x /usr/local/sbin/wp-bulk-complete-remove.sh && echo "✓ Updated"
```

## ถอนการติดตั้ง

```bash
rm -f /usr/local/sbin/wp-bulk-complete-remove.sh
rm -rf /var/log/wp-bulk-remove/
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
