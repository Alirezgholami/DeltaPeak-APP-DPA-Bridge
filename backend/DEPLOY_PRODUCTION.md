# DPA Backend — Production Deployment v0.5.0

این راهنما برای یک VPS لینوکسی با Docker Compose و یک دامنه/ساب‌دامنه مانند `api.example.com` است.

## آنچه قبل از استقرار لازم است

1. یک VPS دارای IP عمومی.
2. یک رکورد DNS برای دامنه API که به IP سرور اشاره کند.
3. پورت‌های TCP 80 و 443 روی سرور باز باشند؛ UDP 443 برای HTTP/3 اختیاری ولی در Compose فعال است.
4. حساب سرویس پیامک. برای Kavenegar: API key و Template تأییدشده برای ثبت‌نام و بازیابی رمز.

Caddy جلوی Backend قرار می‌گیرد؛ API پورت 8080 را روی Host منتشر نمی‌کند. Caddy برای دامنه عمومی HTTPS را خودکار دریافت و تمدید می‌کند.

## 1) ساخت فایل Production

```bash
cd backend
python scripts/init_production_env.py --output .env.production
nano .env.production
```

حداقل این مقادیر را تکمیل کنید:

```text
DPA_API_DOMAIN=api.your-domain.example
DPA_KAVENEGAR_API_KEY=...
DPA_KAVENEGAR_SIGNUP_TEMPLATE=...
DPA_KAVENEGAR_RESET_TEMPLATE=...
```

سه Secret اصلی به‌صورت تصادفی تولید شده‌اند؛ آن‌ها را تغییر ندهید مگر اینکه عمداً Secret rotation انجام می‌دهید.

## 2) Preflight و اجرا

```bash
python scripts/production_preflight.py .env.production
./scripts/deploy_production.sh .env.production
```

بررسی سرویس‌ها:

```bash
docker compose --env-file .env.production ps
curl https://api.your-domain.example/ready
```

یا:

```bash
python scripts/smoke_test.py https://api.your-domain.example
```

## 3) ساخت Owner اولیه

Owner باید داخل Container ساخته شود؛ رمز را در command history ننویسید:

```bash
docker compose --env-file .env.production exec \
  -e DPA_OWNER_MOBILE=09xxxxxxxxx \
  -e DPA_OWNER_NAME='DPA Owner' \
  api python -m app.bootstrap_owner
```

فرمان رمز را به‌صورت تعاملی درخواست می‌کند.

## 4) Backup پایگاه حساب‌ها

```bash
./scripts/backup_postgres.sh .env.production
```

خروجی در `backend/backups/` ایجاد می‌شود و برای آن SHA-256 نیز ساخته می‌شود. این پوشه در `.gitignore` است.

## 5) اتصال APK

APK فقط آدرس عمومی API را می‌گیرد؛ هیچ Secret سرور داخل APK قرار نمی‌گیرد:

```bash
flutter build apk --release \
  --dart-define=DPA_API_BASE_URL=https://api.your-domain.example
```

نسخه Release خود اپ نیز اتصال Backend غیر HTTPS را رد می‌کند.

## 6) GitHub Production signing

Workflow `Release DPA Signed Android APK` این Secrets را نیاز دارد:

- `DPA_API_BASE_URL` — آدرس HTTPS عمومی API.
- `DPA_ANDROID_KEYSTORE_BASE64` — محتوای Base64 کلید JKS.
- `DPA_ANDROID_KEY_ALIAS`
- `DPA_ANDROID_KEY_PASSWORD`
- `DPA_ANDROID_STORE_PASSWORD`

ساخت یک keystore جدید:

```bash
bash tool/generate_release_keystore.sh dpa-release.jks dpa-release
```

از keystore و Passwordهای آن حداقل دو Backup امن جداگانه نگهداری کنید. گم‌شدن کلید Release می‌تواند به‌روزرسانی مستقیم همان نصب/انتشار را دشوار یا غیرممکن کند.
